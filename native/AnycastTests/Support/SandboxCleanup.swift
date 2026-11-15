import Foundation
import GRDB

/// Test-sandbox teardown: every sqlite queue must be closed BEFORE its
/// files are unlinked. Deleting a directory whose database is still open
/// trips sqlite's "vnode unlinked while in use" API-violation check —
/// exactly the integrity-signal noise the crash/corrupt suites listen for.
enum SandboxCleanup {

    static func remove(_ url: URL, closing queues: [DatabaseQueue?] = []) {
        for queue in queues {
            try? queue?.close()
        }
        try? FileManager.default.removeItem(at: url)
    }
}
