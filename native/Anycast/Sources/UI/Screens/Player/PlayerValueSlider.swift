import UIKit
import AnycastKit

/// Pure stop math for the two player sliders (SPEED 0.5–2.0 ×0.25 and
/// COUNTDOWN 0–60 ×10 — Dart `Slider(min:max:divisions: 6)`, seven stops
/// each) plus the Dart `toStringAsFixed(1)` thumb-text parity. Kept free of
/// UIKit so the AnycastAppTests suite can pin the arithmetic.
enum PlayerSliderMath {

    /// `divisions` splits the range into divisions+1 stops
    /// (divisions 6 → 7 stops).
    static func stops(min: Double, max: Double, divisions: Int) -> [Double] {
        guard divisions > 0, max > min else { return [min] }
        return (0...divisions).map { min + (max - min) * Double($0) / Double(divisions) }
    }

    /// The stop a raw value snaps to (Material slider snap; ties go to the
    /// nearer lower-middle by distance compare).
    static func nearestIndex(for value: Double, in stops: [Double]) -> Int {
        guard stops.count > 1 else { return 0 }
        var best = 0
        var bestDistance = abs(value - stops[0])
        for (index, stop) in stops.enumerated().dropFirst() {
            let distance = abs(value - stop)
            if distance < bestDistance {
                best = index
                bestDistance = distance
            }
        }
        return best
    }

    /// Dart `speed.toStringAsFixed(1)` for the SPEED thumb (player.dart:1496):
    /// one decimal, ties rounded AWAY FROM ZERO — 0.75 renders "0.8",
    /// 1.25 "1.3", 1.75 "1.8" (printf-style %.1f would give "1.2" at 1.25
    /// on some paths; this reproduces the shipped strings exactly).
    static func dartFixed1(_ value: Double) -> String {
        let scaled = (value * 10).rounded(.awayFromZero)
        let whole = Int(scaled)
        let sign = whole < 0 ? "-" : ""
        let magnitude = abs(whole)
        return "\(sign)\(magnitude / 10).\(magnitude % 10)"
    }

    /// SPEED thumb text: the stop value at one decimal (Dart passes the
    /// slider `label` into the painted thumb).
    static func speedThumbText(_ value: Double) -> String {
        dartFixed1(value)
    }

    /// COUNTDOWN thumb text: `formatCountdown(countdownDuration)` — the LIVE
    /// remaining time, not the dragged stop (player.dart:1542-1543); OFF
    /// when no countdown is running.
    static func countdownThumbText(remainingMilliseconds: Int64?) -> String {
        TimeFormats.formatCountdown(remainingMilliseconds ?? -1)
    }
}

/// The thumb-shows-value snapped slider (self-drawn widget #5, 07 §2.4/§3;
/// Dart CustomSliderThumbCircle, player.dart:1084-1146): a 48 pt stadium
/// capsule on 0x232830 with a white 20 pt-radius thumb carrying the value
/// text (12 pt bold, 0x111316) and 4 pt tick dots at the stops. No visible
/// track fill — the Dart theme drew it at height 0; only ticks and thumb
/// ride the capsule.
final class PlayerValueSlider: UIControl {

    enum TickStyle {
        /// SPEED: every tick dot is white.
        case allWhite
        /// COUNTDOWN: white up to the active stop, hidden after
        /// (inactive dots painted 0x232830, invisible on the capsule).
        case whiteUpToActive
    }

    struct Spec {
        let values: [Double]
        let tickStyle: TickStyle
    }

    /// User-driven stop change (index, value). Programmatic `select` never
    /// fires this.
    var onValueChanged: (@MainActor (Int, Double) -> Void)?

    let spec: Spec
    private(set) var selectedIndex: Int

    private static let thumbRadius: CGFloat = 20
    private static let tickRadius: CGFloat = 4
    private static let capsuleHeight: CGFloat = 48

    private let thumbView = UIView()
    private let thumbLabel = UILabel()
    private var tickLayers: [CAShapeLayer] = []
    private let textProvider: @MainActor (Double) -> String
    private var textValue: Double
    private lazy var dragClaim = HorizontalDragClaim(owner: self)

