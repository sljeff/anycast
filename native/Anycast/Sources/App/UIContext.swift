import UIKit
import AnycastKit

/// The share-handoff entry point (docs/migration/08 §12.2): URLs arriving
/// on the `ShareMedia-<bundleid>` scheme carry media shared from the
/// extension. T9 registers its implementation on `UIContext.shareHandoffPresenter`;
/// until then the router queues the URL and logs.
@MainActor
protocol ShareHandoffPresenting: AnyObject {
    func presentShareHandoff(for url: URL)
}

/// Programmatic tab navigation for screens (the Explore buttons jump to the
/// Discover tab, 03 §2.3/§2.5) plus the tab-0 re-tap registration point.
/// Constructed in the composition root together with `UIContext`; the shell
/// attaches the tab bar controller once installed (weak — UI objects die
/// with the scene, the context does not own them).
@MainActor
final class TabNavigation {

    weak var tabBarController: UITabBarController?

    /// The Feeds screen registers itself so the tab-0 re-tap rule
    /// (03 §1.1) can reach the Inbox list; nil until that task lands.
    weak var tabZeroTopRefresh: TabZeroTopRefresh?

    var selectedIndex: Int { tabBarController?.selectedIndex ?? 0 }

    func select(_ index: Int) {
        guard let tabs = tabBarController as? MainTabBarController else { return }
        tabs.selectTab(index)
    }

    /// Fires the re-tap behavior (MainTabBarController calls this on an
    /// already-selected tab-0 tap). Extracted so the quirk stays testable:
    /// the target is the Inbox list even when the Subscriptions inner tab
    /// is visible — no inner-tab condition (03 §1.1).
    func handleTabZeroReTap() {
        tabZeroTopRefresh?.tabZeroReTapped()
    }
}

/// Everything a screen needs, constructed ONCE in the composition root
/// (AppEnvironment) when the startup DAG is ready, then constructor-injected
/// into every view controller (docs/migration/08 §2.2). No service locator:
/// the only late-bound fields are the explicitly documented weak
/// registration points (`tabs`, `shareHandoffPresenter`, `loginPrompt`).
@MainActor
final class UIContext {

    // Repositories — async; screens never touch SQLite on the main actor.
    let database: AppDatabase

    /// The anycast.website API client with the auth token provider wired.
    let api: APIClient

    let paths: ApplicationPaths

    // The M2 audio stack (PlaybackStack members, flattened for screens).
    let playback: PlaybackService
    let cacheStore: EpisodeCacheStore
    let sleepTimer: SleepTimerController
    let subtitles: SubtitlePollController
    let translations: TranslationPollController
    let settingsBox: SettingsBox

    /// Settings writes: repository + settingsBox + change notifications.
    let settingsCoordinator: SettingsCoordinator

    let auth: AuthController
    let purchases: RevenueCatController
    let palette: PaletteService

    // Navigation.
    let tabs: TabNavigation
    let loginPrompt: LoginPromptCoordinator
    let flyInAnimator: PlaylistFlyInAnimator
    /// Endpoint provider the animator reads; the shell attaches itself.
    let flyInEndpointProvider: TabBarFlyInEndpointProvider

    /// T9 registration point for `ShareMedia-<bundleid>` URLs.
    weak var shareHandoffPresenter: ShareHandoffPresenting?

    init(
        database: AppDatabase,
        api: APIClient,
        paths: ApplicationPaths,
        playback: PlaybackService,
        cacheStore: EpisodeCacheStore,
        sleepTimer: SleepTimerController,
        subtitles: SubtitlePollController,
        translations: TranslationPollController,
        settingsBox: SettingsBox,
        auth: AuthController,
        purchases: RevenueCatController
    ) {
        self.database = database
        self.api = api
        self.paths = paths
        self.playback = playback
        self.cacheStore = cacheStore
        self.sleepTimer = sleepTimer
        self.subtitles = subtitles
        self.translations = translations
        self.settingsBox = settingsBox
        self.settingsCoordinator = SettingsCoordinator(
            repository: database.settingsRepository(),
            settingsBox: settingsBox
        )
        self.auth = auth
        self.purchases = purchases
        self.palette = PaletteService.shared
        self.tabs = TabNavigation()
        self.loginPrompt = LoginPromptCoordinator()
        self.flyInEndpointProvider = TabBarFlyInEndpointProvider()
        self.flyInAnimator = PlaylistFlyInAnimator(endpointProvider: flyInEndpointProvider)

        // The 401 signal chain (03 §10.1): any loginRequired error reaching
        // AuthController pops the login sheet through the coordinator.
        auth.onAuthRequired = { [weak loginPrompt = self.loginPrompt] in
            loginPrompt?.presentLogin()
        }
    }

    // MARK: - Presentation entry points (screens call these; no hand-rolled
    // sheet plumbing in screen tasks)

    /// The global 401/403-code=2 path (03 §10.1): presents the login sheet
    /// from the top-most view controller.
    func presentLogin() {
        loginPrompt.presentLogin()
    }

    /// Presents the full-screen player sheet (mini player tap, 03 §1.3 #1).
    func openPlayerPage(from presenter: UIViewController) {
        PlayerPageContainer.present(from: presenter, context: self)
    }

    /// Builds a mini player bar bound to the playback service; opening the
    /// full-screen player is pre-wired through the responder chain, so
    /// hosts only position the bar (tab accessory, or floating above a
    /// screen's bottom content). Sheet bottom bars use the default
    /// `.standalone` style; the shell's iOS 26+ tab accessory passes
    /// `.systemAccessory` so the system glass capsule is the only chrome.
    func makePlayerBar(style: PlayerBarView.HostingStyle = .standalone) -> PlayerBarView {
        let bar = PlayerBarView(playback: playback, style: style)
        bar.onOpenPlayer = { [weak bar, weak self] in
            guard let bar, let self else { return }
            // Present from whatever screen currently hosts the bar
            // (Channel/SearchPage bottom bars, 03 §2.7).
            let presenter = bar.containingViewController ?? self.topPresenter()
            guard let presenter else { return }
            self.openPlayerPage(from: presenter)
        }
        return bar
    }

    /// The current top-most view controller over the shell's root — the
    /// anchor for globally triggered sheets (login on 401).
    func topPresenter() -> UIViewController? {
        loginPrompt.presentingAnchor?.topMostPresented()
    }
}
