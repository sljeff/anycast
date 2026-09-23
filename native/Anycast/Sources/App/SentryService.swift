import Foundation
import Sentry

/// sentry-cocoa bootstrap, config transplanted 1:1 from the Flutter line
/// (lib/main.dart:54-66: full traces + profiles sampling, no manual captures
/// anywhere in the app code).
@MainActor
final class SentryService {

    private var started = false

    func start() {
        guard !started else { return }
        started = true
        SentrySDK.start { options in
            options.dsn = AppConfiguration.sentryDSN
            options.tracesSampleRate = NSNumber(value: AppConfiguration.sentryTracesSampleRate)
            options.profilesSampleRate = NSNumber(value: AppConfiguration.sentryProfilesSampleRate)
        }
    }

    /// K25 quarantine reporting and any other non-fatal startup failure land
    /// here. The old app had zero manual captures; the migration only adds
    /// what its own decisions require (K25 兜底上报, migration counters).
    func capture(_ error: Error, context: String) {
        SentrySDK.capture(error: error) { scope in
            scope.setTag(value: context, key: "migration.context")
        }
    }

    func captureMessage(_ message: String, context: String) {
        SentrySDK.capture(message: message) { scope in
            scope.setTag(value: context, key: "migration.context")
        }
    }
}
