import UIKit

/// Circular download/import progress ring (self-drawn widget #8, 07 §3) —
/// a CAShapeLayer driven by `strokeEnd`. Matches the Dart
/// CircularPercentIndicator(radius 8, lineWidth 3) on cards and is reused by
/// the OPML import indicator (07 §2.7).
final class ProgressRingView: UIView {

    var tintColorOverride: UIColor? {
        didSet { ringLayer.strokeColor = (tintColorOverride ?? Theme.primary).cgColor }
    }

    private let ringLayer = CAShapeLayer()

    init(lineWidth: CGFloat = 3) {
        super.init(frame: .zero)
        isAccessibilityElement = true
        accessibilityTraits = [.updatesFrequently]

        ringLayer.fillColor = UIColor.clear.cgColor
        ringLayer.strokeColor = Theme.primary.cgColor
        ringLayer.lineWidth = lineWidth
        ringLayer.lineCap = .round
        ringLayer.strokeEnd = 0
        layer.addSublayer(ringLayer)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    /// Progress 0…1; clamped, and a non-finite value counts as 0 (min/max
    /// do not filter NaN). Drives strokeEnd — no animation (the Dart ring
    /// tracked download callbacks frame by frame), so the implicit layer
    /// action is disabled and every update lands immediately.
    func setProgress(_ progress: Double) {
        let clamped = min(max(progress.isFinite ? progress : 0, 0), 1)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        ringLayer.strokeEnd = CGFloat(clamped)
        CATransaction.commit()
        accessibilityValue = "\(Int(clamped * 100)) percent"
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        let radius = (min(bounds.width, bounds.height) - ringLayer.lineWidth) / 2
        let path = UIBezierPath(
            arcCenter: center,
            radius: max(radius, 0),
            startAngle: -.pi / 2,
            endAngle: .pi * 1.5,
            clockwise: true
        )
        ringLayer.frame = bounds
        ringLayer.path = path.cgPath
    }
}
