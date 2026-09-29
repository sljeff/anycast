import UIKit

/// The MyProgressBar gating state (formatters.dart:89-116
/// playbackProgressVisualState): no episode / loading / zero duration each
/// swap the bar to a message, dim it to 0.48 and block seeking.
enum PlayerProgressVisualState: Equatable {

    case normal
    case loading
    case unknownDuration
    case disabled

    /// Dart ladder order: no episode → loading → zero duration → normal.
    static func resolve(hasEpisode: Bool, isLoading: Bool, durationMilliseconds: Int64) -> PlayerProgressVisualState {
        if !hasEpisode { return .disabled }
        if isLoading { return .loading }
        if durationMilliseconds <= 0 { return .unknownDuration }
        return .normal
    }

    var message: String? {
        switch self {
        case .normal: nil
        case .loading: "Loading…"
        case .unknownDuration: "Duration unavailable"
        case .disabled: "Playback unavailable"
        }
    }

    var allowsSeek: Bool { self == .normal }
}

/// Clock strings for the progress bar's above-bar labels, porting
/// audio_video_progress_bar 2.0.3 `_getTimeString`/`TimeLabelType.remainingTime`
/// (the shipped MyProgressBar, player.dart:413-460): left label is the
/// position `m:ss` / `h:mm:ss` (minutes unpadded under an hour), right label
/// is the negated remaining `-m:ss`.
enum PlayerProgressClock {

    static func positionText(_ milliseconds: Int64) -> String {
        clock(max(milliseconds, 0))
    }

    static func remainingText(positionMilliseconds: Int64, durationMilliseconds: Int64) -> String {
        let remaining = max(durationMilliseconds - positionMilliseconds, 0)
        return "-\(clock(remaining))"
    }

    private static func clock(_ milliseconds: Int64) -> String {
        let totalSeconds = milliseconds / 1000
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds / 60) % 60
        let seconds = totalSeconds % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%d:%02d", minutes, seconds)
    }

    /// The a11y summary ("3:05 of 59:12").
    static func accessibilityValue(positionMilliseconds: Int64, durationMilliseconds: Int64) -> String {
        "\(positionText(positionMilliseconds)) of \(positionText(durationMilliseconds))"
    }
}

/// The player progress bar (self-drawn widget #4, 07 §2.4; Dart MyProgressBar
/// over audio_video_progress_bar): 40 pt-tall rounded-caps bar on 0x232830
/// with a white 5% buffered segment and a white played segment — the
/// played segment's rounded head IS the position indicator (no separate
/// thumb: a same-white knob would be invisible against the fill, and the
/// Dart glow halo read as a dark ring over the track). The head stays a
/// full semicircle at ANY fraction — a plain rounded rect clamps its
/// corner radius to width/2, which rendered the first seconds of playback
/// as a square-cornered stub. Time labels sit ABOVE the ends (12 pt
/// comfortaa w700 white; right label shows REMAINING time). Drag (or tap)
/// anywhere on the control seeks through `onSeek(positionMilliseconds:)`
/// on release.
final class PlayerProgressBarView: UIControl {

    var onSeek: (@MainActor (Int64) -> Void)?

    private static let barHeight: CGFloat = 40

    /// The bar layers live in their own corner-clipped container: the round
    /// head sticks past the track's leading cap at small fractions and must
    /// grow OUT of the cap. View-level clipping (not a CAShapeLayer mask —
    /// those do not rasterize under plain `layer.render` harnesses, which
    /// silently hid the whole fill). Test-visible like `indicator` above.
    let barContainer = UIView()
    private let trackLayer = CAShapeLayer()
    private let bufferedLayer = CAShapeLayer()
    private let playedLayer = CAShapeLayer()
    private let positionLabel = UILabel()
    private let remainingLabel = UILabel()

    private var positionMilliseconds: Int64 = 0
    private var bufferedMilliseconds: Int64 = 0
    private var durationMilliseconds: Int64 = 0
    private var isDragging = false
    private var dragPositionMilliseconds: Int64 = 0
    private lazy var dragClaim = HorizontalDragClaim(owner: self)

