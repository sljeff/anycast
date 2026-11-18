import UIKit

/// Owners retain their controller and use this subclass for presentation-aware
/// hit routing. No delegate proxy is installed, so existing scrolling survives.
@MainActor
final class ListActionCollectionView: UICollectionView {
    weak var actionController: ListActionController?

    /// Fires after every offset change (drag, deceleration, programmatic).
    /// A hook instead of a delegate: no delegate proxy is installed here, so
    /// the owner can watch the scroll without taking the delegate slot.
    var onContentOffsetChange: (() -> Void)?

    override var contentOffset: CGPoint {
        didSet {
            if contentOffset != oldValue { onContentOffsetChange?() }
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        actionController?.collectionViewDidLayout()
    }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard isUserInteractionEnabled, !isHidden, alpha > 0.01,
              self.point(inside: point, with: event) else { return nil }
        if let routed = actionController?.hitTest(point, with: event) { return routed }
        return super.hitTest(point, with: event)
    }
}

/// A control consumes travelling-card touches without involving the card's
/// cover/body recognizers or collection selection. Only explicit routing can
/// hit it; it must not intercept ordinary scrolling or settled card taps.
@MainActor
final class ListActionTouchSink: UIControl {
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? { nil }
}
