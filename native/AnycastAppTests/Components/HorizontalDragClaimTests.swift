import UIKit
import Testing
@testable import Anycast

/// The player's drag-to-seek/stop sliders live inside a UIPageViewController
/// whose internal scroll view claims horizontal pans and cancels UIControl
/// touch tracking mid-drag (drag did nothing; the page swiped instead — the
/// 2026-09-29 QA round). HorizontalDragClaim is the wiring that wins those
/// drags back; Flutter's PageView already resolves the arena in the slider's
/// favor, so winning is parity.
@MainActor
struct HorizontalDragClaimTests {

    @Test("claim decision: horizontal-dominant movement only")
    func claimDecision() {
        #expect(HorizontalDragClaim.shouldClaim(velocityX: 300, velocityY: 10))
        #expect(HorizontalDragClaim.shouldClaim(velocityX: -300, velocityY: 10))
        #expect(!HorizontalDragClaim.shouldClaim(velocityX: 10, velocityY: 300))
        #expect(!HorizontalDragClaim.shouldClaim(velocityX: 0, velocityY: 0))
        // Ties go to the scroller (vertical scrolling through the slider
        // must keep working).
        #expect(!HorizontalDragClaim.shouldClaim(velocityX: 300, velocityY: 300))
    }

    @Test("claim pan attaches non-cancelling to the owner")
    func panAttachment() {
        let owner = UIControl(frame: CGRect(x: 0, y: 0, width: 100, height: 48))
        let claim = HorizontalDragClaim(owner: owner)

        let attached = owner.gestureRecognizers ?? []
        #expect(attached.contains { $0 === claim.pan })
        // The control keeps tracking the touches itself; a cancelling
        // recognizer would defeat the whole point.
        #expect(claim.pan.cancelsTouchesInView == false)
    }

    @Test("ancestor walk finds every enclosing scroll view's pan, innermost first")
    func ancestorWalk() {
        let owner = UIControl(frame: .zero)
        let verticalScroll = UIScrollView()
        let pagerScroll = UIScrollView()
        verticalScroll.addSubview(owner)
        pagerScroll.addSubview(verticalScroll)

        let pans = HorizontalDragClaim.enclosingScrollPans(above: owner)
        #expect(pans.count == 2)
        #expect(pans[0] === verticalScroll.panGestureRecognizer)
        #expect(pans[1] === pagerScroll.panGestureRecognizer)
        // No ancestors → no pans; must not trap or return the owner itself.
        #expect(HorizontalDragClaim.enclosingScrollPans(above: UIControl(frame: .zero)).isEmpty)
    }
}
