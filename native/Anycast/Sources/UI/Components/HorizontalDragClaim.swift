import UIKit

/// Lets a UIControl that tracks its own touches (PlayerValueSlider,
/// PlayerProgressBarView) win horizontal drags against enclosing scroll
/// views. The player pages live inside a UIPageViewController whose
/// internal scroll view claims horizontal pans and cancels the control's
/// touch tracking mid-gesture — the drag did nothing while the page swiped.
/// Flutter's PageView resolves the arena in the slider's favor, so winning
/// is the parity behavior.
///
/// Mechanism: a non-cancelling pan recognizer that only *begins* for
/// horizontal-dominant movement inside the control, plus
/// `panGestureRecognizer.require(toFail:)` wired from every enclosing scroll
/// view once the control enters a window. When the claim begins, the scroll
/// pans fail and touch tracking continues undisturbed; vertical drags and
/// gestures starting outside the control are untouched.
@MainActor
final class HorizontalDragClaim: NSObject, UIGestureRecognizerDelegate {

    /// Pure decision, unit-tested: claim horizontal-dominant movement only,
    /// so vertical scrolling through an ancestor scroll view is unaffected.
    static func shouldClaim(velocityX: CGFloat, velocityY: CGFloat) -> Bool {
        abs(velocityX) > abs(velocityY)
    }

    /// Every scroll-view pan above `view` in the hierarchy (the settings
    /// page's vertical scroller and the pager's internal one). Exposed for
    /// the wiring test.
    static func enclosingScrollPans(above view: UIView?) -> [UIGestureRecognizer] {
        var result: [UIGestureRecognizer] = []
        var current = view?.superview
        while let ancestor = current {
            if let scroll = ancestor as? UIScrollView {
                result.append(scroll.panGestureRecognizer)
            }
            current = ancestor.superview
        }
        return result
    }

    private let claimPan: UIPanGestureRecognizer
    private weak var installedWindow: UIWindow?

    /// The recognizer doing the claiming (attached to the owner).
    var pan: UIPanGestureRecognizer { claimPan }

    init(owner: UIControl) {
        claimPan = UIPanGestureRecognizer(target: nil, action: nil)
        super.init()
        claimPan.delegate = self
        // The claim only needs to *begin*; the control keeps tracking the
        // touches itself, so the recognizer must never cancel them.
        claimPan.cancelsTouchesInView = false
        owner.addGestureRecognizer(claimPan)
    }

    /// Call from the owner's `didMoveToWindow`; idempotent per window so
    /// reparenting the control re-wires the new ancestor chain.
    func installWhenInWindow() {
        guard let ownerView = claimPan.view,
              let window = ownerView.window,
              installedWindow !== window else { return }
        installedWindow = window
        for pan in Self.enclosingScrollPans(above: ownerView) {
            pan.require(toFail: claimPan)
        }
    }

    // MARK: - UIGestureRecognizerDelegate

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard gestureRecognizer === claimPan, let view = claimPan.view else { return false }
        let velocity = claimPan.velocity(in: view)
        return Self.shouldClaim(velocityX: velocity.x, velocityY: velocity.y)
    }
}
