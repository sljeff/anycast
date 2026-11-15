import UIKit
import Testing
@testable import Anycast

/// The Undo window controller: commit runs once, only after the window ends
/// or an earlier trigger; Undo never commits.
@MainActor
struct PendingRemovalTests {

    private final class Counter {
        var commits = 0
    }

    private static func sleep(_ ms: Int) async {
        try? await Task.sleep(for: .milliseconds(ms))
    }

    @Test("begin does not commit")
    func beginDoesNotCommit() async {
        let counter = Counter()
        let removal = PendingRemoval(window: .seconds(60), center: NotificationCenter())
        removal.begin("a") { counter.commits += 1 }
        await Self.sleep(50)
        #expect(counter.commits == 0)
        #expect(removal.isPending("a"))
    }

    @Test("undo never commits, even after the window")
    func undoNeverCommits() async {
        let counter = Counter()
        let removal = PendingRemoval(window: .milliseconds(80), center: NotificationCenter())
        removal.begin("a") { counter.commits += 1 }
        #expect(removal.undo())
        #expect(!removal.isPending("a"))
        await Self.sleep(250)
        await removal.commitNow()
        #expect(counter.commits == 0)
    }

    @Test("the window ending commits exactly once")
    func timerCommitsOnce() async {
        let counter = Counter()
        let removal = PendingRemoval(window: .milliseconds(60), center: NotificationCenter())
        removal.begin("a") { counter.commits += 1 }
        await Self.sleep(300)
        #expect(counter.commits == 1)
        await removal.commitNow()
        #expect(counter.commits == 1)
    }

    @Test("commitNow then the timer commits once")
    func commitNowThenTimer() async {
        let counter = Counter()
        let removal = PendingRemoval(window: .milliseconds(100), center: NotificationCenter())
        removal.begin("a") { counter.commits += 1 }
        await removal.commitNow()
        #expect(counter.commits == 1)
        await Self.sleep(300)
        #expect(counter.commits == 1)
    }

    @Test("a second begin commits the first right away")
    func secondBeginCommitsFirst() async {
        var committed: [String] = []
        let removal = PendingRemoval(window: .seconds(60), center: NotificationCenter())
        removal.begin("a") { committed.append("a") }
        removal.begin("b") { committed.append("b") }
        await Self.sleep(50)
        #expect(committed == ["a"])
        #expect(removal.isPending("b"))
        await removal.commitNow()
        #expect(committed == ["a", "b"])
    }

    @Test("entering the background commits")
    func backgroundCommits() async {
        let center = NotificationCenter()
        let counter = Counter()
        let removal = PendingRemoval(window: .seconds(60), center: center)
        removal.begin("a") { counter.commits += 1 }
        center.post(name: UIApplication.didEnterBackgroundNotification, object: nil)
        await Self.sleep(50)
        #expect(counter.commits == 1)
        #expect(!removal.undo())
    }

    @Test("terminating commits")
    func terminateCommits() async {
        let center = NotificationCenter()
        let counter = Counter()
        let removal = PendingRemoval(window: .seconds(60), center: center)
        removal.begin("a") { counter.commits += 1 }
        center.post(name: UIApplication.willTerminateNotification, object: nil)
        await Self.sleep(50)
        #expect(counter.commits == 1)
    }

    @Test("undo after commit is a no-op that returns false")
    func undoAfterCommit() async {
        let counter = Counter()
        let removal = PendingRemoval(window: .seconds(60), center: NotificationCenter())
        removal.begin("a") { counter.commits += 1 }
        await removal.commitNow()
        #expect(!removal.undo())
        #expect(counter.commits == 1)
    }

    @Test("onCommit fires when a commit starts, not on undo")
    func onCommitFires() async {
        var fired = 0
        let removal = PendingRemoval(window: .seconds(60), center: NotificationCenter())
        removal.onCommit = { fired += 1 }
        removal.begin("a") {}
        _ = removal.undo()
        #expect(fired == 0)
        removal.begin("b") {}
        await removal.commitNow()
        #expect(fired == 1)
    }
}
