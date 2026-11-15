import Foundation

/// "Show after 300 ms if still loading": a loading affordance (skeleton rows)
/// must not flash for a fetch that finishes at once. Start it when loading
/// begins, cancel it when loading ends; `onDue` fires on the main actor only
/// if it was not cancelled first.
@MainActor
final class LoadingDelay {

    /// The one shared threshold.
    static let threshold: TimeInterval = 0.3

    private var task: Task<Void, Never>?
    private(set) var isDue = false

    var isRunning: Bool { task != nil }

    /// Starts the clock unless it already runs or already fired.
    func start(after delay: TimeInterval = LoadingDelay.threshold, onDue: @escaping @MainActor () -> Void) {
        guard task == nil, !isDue else { return }
        task = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled, let self else { return }
            self.isDue = true
            self.task = nil
            onDue()
        }
    }

    /// Loading ended: forget the clock and the fired state.
    func cancel() {
        task?.cancel()
        task = nil
        isDue = false
    }
}
