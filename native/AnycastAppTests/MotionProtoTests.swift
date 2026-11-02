import CoreGraphics
import Testing
@testable import Anycast

@MainActor
struct MotionBehaviorTests {

    @Test("Empty fetches show a skeleton; a loaded list refreshes quietly")
    func loadingChrome() {
        let empty = MotionLoading.chrome(isLoading: true, hasContent: false)
        #expect(empty.showSkeleton)
        #expect(!empty.showSubtleIndicator)

        let stale = MotionLoading.chrome(isLoading: true, hasContent: true)
        #expect(!stale.showSkeleton)
        #expect(stale.showSubtleIndicator)

        let done = MotionLoading.chrome(isLoading: false, hasContent: true)
        #expect(!done.showSkeleton)
        #expect(!done.showSubtleIndicator)
    }

    @Test("Mini-player drag opens on a long travel or an upward flick, and cancels when pulled back")
    func dragDecision() {
        let travel: CGFloat = 800
        #expect(PlayerDragDecision.shouldOpen(
            translationY: -400, velocityY: 0, travel: travel, cancelled: false
        ))
        #expect(!PlayerDragDecision.shouldOpen(
            translationY: -20, velocityY: 0, travel: travel, cancelled: false
        ))
        #expect(PlayerDragDecision.shouldOpen(
            translationY: -20, velocityY: -901, travel: travel, cancelled: false
        ))
        #expect(!PlayerDragDecision.shouldOpen(
            translationY: -20, velocityY: -900, travel: travel, cancelled: false
        ))
        // Still moving upward on paper, but the finger has come back down.
        #expect(!PlayerDragDecision.shouldOpen(
            translationY: -30, velocityY: 1200, travel: travel, cancelled: false
        ))
        #expect(!PlayerDragDecision.shouldOpen(
            translationY: -500, velocityY: -2000, travel: travel, cancelled: true
        ))
    }
}
