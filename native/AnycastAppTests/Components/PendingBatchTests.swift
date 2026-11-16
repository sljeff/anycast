import UIKit
import Testing
@testable import Anycast

/// The merged Undo window: same-kind actions share one window and one
/// commit; a different kind commits the previous batch first; Undo returns
/// the items newest first and never commits.
@MainActor
struct PendingBatchTests {

    private final class Clock {
        var elapsedMilliseconds = 0
        func advance(_ milliseconds: Int) async {
            // Let a window task that was just started read the current time.
            try? await Task.sleep(for: .milliseconds(30))
            elapsedMilliseconds += milliseconds
            // Let the window task observe the new time.
            try? await Task.sleep(for: .milliseconds(30))
        }
    }

    private final class Log {
        var commits: [[String]] = []
    }

    private enum Kind { case remove, add }

    private static func makeBatch(
        clock: Clock, center: NotificationCenter = NotificationCenter()
    ) -> PendingBatch<Kind, String> {
        PendingBatch<Kind, String>(window: .seconds(5), center: center) { [clock] duration in
            let target = clock.elapsedMilliseconds
                + Int(duration.components.seconds) * 1000
            while clock.elapsedMilliseconds < target {
                try await Task.sleep(for: .milliseconds(2))
            }
        }
    }

    private static func settle() async {
        try? await Task.sleep(for: .milliseconds(60))
    }

    @Test("add does not commit; the count and kind track the batch")
    func addDoesNotCommit() async {
        let log = Log()
        let batch = Self.makeBatch(clock: Clock())
        #expect(batch.add("a", kind: .remove) { log.commits.append($0) } == 1)
        #expect(batch.add("b", kind: .remove) { log.commits.append($0) } == 2)
        await Self.settle()
        #expect(log.commits.isEmpty)
        #expect(batch.count == 2 && batch.kind == .remove && batch.isPending)
    }

    @Test("each merge restarts the window; the whole batch commits once")
    func mergeRestartsWindow() async {
        let clock = Clock()
        let log = Log()
        let batch = Self.makeBatch(clock: clock)
        batch.add("a", kind: .remove) { log.commits.append($0) }
        await clock.advance(4_000)
        batch.add("b", kind: .remove) { log.commits.append($0) }
        await clock.advance(4_000)
        #expect(log.commits.isEmpty, "8 s since the first add, but only 4 s since the last")
        await clock.advance(1_100)
        await Self.settle()
        #expect(log.commits == [["a", "b"]], "the restarted window ended by itself")
        await clock.advance(10_000)
        #expect(log.commits.count == 1, "the old window never commits again")
    }

    @Test("a different kind commits the previous batch immediately, then starts its own")
    func kindSwitchCommitsPrevious() async {
        let log = Log()
        let batch = Self.makeBatch(clock: Clock())
        batch.add("a", kind: .add) { log.commits.append($0) }
        batch.add("b", kind: .add) { log.commits.append($0) }
        batch.add("c", kind: .remove) { log.commits.append($0.map { "r" + $0 }) }
        await Self.settle()
        #expect(log.commits == [["a", "b"]])
        #expect(batch.kind == .remove && batch.count == 1)
        await batch.commitNow()
        #expect(log.commits == [["a", "b"], ["rc"]])
    }

    @Test("chained commits finish in order even when the first is slow")
    func commitsAreOrdered() async {
        var order: [String] = []
        let batch = Self.makeBatch(clock: Clock())
        batch.add("a", kind: .add) { _ in
            try? await Task.sleep(for: .milliseconds(80))
            order.append("first")
        }
        batch.add("b", kind: .remove) { _ in order.append("second") }
        await batch.commitNow()
        #expect(order == ["first", "second"])
    }

    @Test("undo returns the whole batch newest first and never commits")
    func undoNeverCommits() async {
        let clock = Clock()
        let log = Log()
        let batch = Self.makeBatch(clock: clock)
        for item in ["a", "b", "c"] { batch.add(item, kind: .remove) { log.commits.append($0) } }
        let undone = batch.undo()
        #expect(undone?.items == ["c", "b", "a"])
        #expect(undone?.kind == .remove)
        #expect(!batch.isPending && batch.count == 0)
        await clock.advance(10_000)
        await batch.commitNow()
        #expect(log.commits.isEmpty)
        #expect(batch.undo() == nil)
    }

    @Test("undo restores items 2, 3, 5 and the head to the exact original order")
    func undoRestoresOriginalOrder() {
        struct Removed { let value: Int; let index: Int }
        let original = Array(0..<8)
        var list = original
        let batch = PendingBatch<Kind, Removed>(center: NotificationCenter())
        // Each index is valid only right before its own removal.
        for value in [2, 3, 5, 0] {
            let index = list.firstIndex(of: value)!
            batch.add(Removed(value: value, index: index), kind: .remove) { _ in }
            list.remove(at: index)
        }
        #expect(list == [1, 4, 6, 7])
        for removed in batch.undo()!.items {
            list.insert(removed.value, at: removed.index)
        }
        #expect(list == original)
    }

    @Test("commitNow commits once; later triggers and undo are no-ops")
    func commitIsIdempotent() async {
        let log = Log()
        let batch = Self.makeBatch(clock: Clock())
        batch.add("a", kind: .remove) { log.commits.append($0) }
        await batch.commitNow()
        await batch.commitNow()
        #expect(log.commits == [["a"]])
        #expect(batch.undo() == nil)
    }

    @Test("entering the background commits the whole batch")
    func backgroundCommits() async {
        let center = NotificationCenter()
        let log = Log()
        let batch = Self.makeBatch(clock: Clock(), center: center)
        batch.add("a", kind: .remove) { log.commits.append($0) }
        batch.add("b", kind: .remove) { log.commits.append($0) }
        center.post(name: UIApplication.didEnterBackgroundNotification, object: nil)
        await Self.settle()
        #expect(log.commits == [["a", "b"]])
        #expect(batch.undo() == nil)
    }

    @Test("terminating commits")
    func terminateCommits() async {
        let center = NotificationCenter()
        let log = Log()
        let batch = Self.makeBatch(clock: Clock(), center: center)
        batch.add("a", kind: .remove) { log.commits.append($0) }
        center.post(name: UIApplication.willTerminateNotification, object: nil)
        await Self.settle()
        #expect(log.commits == [["a"]])
    }

    @Test("onCommit fires when a commit starts (window, kind switch), not on undo")
    func onCommitFires() async {
        var fired = 0
        let batch = Self.makeBatch(clock: Clock())
        batch.onCommit = { fired += 1 }
        batch.add("a", kind: .remove) { _ in }
        _ = batch.undo()
        #expect(fired == 0)
        batch.add("b", kind: .remove) { _ in }
        batch.add("c", kind: .add) { _ in }
        #expect(fired == 1)
        await batch.commitNow()
        #expect(fired == 2)
    }
}
