import Foundation
import Observation

/// Re-registering Observation tracker for UIKit hosts (shells own no
/// SwiftUI): each `track` call reads the observable state once, is told on
/// mutation, re-reads, and fires the caller's change handler. One loop per
/// concern; `deinit` stops re-registration.
@MainActor
final class ObservationLoop {

    private var stopped = false

    func track(
        read: @escaping @MainActor () -> Void,
        onChange: @escaping @MainActor () -> Void
    ) {
        guard !stopped else { return }
        withObservationTracking {
            read()
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, !self.stopped else { return }
                self.track(read: read, onChange: onChange)
                onChange()
            }
        }
    }

    deinit {
        stopped = true
    }
}
