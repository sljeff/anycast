import UIKit

/// The MyProgressBar gating state (formatters.dart:89-116
/// playbackProgressVisualState): no episode / loading / zero duration each
/// swap the bar to a message, dim it to 0.48 and block seeking.
enum PlayerProgressVisualState: Equatable {

    /// The drained-player message, shared by every surface that names the
    /// state (the transport's progress message and the episode/transcript
    /// capsules) — one state, one string. Reached when the queue finishes
    /// or the playing head is removed while the sheet is open; a normal
    /// end state, so no fault wording.
    static let nothingPlayingMessage = "Nothing playing"

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

    /// `unavailable` wording is reserved for the "an episode exists but
    /// this datum is missing" family (Duration unavailable, Translation
    /// unavailable) — disjoint from `.disabled`, which never has an
    /// episode.
    var message: String? {
        switch self {
        case .normal: nil
        case .loading: "Loading…"
        case .unknownDuration: "Duration unavailable"
        case .disabled: Self.nothingPlayingMessage
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
/// over audio_video_progress_bar), in the Anycast 2.0 scrubber form: a 6 pt
/// rounded track (white 12%, buffered 24%) in a 40 pt touch band, with a
/// white played segment whose rounded head IS the position indicator (no
/// separate thumb). The head stays a full semicircle at ANY fraction — a
/// plain rounded rect clamps its corner radius to width/2, which rendered
/// the first seconds of playback as a square-cornered stub. Elapsed and
/// remaining times sit BELOW the ends (monospaced digits).
///
/// Holding the bar (UI kit scrubber physics): the track grows to 12 pt and
/// widens past its ends, a time bubble follows the finger above the track
/// (09 §9 — touching shows the position, dragging updates it, releasing
/// restores the resting look and keeps the new position), and dragging
/// past either end stretches the track like a rubber band. Drag (or tap)
/// anywhere seeks through `onSeek(positionMilliseconds:)` on release.
final class PlayerProgressBarView: UIControl {

    var onSeek: (@MainActor (Int64) -> Void)?

    /// The touch band the bar sits in (unchanged hit area and layout).
    private static let barHeight: CGFloat = 40
    /// Drawn track thickness while held (Anycast 2.0 UI kit scrubber: the
    /// track grows under the finger); at rest it is scaled to half,
    /// `Spacing.playerProgress` (6 pt).
    private static let trackHeight: CGFloat = 12
    private static let restScale: CGFloat = Spacing.playerProgress / trackHeight
    /// Width of a chapter gap in the track.
    private static let chapterGap: CGFloat = 2

    /// The bar layers live in their own corner-clipped container: the round
    /// head sticks past the track's leading cap at small fractions and must
    /// grow OUT of the cap. View-level clipping (not a CAShapeLayer mask —
    /// those do not rasterize under plain `layer.render` harnesses, which
    /// silently hid the whole fill). Test-visible like `indicator` above.
    let barContainer = UIView()
    private let trackLayer = CAShapeLayer()
    private let bufferedLayer = CAShapeLayer()
    private let playedLayer = CAShapeLayer()
    /// Chapter starts cut thin gaps through the track (page ground colour).
    private let chapterLayer = CAShapeLayer()
    private var chapterStartsMilliseconds: [Int64] = []
    /// The message the a11y value carries while seeking is blocked
    /// (`setAllowsSeek`); nil while adjustable.
    private var disabledStatusMessage: String?
    private let positionLabel = UILabel()
    private let remainingLabel = UILabel()
    /// The time bubble shown above the track while held.
    private let timeBubble = UIView()
    private let timeBubbleLabel = UILabel()
    private var timeBubbleCenterX: NSLayoutConstraint!
    private var overscroll: CGFloat = 0

    private var positionMilliseconds: Int64 = 0
    private var bufferedMilliseconds: Int64 = 0
    private var durationMilliseconds: Int64 = 0
    private var isDragging = false
    private var dragPositionMilliseconds: Int64 = 0
    private lazy var dragClaim = HorizontalDragClaim(owner: self)

    init() {
        super.init(frame: CGRect(x: 0, y: 0, width: 320, height: Self.barHeight + 20))

        // Static player-page tokens (trait-independent): the player stays
        // warm-dark in both appearances (09 §2.1), and CAShapeLayer fill
        // colors snapshot `.cgColor` at config time — a dynamic color here
        // would freeze whatever trait was ambient.
        trackLayer.fillColor = UIColor.white.withAlphaComponent(0.12).cgColor
        bufferedLayer.fillColor = UIColor.white.withAlphaComponent(0.24).cgColor
        playedLayer.fillColor = Theme.playerText.cgColor
        chapterLayer.fillColor = Theme.playerBackground.cgColor
        barContainer.clipsToBounds = true
        barContainer.layer.cornerRadius = Self.trackHeight / 2
        barContainer.transform = CGAffineTransform(scaleX: 1, y: Self.restScale)
        // The control tracks touches itself; the container is pure chrome.
        barContainer.isUserInteractionEnabled = false
        barContainer.translatesAutoresizingMaskIntoConstraints = false
        addSubview(barContainer)
        for layer in [trackLayer, bufferedLayer, playedLayer, chapterLayer] {
            barContainer.layer.addSublayer(layer)
        }
        NSLayoutConstraint.activate([
            barContainer.leadingAnchor.constraint(equalTo: leadingAnchor),
            barContainer.trailingAnchor.constraint(equalTo: trailingAnchor),
            // Centered in the top touch band; the time labels sit below.
            barContainer.centerYAnchor.constraint(equalTo: topAnchor, constant: Self.barHeight / 2),
            barContainer.heightAnchor.constraint(equalToConstant: Self.trackHeight),
        ])
        layoutBarLayers()

        for label in [positionLabel, remainingLabel] {
            // Monospaced digits keep the ticking times from jittering.
            label.font = TypographyV2.meta.font().monospacedDigits()
            label.textColor = Theme.playerSecondary
            label.adjustsFontForContentSizeCategory = true
            label.translatesAutoresizingMaskIntoConstraints = false
            addSubview(label)
        }

        timeBubbleLabel.font = TypographyV2.emphasis.font().monospacedDigits()
        timeBubbleLabel.adjustsFontForContentSizeCategory = true
        timeBubbleLabel.textColor = Theme.playerBackground
        timeBubbleLabel.translatesAutoresizingMaskIntoConstraints = false
        timeBubble.backgroundColor = Theme.playerText
        timeBubble.layer.cornerRadius = Radius.sm
        timeBubble.layer.cornerCurve = .continuous
        timeBubble.alpha = 0
        timeBubble.isUserInteractionEnabled = false
        timeBubble.translatesAutoresizingMaskIntoConstraints = false
        timeBubble.addSubview(timeBubbleLabel)
        addSubview(timeBubble)
        timeBubbleCenterX = timeBubble.centerXAnchor.constraint(equalTo: leadingAnchor)
        timeBubbleCenterX.priority = .defaultHigh

        NSLayoutConstraint.activate([
            // Labels sit inside the control, in the band below the bar.
            positionLabel.leadingAnchor.constraint(equalTo: leadingAnchor),
            positionLabel.topAnchor.constraint(equalTo: barContainer.centerYAnchor, constant: Spacing.md),
            remainingLabel.trailingAnchor.constraint(equalTo: trailingAnchor),
            remainingLabel.topAnchor.constraint(equalTo: barContainer.centerYAnchor, constant: Spacing.md),

            timeBubbleLabel.topAnchor.constraint(equalTo: timeBubble.topAnchor, constant: Spacing.sm),
            timeBubbleLabel.bottomAnchor.constraint(equalTo: timeBubble.bottomAnchor, constant: -Spacing.sm),
            timeBubbleLabel.leadingAnchor.constraint(equalTo: timeBubble.leadingAnchor, constant: Spacing.gap),
            timeBubbleLabel.trailingAnchor.constraint(equalTo: timeBubble.trailingAnchor, constant: -Spacing.gap),
            // Floats above the control, following the finger, kept on screen.
            timeBubble.bottomAnchor.constraint(equalTo: barContainer.topAnchor, constant: -Spacing.md),
            timeBubbleCenterX,
            timeBubble.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor),
            timeBubble.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor),
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

    /// The 40 pt bar + 20 pt label band; width is host-driven. Without an
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

    /// Chapter starts to mark on the track (the first, at 0, is skipped).
    func setChapterMarks(_ startsMilliseconds: [Int64]) {
        guard startsMilliseconds != chapterStartsMilliseconds else { return }
        chapterStartsMilliseconds = startsMilliseconds
        render()
    }

    /// Dart IgnorePointer + 0.48 opacity when the visual state disallows
    /// seeking; time labels hidden (timeLabelLocation .none). The
    /// adjustable trait goes with it — VoiceOver must not announce a
    /// control it can adjust when seeking is blocked; the status message
    /// (`Loading…` / `Nothing playing`) becomes the value instead.
    func setAllowsSeek(_ allows: Bool, statusMessage: String? = nil) {
        isEnabled = allows
        alpha = allows ? 1 : 0.48
        positionLabel.isHidden = !allows
        remainingLabel.isHidden = !allows
        accessibilityTraits = allows ? [.adjustable] : []
        disabledStatusMessage = statusMessage
        accessibilityValue = allows
            ? accessibilityValue
            : statusMessage
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
        let rect = CGRect(x: 0, y: 0, width: clamped, height: Self.trackHeight)
        let path = UIBezierPath(roundedRect: rect, cornerRadius: Self.trackHeight / 2)
        path.append(UIBezierPath(ovalIn: CGRect(
            x: clamped - Self.trackHeight, y: 0,
            width: Self.trackHeight, height: Self.trackHeight
        )))
        return path.cgPath
    }

    private func render() {
        guard bounds.width > 1 else { return }
        let duration = max(durationMilliseconds, 0)

        // All bar geometry is in bar-local (layer) space; the layers sit at
        // barRect via layoutBarLayers.
        trackLayer.path = UIBezierPath(
            roundedRect: CGRect(x: 0, y: 0, width: bounds.width, height: Self.trackHeight),
            cornerRadius: Self.trackHeight / 2
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

        let marks = UIBezierPath()
        if duration > 0 {
            for start in chapterStartsMilliseconds where start > 0 && start < duration {
                let markX = x(forFraction: Double(start) / Double(duration))
                marks.append(UIBezierPath(rect: CGRect(
                    x: markX - Self.chapterGap / 2, y: 0, width: Self.chapterGap, height: Self.trackHeight
                )))
            }
        }
        chapterLayer.path = marks.cgPath

        positionLabel.text = PlayerProgressClock.positionText(effectivePosition)
        timeBubbleLabel.text = positionLabel.text
        timeBubbleCenterX.constant = x(forFraction: playedFraction)
        remainingLabel.text = PlayerProgressClock.remainingText(
            positionMilliseconds: effectivePosition,
            durationMilliseconds: duration
        )
        // While blocked, the clock reads 0:00 of 0:00 — the status message
        // is the honest value (see setAllowsSeek).
        accessibilityValue = isEnabled
            ? PlayerProgressClock.accessibilityValue(
                positionMilliseconds: effectivePosition,
                durationMilliseconds: duration
            )
            : disabledStatusMessage
    }

    private func layoutBarLayers() {
        // The bar layers fill the clipped container (anchored to the
        // control's bottom by constraints); their paths are in the same
        // bar-local space.
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let size = barContainer.bounds.size
        for layer in [trackLayer, bufferedLayer, playedLayer, chapterLayer] {
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

    /// Resting: 6 pt track at full width. Held: 12 pt, widened past both
    /// ends, shifted by any rubber-band overscroll.
    private func barTransform(expanded: Bool) -> CGAffineTransform {
        guard expanded else { return CGAffineTransform(scaleX: 1, y: Self.restScale) }
        let widen = 1 + Motion.scrubberFocusOutset * 2 / max(bounds.width, 1)
        return CGAffineTransform(translationX: Motion.rubberBand(overscroll), y: 0)
            .scaledBy(x: widen, y: 1)
    }

    /// Grows the track under the finger (with the time bubble) and settles
    /// it back on release.
    private func setExpanded(_ expanded: Bool) {
        if !expanded { overscroll = 0 }
        let transform = barTransform(expanded: expanded)
        let bubbleAlpha: CGFloat = expanded ? 1 : 0
        guard !Motion.reduceMotion else {
            barContainer.transform = transform
            timeBubble.alpha = bubbleAlpha
            return
        }
        UIView.animate(
            withDuration: expanded ? Motion.pressRelease : Motion.standard, delay: 0,
            usingSpringWithDamping: 0.7, initialSpringVelocity: 0,
            options: [.allowUserInteraction, .beginFromCurrentState]
        ) {
            self.barContainer.transform = transform
            self.timeBubble.alpha = bubbleAlpha
        }
    }

    /// Tracks the finger; past either end the overscroll feeds the rubber band.
    private func track(_ touch: UITouch) {
        let x = touch.location(in: self).x
        dragPositionMilliseconds = position(atX: x)
        overscroll = x < 0 ? x : (x > bounds.width ? x - bounds.width : 0)
        if !Motion.reduceMotion {
            barContainer.transform = barTransform(expanded: true)
        }
        render()
    }

    override func beginTracking(_ touch: UITouch, with event: UIEvent?) -> Bool {
        Haptics.scrubberGrab()
        isDragging = true
        track(touch)
        setExpanded(true)
        return true
    }

    override func continueTracking(_ touch: UITouch, with event: UIEvent?) -> Bool {
        track(touch)
        return true
    }

    override func endTracking(_ touch: UITouch?, with event: UIEvent?) {
        let target = touch.map { position(atX: $0.location(in: self).x) } ?? dragPositionMilliseconds
        setExpanded(false)
        isDragging = false
        dragPositionMilliseconds = target
        render()
        if isEnabled {
            Haptics.seekCommit()
            onSeek?(target)
        }
    }

    override func cancelTracking(with event: UIEvent?) {
        setExpanded(false)
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
