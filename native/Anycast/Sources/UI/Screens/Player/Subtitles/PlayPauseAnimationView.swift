import UIKit

/// Center-screen play/pause morph, the port of the Dart CustomPaint
/// (lib/widgets/animation.dart:90-175): 80×80, `white70` fill, a 200 ms
/// easeInOut progress from 0 to 1 that grows the target glyph. Shown when
/// a lyric line is tapped; the presenter removes the view 500 ms after it
/// appears (player.dart:1006-1015).
final class PlayPauseAnimationView: UIView {

    static let sideLength: CGFloat = 80
    static let animationDuration: TimeInterval = 0.2
    static let dismissalDelay: TimeInterval = 0.5

    private let isPlaying: Bool
    private var progress: CGFloat = 0
    private var startTimestamp: CFTimeInterval = 0
    private var displayLink: CADisplayLink?

    /// Dart `PlayPauseAnimation(isPlaying: !controller.isPlaying.value)` —
    /// the value AFTER the toggle: playing → pause glyph, paused → play
    /// glyph.
    init(isPlaying: Bool) {
        self.isPlaying = isPlaying
        super.init(frame: CGRect(x: 0, y: 0, width: Self.sideLength, height: Self.sideLength))
        backgroundColor = .clear
        isUserInteractionEnabled = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func startAnimation() {
        let link = CADisplayLink(target: self, selector: #selector(tick))
        link.add(to: .main, forMode: .common)
        displayLink = link
        startTimestamp = link.timestamp
    }

    @objc private func tick() {
        guard let displayLink else { return }
        let elapsed = displayLink.timestamp - startTimestamp
        progress = min(CGFloat(elapsed / Self.animationDuration), 1)
        setNeedsDisplay()
        if progress >= 1 {
            displayLink.invalidate()
            self.displayLink = nil
        }
    }

    /// Dart Curves.easeInOut evaluated directly: cubic Bezier through
    /// (0,0) (0.42,0) (0.58,1) (1,1). Solve x(t)=progress for t
    /// (Newton-Raphson), then evaluate y(t).
    private func easeInOut(_ x: CGFloat) -> CGFloat {
        let x1: CGFloat = 0.42, y1: CGFloat = 0, x2: CGFloat = 0.58, y2: CGFloat = 1

        func bezier(_ a: CGFloat, _ b: CGFloat, _ c: CGFloat, _ t: CGFloat) -> CGFloat {
            let inverse = 1 - t
            return 3 * inverse * inverse * t * a
                + 3 * inverse * t * t * b
                + t * t * t * c
        }

        var t = x
        for _ in 0..<8 {
            let xError = bezier(x1, x2, 1, t) - x
            if abs(xError) < 1e-6 { break }
            let derivative = 3 * (1 - t) * (1 - t) * x1
                + 6 * (1 - t) * t * (x2 - x1)
                + 3 * t * t * (1 - x2)
            if abs(derivative) < 1e-6 { break }
            t -= xError / derivative
        }
        t = min(max(t, 0), 1)
        return bezier(y1, y2, 1, t)
    }

    override func draw(_ rect: CGRect) {
        guard progress > 0,
              let context = UIGraphicsGetCurrentContext()
        else { return }

        // PlayPausePainter.paint — Colors.white70.
        context.setFillColor(UIColor.white.withAlphaComponent(0.7).cgColor)
        let width = bounds.width
        let height = bounds.height

        if isPlaying {
            // Pause: two 0.1w-wide bars sliding outward from the thirds.
            let left = width * (0.3 + 0.1 * progress)
            let right = width * (0.7 - 0.1 * progress)
            context.fill(CGRect(x: left, y: height * 0.2, width: width * 0.1, height: height * 0.6))
            context.fill(CGRect(x: right, y: height * 0.2, width: width * 0.1, height: height * 0.6))
        } else {
            // Play: triangle whose tip grows from the left edge to 0.8w.
            let path = CGMutablePath()
            path.move(to: CGPoint(x: width * 0.3, y: height * 0.2))
            path.addLine(to: CGPoint(x: width * (0.3 + 0.5 * progress), y: height * 0.5))
            path.addLine(to: CGPoint(x: width * 0.3, y: height * 0.8))
            path.closeSubpath()
            context.addPath(path)
            context.fillPath()
        }
    }

    deinit {
        MainActor.assumeIsolated {
            displayLink?.invalidate()
        }
    }

    // MARK: - Overlay presentation (player.dart:1006-1015)

    /// Adds the morph centered over `host` (in practice the window — the
    /// Dart OverlayEntry sat at the root overlay) and removes it 500 ms
    /// later. No interaction: the view ignores touches.
    static func presentOver(_ host: UIView, isPlaying: Bool) {
        let morph = PlayPauseAnimationView(isPlaying: isPlaying)
        morph.translatesAutoresizingMaskIntoConstraints = false
        host.addSubview(morph)
        NSLayoutConstraint.activate([
            morph.centerXAnchor.constraint(equalTo: host.centerXAnchor),
            morph.centerYAnchor.constraint(equalTo: host.centerYAnchor),
            morph.widthAnchor.constraint(equalToConstant: sideLength),
            morph.heightAnchor.constraint(equalToConstant: sideLength),
        ])
        morph.startAnimation()
        DispatchQueue.main.asyncAfter(deadline: .now() + dismissalDelay) {
            morph.removeFromSuperview()
        }
    }
}
