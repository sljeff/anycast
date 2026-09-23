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

    /// K18: the session category is set HERE, at process start — category
    /// only, never an activation (cold start must not interrupt another
    /// app's audio; the first PLAY is what activates).
    let audioSession: AudioSessionController

    /// Installed by the startup DAG once local state is restored; the M2
    /// audio stack and every timer live inside it.
    private(set) var playback: PlaybackStack?

    init(paths: ApplicationPaths,
         sentry: SentryService,
         auth: AuthController,
         purchases: RevenueCatController) {
        self.paths = paths
        self.sentry = sentry
        self.auth = auth
        self.purchases = purchases

        let session = AudioSessionController()
        session.configureAtStartup()
        self.audioSession = session

        self.startup = StartupSequence(sentry: sentry, auth: auth, purchases: purchases, paths: paths)
        startup.onReady = { [weak self] database, settings, pointer in
            guard let self else { return }
            Task {
                self.playback = await PlaybackStack.build(
                    database: database,
                    settings: settings,
                    pointer: pointer,
                    paths: self.paths,
                    session: self.audioSession,
                    auth: self.auth,
                    sentry: self.sentry
                )
                #if DEBUG
                self.playback?.runSmokeTestIfRequested(arguments: ProcessInfo.processInfo.arguments)
                #endif
            }
        }
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
