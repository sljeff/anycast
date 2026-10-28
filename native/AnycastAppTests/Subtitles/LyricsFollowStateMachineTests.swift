import Foundation
import Testing
@testable import Anycast

/// LyricsFollowStateMachine: following stops on a user drag and stays
/// stopped until the user taps "Back to now" (no timed auto-resume).
struct LyricsFollowStateMachineTests {

    @Test("Initial mode follows the active line")
    func initialMode() {
        #expect(LyricsFollowStateMachine().mode == .following)
    }

    @Test("A drag stops following")
    func dragDetaches() {
        var machine = LyricsFollowStateMachine()
        machine.handle(.dragBegan)
        #expect(machine.mode == .detached)
    }

    @Test("Stays detached across further drags")
    func staysDetached() {
        var machine = LyricsFollowStateMachine()
        machine.handle(.dragBegan)
        machine.handle(.dragBegan)
        #expect(machine.mode == .detached)
    }

    @Test("Back to now resumes following")
    func backToNowResumes() {
        var machine = LyricsFollowStateMachine()
        machine.handle(.dragBegan)
        machine.handle(.backToNowRequested)
        #expect(machine.mode == .following)
    }

    @Test("Back to now while following is a no-op")
    func backToNowWhileFollowing() {
        var machine = LyricsFollowStateMachine()
        machine.handle(.backToNowRequested)
        #expect(machine.mode == .following)
    }

    @Test("A new drag after returning detaches again")
    func redrag() {
        var machine = LyricsFollowStateMachine()
        machine.handle(.dragBegan)
        machine.handle(.backToNowRequested)
        machine.handle(.dragBegan)
        #expect(machine.mode == .detached)
    }
}
