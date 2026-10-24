import UIKit
import AnycastKit

/// The tab-0 re-tap decision, extracted pure (03 §1.1,
/// bottom_nav_bar.dart:262-276): with no scroll client or at the top →
/// force a refresh; otherwise animate scroll-to-top (300 ms easeInOut).
enum TabZeroRetap {

    enum Action: Equatable {
        case scrollToTop
        case refresh
    }

    static func action(hasClient: Bool, isAtTop: Bool) -> Action {
        if !hasClient || isAtTop {
            return .refresh
        }
        return .scrollToTop
    }
}

/// The Feeds screen implements this; the shell dispatches through
/// `UIContext.tabs`. NOTE the quirk: the target is the Inbox list
/// EVEN WHEN another tab is currently visible — the shipped code never
/// conditioned on the inner tab (03 §1.1, 2026-09-22 corrigendum).
@MainActor
protocol TabZeroTopRefresh: AnyObject {
    func tabZeroReTapped()
}

/// The mini player visibility rule (03 §2.9): with an empty queue the whole
/// bar collapses (`SizedBox.shrink` — bottom_nav_bar.dart:86-88).
enum MiniPlayerVisibility {
    static func isVisible(queueCount: Int) -> Bool {
        queueCount > 0
    }
}

/// Derives the fly-in animation endpoint from the LIVE tab bar (07 §3
/// widget #11): the center of the Playlist tab's button, as the tab reports
/// its frame — degrading to the bar's center when the tab has no frame, and
/// to the window bottom center when the bar is not on screen (A1-accepted
/// adaptation). The shell attaches itself through the providers at install
/// time.
@MainActor
final class TabBarFlyInEndpointProvider: PlaylistFlyInEndpointProvider {

    var tabBarProvider: (() -> UITabBar?)?
    var playlistTabProvider: (() -> UITab?)?

    private let fallback = WindowCenterBottomEndpointProvider()

    func playlistFlyInEndpoint(in window: UIWindow) -> CGPoint {
        guard let tabBar = tabBarProvider?(), tabBar.window != nil, !tabBar.isHidden else {
            return fallback.playlistFlyInEndpoint(in: window)
        }
        if let frame = playlistTabProvider?()?.frame(in: window), !frame.isEmpty {
            return CGPoint(x: frame.midX, y: frame.midY)
        }
        return window.convert(CGPoint(x: tabBar.bounds.midX, y: tabBar.bounds.midY), from: tabBar)
    }
}

/// The Flutter destination shell — Podcast / Playlist / Discover — plus the
/// Search tab at the trailing end (search role, adopted 2026-10-21), on the
/// system tab bar (Anycast 2.0 UI kit shell): Liquid Glass on iOS 26, where
/// Search stands apart from the other tabs, the bar minimizes while content
/// scrolls down and the mini player rides in the bar's bottom accessory; on
/// iOS 18 the classic bar with the mini player floating above it as a
/// capsule. Unselected tabs stay resident (prewarmed) like the Flutter
/// IndexedStack (03 §1.1).
@MainActor
final class MainTabBarController: UITabBarController, UITabBarControllerDelegate {

    private let context: UIContext
    /// Each destination tab's normal and selected glyph; the selected tab
    /// shows the filled variant.
    private var tabImages: [String: (normal: UIImage, selected: UIImage)] = [:]
    /// Every tab's root, resident from launch (a tab's provider runs lazily).
    private var tabRoots: [UIViewController] = []
    /// The fly-in endpoint's target (`TabBarFlyInEndpointProvider`).
    private(set) var playlistTab: UITab?

    private let errorObservation = ObservationLoop()
    private let visibilityObservation = ObservationLoop()

