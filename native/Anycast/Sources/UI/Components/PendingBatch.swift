import UIKit

/// A batch of same-kind actions waiting out one shared Undo window. `add`
/// merges an action of the current kind into the batch and restarts the
/// window; an action of a different kind commits the previous batch right
/// away and starts a new one. The write (`commit`) runs when the window
/// ends, or earlier on backgrounding, termination, a kind switch, or an
/// explicit `commitNow`. `undo` cancels the whole batch without ever
/// running `commit` and hands the items back in REVERSE order of addition:
/// an item's stored index is only valid right before its own removal, so
/// restoring last-to-first rebuilds the original order exactly.
///
/// Pending state is cleared BEFORE the write starts, so every trigger is
/// idempotent and a commit can never run twice. Commits are chained: a later
/// commit starts only after the earlier one finished. The commit closure
/// must capture what it needs (a repository), not a screen, so it still
/// finishes after the screen is gone. A kill inside the window never runs
/// it: the stored rows stay.
@MainActor
final class PendingBatch<Kind: Hashable, Item> {

    /// The window's sleep; injectable so tests drive the clock.
    typealias Sleep = @MainActor (Duration) async throws -> Void

    private let window: Duration
    private let sleep: Sleep
    private(set) var kind: Kind?
    private(set) var items: [Item] = []
    private var commit: (@MainActor ([Item]) async -> Void)?
    private var timer: Task<Void, Never>?
    private var inFlight: Task<Void, Never>?
    /// Block-API observer tokens — touched only on the main thread;
    /// `nonisolated(unsafe)` because deinit is nonisolated.
    private nonisolated(unsafe) var observers: [NSObjectProtocol] = []
    private nonisolated let center: NotificationCenter

    /// Called synchronously each time a pending batch starts committing
    /// (not on undo), so the screen can drop its Undo affordance.
    var onCommit: (() -> Void)?

    init(
        window: Duration = .seconds(5),
        center: NotificationCenter = .default,
        sleep: @escaping Sleep = { try await Task.sleep(for: $0) }
    ) {
        self.window = window
        self.sleep = sleep
        self.center = center
        // A pending batch must not outlive the app being suspended.
        for name in [UIApplication.didEnterBackgroundNotification, UIApplication.willTerminateNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.flush() }
            })
        }
    }

    deinit {
        observers.forEach(center.removeObserver)
    }

    var count: Int { items.count }
    var isPending: Bool { kind != nil }

    /// Adds `item` to the batch of `kind` and restarts the window. A pending
    /// batch of another kind is committed first. `commit` receives every
    /// item of the batch and replaces the closure given by earlier adds.
    /// Returns the batch size after the add.
    @discardableResult
    func add(
        _ item: Item,
        kind: Kind,
        commit: @escaping @MainActor ([Item]) async -> Void
    ) -> Int {
        if let current = self.kind, current != kind { flush() }
        self.kind = kind
        items.append(item)
        self.commit = commit
        timer?.cancel()
        timer = Task { [weak self, window, sleep] in
            try? await sleep(window)
            guard !Task.isCancelled else { return }
            self?.flush()
        }
        return items.count
    }

    /// Cancels the pending batch and returns its kind and items, newest
    /// first (the order to restore them in); nil when nothing is pending
    /// (never begun, already committed, or already undone).
    func undo() -> (kind: Kind, items: [Item])? {
        guard let kind else { return nil }
        let undone = items.reversed() as [Item]
        reset()
        return (kind, undone)
    }

    /// Commits any pending batch and waits for every write to finish.
    func commitNow() async {
        flush()
        await inFlight?.value
    }

    private func reset() {
        kind = nil
        items = []
        commit = nil
        timer?.cancel()
        timer = nil
    }

    private func flush() {
        guard let commit else { return }
        let batch = items
        reset()
        onCommit?()
        let previous = inFlight
        inFlight = Task {
            await previous?.value
            await commit(batch)
        }
    }
}
