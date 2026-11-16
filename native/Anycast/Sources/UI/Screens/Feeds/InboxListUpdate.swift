import UIKit

/// One model/snapshot transaction at a time. A render arriving while the
/// gate is closed is parked (newest wins), including its data commit. FLIP
/// travels after the gate reopens, so the next user action can use its filler.
@MainActor
final class UpdateGate {

    private(set) var isBusy = false
    private var pending: (() -> Void)?

    func begin() { isBusy = true }

    func end() {
        isBusy = false
        let work = pending
        pending = nil
        work?()
    }

    /// Runs `work` now, or parks it (replacing any parked work) until `end()`.
    func submitOrDefer(_ work: @escaping () -> Void) {
        if isBusy {
            pending = work
        } else {
            work()
        }
    }
}