    init() {
        super.init(frame: CGRect(x: 0, y: 0, width: 320, height: Self.barHeight + 20))

        trackLayer.fillColor = Theme.cardBackground.cgColor
        bufferedLayer.fillColor = UIColor.white.withAlphaComponent(0.05).cgColor
        playedLayer.fillColor = UIColor.white.cgColor
        barContainer.clipsToBounds = true
        barContainer.layer.cornerRadius = Self.barHeight / 2
        // The control tracks touches itself; the container is pure chrome.
        barContainer.isUserInteractionEnabled = false
        barContainer.translatesAutoresizingMaskIntoConstraints = false
        addSubview(barContainer)
        for layer in [trackLayer, bufferedLayer, playedLayer] {
            barContainer.layer.addSublayer(layer)
        }
        NSLayoutConstraint.activate([
            barContainer.leadingAnchor.constraint(equalTo: leadingAnchor),
            barContainer.trailingAnchor.constraint(equalTo: trailingAnchor),
            barContainer.bottomAnchor.constraint(equalTo: bottomAnchor),
            barContainer.heightAnchor.constraint(equalToConstant: Self.barHeight),
        ])
        layoutBarLayers()

        for label in [positionLabel, remainingLabel] {
            label.font = UIFontMetrics(forTextStyle: .caption1).scaledFont(
                for: UIFont(name: "Comfortaa-Bold", size: 12) ?? .systemFont(ofSize: 12, weight: .bold)
            )
            label.textColor = .white
            label.adjustsFontForContentSizeCategory = true
            label.translatesAutoresizingMaskIntoConstraints = false
            addSubview(label)
        }

        NSLayoutConstraint.activate([
            // Labels sit inside the control, in the 20 pt band above the bar.
            positionLabel.leadingAnchor.constraint(equalTo: leadingAnchor),
            positionLabel.bottomAnchor.constraint(
                equalTo: bottomAnchor, constant: -(Self.barHeight + 4)
            ),
            remainingLabel.trailingAnchor.constraint(equalTo: trailingAnchor),
            remainingLabel.bottomAnchor.constraint(
                equalTo: bottomAnchor, constant: -(Self.barHeight + 4)
            ),
        ])

        isAccessibilityElement = true
        accessibilityTraits = [.adjustable]
        accessibilityLabel = "Playback position"
        isExclusiveTouch = true
        // Beat the cover container for spare vertical space in the .fill
        // stack — the bar must stay at its intrinsic height.
        setContentHuggingPriority(.required, for: .vertical)
        render()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        dragClaim.installWhenInWindow()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    /// 20 pt label band + the 40 pt bar; width is host-driven. Without an
    /// intrinsic height a `.fill` stack either collapses the control or —
    /// losing the hugging tie against a plain UIView sibling — stretches
    /// it far past the design height.
    override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: Self.barHeight + 20)
    }

    // MARK: - State push (per-frame from the playback observation)

    func update(positionMilliseconds: Int64, bufferedMilliseconds: Int64, durationMilliseconds: Int64) {
        self.positionMilliseconds = positionMilliseconds
        self.bufferedMilliseconds = bufferedMilliseconds
        self.durationMilliseconds = durationMilliseconds
        render()
    }

    /// Dart IgnorePointer + 0.48 opacity when the visual state disallows
    /// seeking; time labels hidden (timeLabelLocation .none).
    func setAllowsSeek(_ allows: Bool) {
        isEnabled = allows
        alpha = allows ? 1 : 0.48
        positionLabel.isHidden = !allows
        remainingLabel.isHidden = !allows
    }

    // MARK: - Drawing

    /// No thumb inset: the played head travels the full track — fraction 0
    /// is the capsule's leading cap, fraction 1 its trailing cap.
    private func x(forFraction fraction: Double) -> CGFloat {
        CGFloat(min(max(fraction, 0), 1)) * bounds.width
    }

    /// Fill-segment path in BAR-LOCAL space (the layers sit inside the
    /// clipped bar container). The head is always a full semicircle: the
    /// rounded rect alone clamps its corner radius to width/2, so the
    /// first seconds of playback rendered as a square-cornered stub; the
    /// unioned head circle keeps the round contour while the container's
    /// corner clipping contains whatever sticks past the track's caps.
    private func fillPath(width: CGFloat) -> CGPath? {
        guard width > 0.5 else { return nil }
        let clamped = min(width, bounds.width)
        let rect = CGRect(x: 0, y: 0, width: clamped, height: Self.barHeight)
        let path = UIBezierPath(roundedRect: rect, cornerRadius: Self.barHeight / 2)
        path.append(UIBezierPath(ovalIn: CGRect(
            x: clamped - Self.barHeight, y: 0,
            width: Self.barHeight, height: Self.barHeight
        )))
        return path.cgPath
    }

    private func render() {
        guard bounds.width > 1 else { return }
        let duration = max(durationMilliseconds, 0)

        // All bar geometry is in bar-local (layer) space; the layers sit at
        // barRect via layoutBarLayers.
        trackLayer.path = UIBezierPath(
            roundedRect: CGRect(x: 0, y: 0, width: bounds.width, height: Self.barHeight),
            cornerRadius: Self.barHeight / 2
        ).cgPath

        let bufferedFraction = duration > 0
            ? min(Double(max(bufferedMilliseconds, 0)) / Double(duration), 1)
            : 0
        bufferedLayer.path = fillPath(width: x(forFraction: bufferedFraction))

        let effectivePosition = isDragging ? dragPositionMilliseconds : positionMilliseconds
        let playedFraction = duration > 0
            ? min(Double(max(effectivePosition, 0)) / Double(duration), 1)
            : 0
        // The played segment's rounded head is the position indicator.
        playedLayer.path = fillPath(width: x(forFraction: playedFraction))

        positionLabel.text = PlayerProgressClock.positionText(effectivePosition)
        remainingLabel.text = PlayerProgressClock.remainingText(
            positionMilliseconds: effectivePosition,
            durationMilliseconds: duration
        )
        accessibilityValue = PlayerProgressClock.accessibilityValue(
            positionMilliseconds: effectivePosition,
            durationMilliseconds: duration
        )
    }

    private func layoutBarLayers() {
        // The bar layers fill the clipped container (anchored to the
        // control's bottom by constraints); their paths are in the same
        // bar-local space.
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let size = barContainer.bounds.size
        for layer in [trackLayer, bufferedLayer, playedLayer] {
            layer.frame = CGRect(origin: .zero, size: size)
        }
        CATransaction.commit()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        layoutBarLayers()
        render()
    }

    // MARK: - Drag-to-seek (onSeek fires on release, like ProgressBar)

    private func position(atX x: CGFloat) -> Int64 {
        let fraction = bounds.width > 0 ? min(max(x / bounds.width, 0), 1) : 0
        return Int64(Double(fraction) * Double(max(durationMilliseconds, 0)))
    }

    override func beginTracking(_ touch: UITouch, with event: UIEvent?) -> Bool {
        isDragging = true
        dragPositionMilliseconds = position(atX: touch.location(in: self).x)
        render()
        return true
    }

    override func continueTracking(_ touch: UITouch, with event: UIEvent?) -> Bool {
        dragPositionMilliseconds = position(atX: touch.location(in: self).x)
        render()
        return true
    }

    override func endTracking(_ touch: UITouch?, with event: UIEvent?) {
        isDragging = false
        let target = touch.map { position(atX: $0.location(in: self).x) } ?? dragPositionMilliseconds
        dragPositionMilliseconds = target
        render()
        if isEnabled {
            onSeek?(target)
        }
    }

    override func cancelTracking(with event: UIEvent?) {
        isDragging = false
        render()
    }

    // MARK: - Accessibility

    override func accessibilityIncrement() {
        step(by: 10_000)
    }

    override func accessibilityDecrement() {
        step(by: -10_000)
    }

    private func step(by delta: Int64) {
        guard isEnabled else { return }
        let duration = max(durationMilliseconds, 0)
        let target = min(max(positionMilliseconds + delta, 0), duration)
        onSeek?(target)
    }
}
