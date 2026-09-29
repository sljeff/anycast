import UIKit

/// The 42×6 rounded white sheet grabber (lib/widgets/handler.dart, 03 §1.3).
/// Purely visual — tap-to-close is wired by the owning sheet through a
/// gesture on its header area (A2 adaptation: the system grabber itself is
/// not tappable), never inside this view.
final class SheetGrabberView: UIView {

    init() {
        super.init(frame: CGRect(x: 0, y: 0, width: 42, height: 6))
        backgroundColor = UIColor.white.withAlphaComponent(0.8)
        layer.cornerRadius = 3
        layer.cornerCurve = .continuous
        isAccessibilityElement = true
        accessibilityTraits = [.button]
        accessibilityLabel = "Close"
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var intrinsicContentSize: CGSize { CGSize(width: 42, height: 6) }
}
