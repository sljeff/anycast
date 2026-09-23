import Foundation
import AnycastKit

/// Composition root (docs/migration/08 §2.2): every long-lived object is
/// constructed here, explicitly, with constructor injection. The GetX
/// lifecycle hacks (build-time `Get.put` storms, `lazyPut`, deferred
/// deletes) have no equivalent: page-scoped state will live and die with its
/// view controller (M3), and nothing registers itself from a `build()`.
@MainActor
final class AppEnvironment {

    let paths: ApplicationPaths
    let sentry: SentryService
    let auth: AuthController
    let purchases: RevenueCatController
    let startup: StartupSequence

    init(paths: ApplicationPaths,
         sentry: SentryService,
         auth: AuthController,
         purchases: RevenueCatController) {
        self.paths = paths
        self.sentry = sentry
        self.auth = auth
        self.purchases = purchases
        self.startup = StartupSequence(sentry: sentry, auth: auth, purchases: purchases, paths: paths)
    }

    /// The production graph. Tests (L0–L2) never go through here — they
    /// construct `AnycastKit` types directly against fixtures.
    static func live() -> AppEnvironment {
        AppEnvironment(
            paths: ApplicationPaths.standard(),
            sentry: SentryService(),
            auth: AuthController(),
            purchases: RevenueCatController()
        )
    }
}
