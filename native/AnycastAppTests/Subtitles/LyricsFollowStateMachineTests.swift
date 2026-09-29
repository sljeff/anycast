import Foundation
import Testing
@testable import Anycast

/// LyricsFollowStateMachine: the player's drag/neverResume configuration
/// (player.dart:988-990 — neverResume, 300 ms select, 3000 ms active).
struct LyricsFollowStateMachineTests {

    @Test("Initial mode follows the active line")
    func initialMode() {
        #expect(LyricsFollowStateMachine().mode == .following)
    }

    @Test("Drag suspends following and cancels any pending resume")
    func dragSuspends() {
        var machine = LyricsFollowStateMachine()
        #expect(machine.handle(.dragBegan) == .cancel)
        #expect(machine.mode == .selecting)
    }

    @Test("neverResume: after a drag only the 3 s active resume schedules")
    func dragEndSchedulesActiveResume() {
        var machine = LyricsFollowStateMachine()
        machine.handle(.dragBegan)
        #expect(machine.handle(.dragEnded) == .startActiveResume)
        // Still selecting while the timer runs.
        #expect(machine.mode == .selecting)
    }

    @Test("Timer fire after drag resumes following")
    func timerResumes() {
        var machine = LyricsFollowStateMachine()
        machine.handle(.dragBegan)
        machine.handle(.dragEnded)
        #expect(machine.handle(.activeResumeTimerFired) == .none)
        #expect(machine.mode == .following)
    }

    @Test("A new drag wins over a queued resume timer")
    func redragCancels() {
        var machine = LyricsFollowStateMachine()
        machine.handle(.dragBegan)
        machine.handle(.dragEnded)
        // The view cancels the timer on dragBegan; a late timer fire is a
        // no-op because the machine is selecting again.
        #expect(machine.handle(.dragBegan) == .cancel)
        #expect(machine.handle(.activeResumeTimerFired) == .none)
        #expect(machine.mode == .selecting)
    }

    @Test("stopSelection (time-bar play tap) returns to following at once")
    func stopSelection() {
        var machine = LyricsFollowStateMachine()
        machine.handle(.dragBegan)
        machine.handle(.dragEnded)
        #expect(machine.handle(.stopSelectionRequested) == .cancel)
        #expect(machine.mode == .following)
    }

    @Test("Resume constants mirror the Dart configuration")
    func constants() {
        #expect(LyricsFollowStateMachine.activeLineResumeMilliseconds == 3_000)
        #expect(LyricsFollowStateMachine.selectLineResumeMilliseconds == 300)
    }
}
