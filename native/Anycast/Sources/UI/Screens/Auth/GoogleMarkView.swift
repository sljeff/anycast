import UIKit

/// Code-drawn Google "G" brand mark — `Ri.google_fill` in the Dart baseline
/// has no SF Symbol, and the asset catalog (Resources/) is outside this
/// task's file set. Four annulus sectors + the horizontal bar approximate
/// the official mark; T11 should replace this with a bundled template image.
final class GoogleMarkView: UIView {

    override init(frame: CGRect) {
        super.init(frame: frame)
        isOpaque = false
        backgroundColor = .clear
        contentMode = .redraw
        isAccessibilityElement = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func draw(_ rect: CGRect) {
        // Angles in y-down radians: 0 = 3 o'clock, π/2 = 6 o'clock. The G
        // opening faces the upper right (gap between 1:30 and 3 o'clock).
        let wedgeAngles: [(start: CGFloat, end: CGFloat, color: UIColor)] = [
            (radians(225), radians(315), GoogleMarkView.blue),   // top: 10:30 → 1:30
            (radians(0), radians(75), GoogleMarkView.red),       // lower right: 3:00 → ~5:15
            (radians(75), radians(150), GoogleMarkView.green),   // bottom: ~5:15 → 7:30
            (radians(150), radians(225), GoogleMarkView.yellow), // left: 7:30 → 10:30
        ]

        let inset = rect.insetBy(dx: 1.5, dy: 1.5)
        let center = CGPoint(x: inset.midX, y: inset.midY)
        let outer = min(inset.width, inset.height) / 2
        let inner = outer * 0.66
        let thickness = outer - inner

        for wedge in wedgeAngles {
            wedge.color.setFill()
            let path = UIBezierPath()
            path.addArc(
                withCenter: center, radius: outer,
                startAngle: wedge.start, endAngle: wedge.end, clockwise: true
            )
            path.addArc(
                withCenter: center, radius: inner,
                startAngle: wedge.end, endAngle: wedge.start, clockwise: false
            )
            path.close()
            path.fill()
        }

        // Horizontal blue bar from the center to the right edge at mid height.
        let bar = UIBezierPath(
            rect: CGRect(
                x: center.x, y: center.y - thickness / 2,
                width: outer, height: thickness
            )
        )
        GoogleMarkView.blue.setFill()
        bar.fill()
    }

    private func radians(_ degrees: CGFloat) -> CGFloat { degrees * .pi / 180 }

    private static let blue = UIColor(red: 0.259, green: 0.522, blue: 0.957, alpha: 1)  // #4285F4
    private static let red = UIColor(red: 0.918, green: 0.263, blue: 0.208, alpha: 1)   // #EA4335
    private static let yellow = UIColor(red: 0.984, green: 0.737, blue: 0.020, alpha: 1) // #FBBC05
    private static let green = UIColor(red: 0.220, green: 0.659, blue: 0.329, alpha: 1) // #38A852
}
