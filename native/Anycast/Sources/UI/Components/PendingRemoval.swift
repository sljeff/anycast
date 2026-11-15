import UIKit

/// One deferred removal waiting out an Undo window. `begin` starts the
/// window; the DB write (`commit`) runs when the window ends, or earlier on
/// backgrounding, termination, a second `begin`, or an explicit
/// `commitNow`. `undo` cancels without ever running `commit`.
///
/// Pending state is cleared BEFORE the write starts, so every trigger is
/// idempotent and a commit can never run twice. The commit closure must
/// capture what it needs (a repository), not a screen, so it still finishes
/// after the screen is gone. A kill inside the window never runs it: the
/// stored row stays.
@MainActor
final class PendingRemoval {

    private let window: Duration
    private var key: String?
    private var commit: (@MainActor () async -> Void)?
    private var timer: Task<Void, Never>?
    private var inFlight: Task<Void, Never>?
    /// Block-API observer tokens — touched only on the main thread;
    /// `nonisolated(unsafe)` because deinit is nonisolated.
    private nonisolated(unsafe) var observers: [NSObjectProtocol] = []
    private let center: NotificationCenter

    /// Called synchronously each time a pending removal starts committing
    /// (not on undo), so the screen can drop its Undo affordance.
    var onCommit: (() -> Void)?

    init(window: Duration = .seconds(5), center: NotificationCenter = .default) {
        self.window = window
        self.center = center
        // A pending removal must not outlive the app being suspended.
        for name in [UIApplication.didEnterBackgroundNotification, UIApplication.willTerminateNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.flush() }
            })
        }
    }

    deinit {
        observers.forEach(center.removeObserver)
    }

    func isPending(_ key: String) -> Bool { self.key == key }

    /// Starts the window for `key`. A removal already pending is committed
    /// right away.
    func begin(_ key: String, commit: @escaping @MainActor () async -> Void) {
        flush()
        self.key = key
        self.commit = commit
        timer = Task { [weak self, window] in
            try? await Task.sleep(for: window)
            guard !Task.isCancelled else { return }
            self?.flush()
        }
    }

    /// Cancels the pending removal; false when nothing is pending (never
    /// begun, already committed, or already undone).
    func undo() -> Bool {
        guard key != nil else { return false }
        key = nil
        commit = nil
        timer?.cancel()
        timer = nil
        return true
    }

    /// Commits any pending removal and waits for its write to finish.
    func commitNow() async {
        flush()
        await inFlight?.value
    }

    private func flush() {
        guard let commit else { return }
        key = nil
        self.commit = nil
        timer?.cancel()
        timer = nil
        onCommit?()
        inFlight = Task { await commit() }
    }
}
