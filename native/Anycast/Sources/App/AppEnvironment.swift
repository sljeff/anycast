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

    /// Built once the playback stack exists — the one object screens
    /// receive. Held here so a late `onShellReady` observer (set after the
    /// DAG finished) still gets it exactly once.
    private(set) var uiContext: UIContext?

    /// The shell installs through this callback (SceneDelegate wires it to
    /// RootViewController.install). Called once, with the UIContext.
    var onShellReady: (@MainActor (UIContext) -> Void)? {
        didSet {
            if let uiContext, onShellReady != nil {
                onShellReady?(uiContext)
            }
        }
    }

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
                let stack = await PlaybackStack.build(
                    database: database,
                    settings: settings,
                    pointer: pointer,
                    paths: self.paths,
                    session: self.audioSession,
                    auth: self.auth,
                    sentry: self.sentry
                )
                self.playback = stack
                self.installUIContext(database: database, stack: stack)
            }
        }
    }

    /// The `UIContext` is constructed ONLY here, after the DAG restored
    /// local state and the playback stack exists (constructor injection
    /// from here down; screens never see a half-built context).
    private func installUIContext(database: AppDatabase, stack: PlaybackStack) {
        let context = UIContext(
            database: database,
            api: APIClient(client: HTTPClient(), tokenProvider: {
                try await AuthController.currentToken()
            }),
            paths: paths,
            playback: stack.playback,
            cacheStore: stack.cacheStore,
            sleepTimer: stack.sleepTimer,
            subtitles: stack.subtitles,
            translations: stack.translations,
            settingsBox: stack.settingsBox,
            auth: auth,
            purchases: purchases
        )
        context.loginPrompt.context = context
        ShareHandoffCoordinator.register(on: context)
        uiContext = context
        onShellReady?(context)
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