    private let playerBar: PlayerBarView
    /// iOS 18 floating capsule placement (above the tab bar).
    private var floatingBottomConstraint: NSLayoutConstraint?
    /// iOS 18: melts the pages' rows into the page colour behind the
    /// capsule, so they are not hard-cut around it.
    private var floatingFade: ScrollEdgeFade?
    /// iOS 26+: the same melt behind the glass bottom bars (mini player
    /// accessory + tab bar or search field), so list text never reads
    /// through them. Tracks the system's content layout guide, so it follows
    /// the bars when the tab bar minimizes.
    private(set) var bottomBarFade: ScrollEdgeFade?

    private enum FloatingMetrics {
        /// Gap between the floating capsule and the tab bar / content.
        static let gap: CGFloat = Spacing.md
    }

    init(context: UIContext) {
        self.context = context
        if #available(iOS 26.0, *) {
            self.playerBar = context.makePlayerBar(style: .systemAccessory)
        } else {
            self.playerBar = context.makePlayerBar(style: .capsule)
        }
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        Theme.installPageBase(on: view)
        delegate = self
        tabBar.tintColor = Theme.primary

        let destinations: [(UIViewController, String, UIImage, UIImage)] = [
            (InboxPageViewController(context: context), "Podcast", AppIcons.inbox, AppIcons.inboxSelected),
            (PlaylistsPageViewController(context: context), "Playlist", AppIcons.playlist, AppIcons.playlistSelected),
            (DiscoverViewController(context: context), "Discover", AppIcons.discover, AppIcons.discoverSelected),
        ]
        var tabs: [UITab] = destinations.enumerated().map { index, destination in
            let (controller, title, icon, selectedIcon) = destination
            let identifier = "tab-\(index)"
            // Resident pages: their timers and observers start at launch.
            controller.loadViewIfNeeded()
            tabImages[identifier] = (icon, selectedIcon)
            let tab = UITab(title: title, image: index == 0 ? selectedIcon : icon, identifier: identifier) { _ in
                controller
            }
            tab.accessibilityIdentifier = identifier
            return tab
        }
        let searchRoot = SearchPageViewController.makeTabRoot(context: context)
        searchRoot.loadViewIfNeeded()
        let searchTab = UISearchTab { _ in searchRoot }
        searchTab.accessibilityIdentifier = "tab-search"
        if #available(iOS 26.0, *) {
            searchTab.automaticallyActivatesSearch = true
        }
        tabs.append(searchTab)
        tabRoots = destinations.map(\.0) + [searchRoot]
        playlistTab = tabs[1]
        self.tabs = tabs

        if #available(iOS 26.0, *) {
            tabBarMinimizeBehavior = .onScrollDown
            installBottomBarFade()
        } else {
            installFloatingPlayerBar()
        }

        observePlaybackError()
        updateMiniPlayerVisibility(animated: false)
        visibilityObservation.track(
            read: { [weak self] in _ = self?.context.playback.queue },
            onChange: { [weak self] in self?.updateMiniPlayerVisibility(animated: true) }
        )
    }

    // MARK: - Selection

    /// The tab-0 re-tap rule (03 §1.1): the Feeds screen owns the
    /// scroll-vs-refresh decision via TabZeroRetap.
    func tabBarController(_ tabBarController: UITabBarController, shouldSelectTab tab: UITab) -> Bool {
        if tab === selectedTab, tab === tabs.first {
            context.tabs.handleTabZeroReTap()
        }
        if tab !== selectedTab {
            Haptics.selection()
        }
        return true
    }

    func tabBarController(
        _ tabBarController: UITabBarController, didSelectTab selectedTab: UITab, previousTab: UITab?
    ) {
        for tab in [previousTab, selectedTab].compactMap({ $0 }) {
            guard let images = tabImages[tab.identifier] else { continue }
            tab.image = tab === selectedTab ? images.selected : images.normal
        }
    }

    /// Programmatic selection (UIContext.tabs.select): 0–2 are the
    /// destinations, 3 is Search.
    func selectTab(_ index: Int) {
        guard tabs.indices.contains(index) else { return }
        let previous = selectedTab
        selectedTab = tabs[index]
        tabBarController(self, didSelectTab: tabs[index], previousTab: previous)
    }

    // MARK: - K6: playback failure toast

    private func observePlaybackError() {
        errorObservation.track(
            read: { [weak self] in _ = self?.context.playback.playbackError },
            onChange: { [weak self] in
                guard let self,
                      let message = self.context.playback.playbackError,
                      let window = self.view.window
                else { return }
                // The retry affordance belongs to the player page (T4);
                // the shell only surfaces the failure.
                ToastPresenter.shared.show(message, in: window)
            }
        )
    }

    // MARK: - Bottom bar fade (iOS 26+)

    /// A page-background gradient behind the system bars and above the tab
    /// roots: solid from the bars' top edge to the screen bottom, ramping to
    /// clear over `ScrollEdgeFade.fadeLength` above them. The system soft
    /// edge effect stays on the scroll views; this gives the glass a calm
    /// surface to sample and keeps list text from showing through. Its top
    /// follows `contentLayoutGuide`, which the system moves with the
    /// accessory and the minimizing tab bar.
    @available(iOS 26.0, *)
    private func installBottomBarFade() {
        let fade = ScrollEdgeFade(edge: .bottom)
        // Between the page content and the container that hosts the bars.
        var barContainer: UIView? = tabBar
        while let candidate = barContainer, candidate.superview !== view { barContainer = candidate.superview }
        if let barContainer {
            view.insertSubview(fade, belowSubview: barContainer)
        } else {
            view.insertSubview(fade, belowSubview: tabBar)
        }
        NSLayoutConstraint.activate([
            fade.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            fade.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            fade.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            fade.topAnchor.constraint(
                equalTo: contentLayoutGuide.bottomAnchor, constant: -ScrollEdgeFade.fadeLength
            ),
        ])
        bottomBarFade = fade
    }

    // MARK: - Mini player hosting

    private func installFloatingPlayerBar() {
        playerBar.translatesAutoresizingMaskIntoConstraints = false
        view.insertSubview(playerBar, belowSubview: tabBar)
        let bottom = playerBar.bottomAnchor.constraint(equalTo: tabBar.topAnchor, constant: -FloatingMetrics.gap)
        floatingBottomConstraint = bottom
        NSLayoutConstraint.activate([
            playerBar.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: Spacing.pageH),
            playerBar.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -Spacing.pageH),
            bottom,
        ])

        // The ramp starts where resting content ends (a gap above the
        // capsule) and runs solid down to the tab bar.
        let fade = ScrollEdgeFade(edge: .bottom)
        view.insertSubview(fade, belowSubview: playerBar)
        NSLayoutConstraint.activate([
            fade.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            fade.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            fade.bottomAnchor.constraint(equalTo: tabBar.topAnchor),
            fade.topAnchor.constraint(equalTo: playerBar.topAnchor, constant: -FloatingMetrics.gap),
        ])
        floatingFade = fade
    }

    /// The mini player shows while the queue has episodes (03 §2.9). On
    /// iOS 26 the system accessory carries it and adjusts content insets
    /// itself; the iOS 18 capsule makes the pages avoid it explicitly.
    private func updateMiniPlayerVisibility(animated: Bool) {
        let visible = MiniPlayerVisibility.isVisible(queueCount: context.playback.queue.count)
        if #available(iOS 26.0, *) {
            if visible, bottomAccessory == nil {
                setBottomAccessory(UITabAccessory(contentView: playerBar), animated: animated)
            } else if !visible, bottomAccessory != nil {
                setBottomAccessory(nil, animated: animated)
            }
            return
        }
        let changes = { [weak self] in
            guard let self else { return }
            self.playerBar.isHidden = !visible
            self.floatingFade?.isHidden = !visible
        }
        if animated {
            UIView.animate(withDuration: Motion.quick, animations: changes)
        } else {
            changes()
        }
        let avoidance = visible ? PlayerBarView.barHeight + FloatingMetrics.gap * 2 : 0
        for child in tabRoots {
            child.additionalSafeAreaInsets.bottom = avoidance
        }
    }
}
