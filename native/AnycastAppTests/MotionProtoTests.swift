import CoreGraphics
import Testing
@testable import Anycast

@MainActor
struct MotionProtoTests {

    @Test("Flags default off and the master switch enables every item")
    func masterSwitch() {
        let off: [String] = []
        for item in [
            MotionProto.Item.skeleton, .silent, .drag, .cover, .transitions, .reduceMotion,
        ] {
            #expect(MotionProto.isEnabled(item, arguments: off) == false)
        }
        let on = ["-motionProto", "1"]
        #expect(MotionProto.isEnabled(.cover, arguments: on))
        #expect(MotionProto.isEnabled(.drag, arguments: on))
        #expect(!MotionProto.isEnabled(.cover, arguments: ["-motionProto", "0"]))
    }

    @Test("A per-item flag overrides the master switch")
    func perItemOverride() {
        #expect(MotionProto.isEnabled(.cover, arguments: ["-motionProto.cover", "1"]))
        #expect(!MotionProto.isEnabled(.skeleton, arguments: ["-motionProto.cover", "1"]))
        #expect(!MotionProto.isEnabled(
            .cover,
            arguments: ["-motionProto", "1", "-motionProto.cover", "0"]
        ))
        #expect(MotionProto.isEnabled(
            .silent,
            arguments: ["-motionProto", "0", "-motionProto.silent", "yes"]
        ))
        // The later occurrence wins.
        #expect(MotionProto.isEnabled(
            .drag,
            arguments: ["-motionProto.drag", "0", "-motionProto.drag", "on"]
        ))
        #expect(!MotionProto.isEnabled(.drag, arguments: ["-motionProto"]))
    }

    @Test("Loading chrome: skeleton for an empty fetch, subtle indicator over rows")
    func loadingChrome() {
        let on = ["-motionProto", "1"]
        let empty = MotionLoading.chrome(isLoading: true, hasContent: false, arguments: on)
        #expect(empty.showSkeleton)
        #expect(!empty.showBlockingSpinner)
        #expect(!empty.showSubtleIndicator)

        let stale = MotionLoading.chrome(isLoading: true, hasContent: true, arguments: on)
        #expect(!stale.showSkeleton)
        #expect(!stale.showBlockingSpinner)
        #expect(stale.showSubtleIndicator)

        let legacy = MotionLoading.chrome(isLoading: true, hasContent: true, arguments: [])
        #expect(legacy.showBlockingSpinner)
        #expect(!legacy.showSkeleton)
        #expect(!legacy.showSubtleIndicator)

        let done = MotionLoading.chrome(isLoading: false, hasContent: true, arguments: on)
        #expect(!done.showSkeleton)
        #expect(!done.showBlockingSpinner)
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