    init(spec: Spec, initialIndex: Int, thumbText: @escaping @MainActor (Double) -> String) {
        self.spec = spec
        self.selectedIndex = min(max(initialIndex, 0), max(spec.values.count - 1, 0))
        self.textProvider = thumbText
        self.textValue = spec.values.indices.contains(selectedIndex) ? spec.values[selectedIndex] : 0

        super.init(frame: CGRect(x: 0, y: 0, width: 240, height: Self.capsuleHeight))

        backgroundColor = Theme.cardBackground
        layer.cornerRadius = Self.capsuleHeight / 2
        layer.cornerCurve = .continuous
        clipsToBounds = true

        for _ in spec.values {
            let dot = CAShapeLayer()
            dot.fillColor = UIColor.white.cgColor
            layer.addSublayer(dot)
            tickLayers.append(dot)
        }

        thumbView.backgroundColor = Theme.primaryLightMax
        thumbView.layer.cornerRadius = Self.thumbRadius
        thumbView.layer.cornerCurve = .continuous
        thumbView.frame = CGRect(x: 0, y: 0, width: Self.thumbRadius * 2, height: Self.thumbRadius * 2)
        // A plain UIView swallows hit-testing, so a drag STARTING on the
        // thumb never reached the control's tracking (the Dart thumb is the
        // drag handle — starting there must work, not be the one dead spot).
        thumbView.isUserInteractionEnabled = false
        addSubview(thumbView)

        // CustomSliderThumbCircle: fontSize = thumbRadius * 0.6, bold,
        // valueIndicatorColor (0x111316) as the text color.
        thumbLabel.font = .systemFont(ofSize: Self.thumbRadius * 0.6, weight: .bold)
        thumbLabel.textColor = Theme.primaryBackgroundDark
        thumbLabel.textAlignment = .center
        thumbLabel.adjustsFontForContentSizeCategory = false
        thumbLabel.translatesAutoresizingMaskIntoConstraints = false
        thumbView.addSubview(thumbLabel)
        NSLayoutConstraint.activate([
            thumbLabel.centerXAnchor.constraint(equalTo: thumbView.centerXAnchor),
            thumbLabel.centerYAnchor.constraint(equalTo: thumbView.centerYAnchor, constant: 0.5),
        ])

        isAccessibilityElement = true
        accessibilityTraits = [.adjustable]
        setContentHuggingPriority(.required, for: .vertical)

        renderThumb()
        isExclusiveTouch = true
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        dragClaim.installWhenInWindow()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    /// The 48 pt capsule is the control's fixed height (Dart `SizedBox
    /// height: 48`); width is host-driven. Without an intrinsic height a
    /// vertical stack gives the control zero height.
    override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: Self.capsuleHeight)
    }

    // MARK: - State

    /// Programmatic selection (no callback); re-renders thumb and ticks.
    func select(index: Int) {
        let clamped = min(max(index, 0), max(spec.values.count - 1, 0))
        guard clamped != selectedIndex else { return }
        selectedIndex = clamped
        renderThumb()
        renderTicks()
    }

    /// Refreshes only the thumb text (the COUNTDOWN label ticks live while
    /// the selected stop stays put).
    func refreshThumbText(remainingValue: Double) {
        textValue = remainingValue
        thumbLabel.text = textProvider(textValue)
    }

    /// Stop value for an index, or nil outside range.
    func value(at index: Int) -> Double? {
        spec.values.indices.contains(index) ? spec.values[index] : nil
    }

    // MARK: - Layout / drawing

    override func layoutSubviews() {
        super.layoutSubviews()
        renderThumb()
        renderTicks()
    }

    /// Thumb center x for the selected stop: the 20 pt thumb rides flush
    /// inside the 4 pt capsule inset.
    private var thumbCenterX: CGFloat {
        let inset = Self.thumbRadius + 4
        let span = max(bounds.width - inset * 2, 0)
        let fraction = spec.values.count > 1
            ? CGFloat(selectedIndex) / CGFloat(spec.values.count - 1)
            : 0
        return inset + fraction * span
    }

    private func renderThumb() {
        let center = CGPoint(x: thumbCenterX, y: bounds.midY)
        thumbView.center = center
        thumbLabel.text = textProvider(textValue)
        accessibilityValue = textProvider(textValue)
    }

    private func renderTicks() {
        let centerY = bounds.midY
        for (index, dot) in tickLayers.enumerated() {
            guard spec.values.indices.contains(index) else { continue }
            let inset = Self.thumbRadius + 4
            let span = max(bounds.width - inset * 2, 0)
            let fraction = spec.values.count > 1
                ? CGFloat(index) / CGFloat(spec.values.count - 1)
                : 0
            let x = inset + fraction * span
            dot.path = UIBezierPath(
                ovalIn: CGRect(x: x - Self.tickRadius, y: centerY - Self.tickRadius,
                               width: Self.tickRadius * 2, height: Self.tickRadius * 2)
            ).cgPath
            switch spec.tickStyle {
            case .allWhite:
                dot.fillColor = UIColor.white.cgColor
            case .whiteUpToActive:
                dot.fillColor = index <= selectedIndex
                    ? UIColor.white.cgColor
                    : Theme.cardBackground.cgColor
            }
        }
    }

    // MARK: - Touch tracking (tap jumps to nearest stop; drag follows)

    private func applyTouch(x: CGFloat) {
        let inset = Self.thumbRadius + 4
        let span = max(bounds.width - inset * 2, 1)
        let fraction = min(max((x - inset) / span, 0), 1)
        let raw = Double(fraction) * Double(max(spec.values.count - 1, 0))
        let index = min(max(Int((raw).rounded()), 0), max(spec.values.count - 1, 0))
        if index != selectedIndex {
            selectedIndex = index
            textValue = spec.values[index]
            // Fire before rendering: the owner may push a corrected text
            // payload (the COUNTDOWN thumb shows remaining time, not the
            // stop value) via refreshThumbText.
            onValueChanged?(index, spec.values[index])
            sendActions(for: .valueChanged)
            renderThumb()
            renderTicks()
        }
    }

    override func beginTracking(_ touch: UITouch, with event: UIEvent?) -> Bool {
        applyTouch(x: touch.location(in: self).x)
        return true
    }

    override func continueTracking(_ touch: UITouch, with event: UIEvent?) -> Bool {
        applyTouch(x: touch.location(in: self).x)
        return true
    }

    // MARK: - Accessibility (adjustable, one stop per increment)

    override func accessibilityIncrement() {
        step(+1)
    }

    override func accessibilityDecrement() {
        step(-1)
    }

    private func step(_ delta: Int) {
        let target = selectedIndex + delta
        guard spec.values.indices.contains(target) else { return }
        selectedIndex = target
        textValue = spec.values[target]
        onValueChanged?(target, spec.values[target])
        sendActions(for: .valueChanged)
        renderThumb()
        renderTicks()
    }
}
