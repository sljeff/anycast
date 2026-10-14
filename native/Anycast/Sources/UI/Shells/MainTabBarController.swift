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
/// widget #11): Playlist is the middle destination, so the endpoint is the
/// bar's center — degrading to the window bottom center when the bar is not
/// on screen (A1-accepted adaptation). The shell attaches itself through
/// `tabBarProvider` at install time.
@MainActor
final class TabBarFlyInEndpointProvider: PlaylistFlyInEndpointProvider {

    var tabBarProvider: (() -> UITabBar?)?

    private let fallback = WindowCenterBottomEndpointProvider()

    func playlistFlyInEndpoint(in window: UIWindow) -> CGPoint {
        guard let tabBar = tabBarProvider?(), tabBar.window != nil, !tabBar.isHidden else {
            return fallback.playlistFlyInEndpoint(in: window)
        }
        return window.convert(CGPoint(x: tabBar.bounds.midX, y: tabBar.bounds.midY), from: tabBar)
    }
}

/// The three-tab Flutter destination shell — Podcast / Playlist / Discover —
/// on the system tab bar (Anycast 2.0 UI kit shell): Liquid Glass on
/// iOS 26, where the bar minimizes while content scrolls down and the mini
/// player rides in the bar's bottom accessory; on iOS 18 the classic bar
/// with the mini player floating above it as a capsule. Unselected tabs
/// stay resident (prewarmed) like the Flutter IndexedStack (03 §1.1).
@MainActor
final class MainTabBarController: UITabBarController, UITabBarControllerDelegate {

    private let context: UIContext

    private let errorObservation = ObservationLoop()
    private let visibilityObservation = ObservationLoop()

    private let playerBar: PlayerBarView
    /// iOS 18 floating capsule placement (above the tab bar).
    private var floatingBottomConstraint: NSLayoutConstraint?

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

        let tabs: [(UIViewController, String, UIImage, UIImage)] = [
            (PodcastHomeViewController(context: context), "Podcast", AppIcons.inbox, AppIcons.inboxSelected),
            (PlaylistsPageViewController(context: context), "Playlist", AppIcons.playlist, AppIcons.playlistSelected),
            (DiscoverViewController(context: context), "Discover", AppIcons.discover, AppIcons.discoverSelected),
        ]
        viewControllers = tabs.enumerated().map { index, tab in
            let (controller, title, icon, selectedIcon) = tab
            controller.tabBarItem = UITabBarItem(title: title, image: icon, selectedImage: selectedIcon)
            controller.tabBarItem.tag = index
            controller.tabBarItem.accessibilityIdentifier = "tab-\(index)"
            // Resident pages: their timers and observers start at launch.
            controller.loadViewIfNeeded()
            return controller
        }

        if #available(iOS 26.0, *) {
            tabBarMinimizeBehavior = .onScrollDown
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
    func tabBarController(
        _ tabBarController: UITabBarController, shouldSelect viewController: UIViewController
    ) -> Bool {
        if viewController === selectedViewController, viewControllers?.firstIndex(of: viewController) == 0 {
            context.tabs.handleTabZeroReTap()
        }
        if viewController !== selectedViewController {
            Haptics.selection()
        }
        return true
    }

    /// Programmatic selection (UIContext.tabs.select).
    func selectTab(_ index: Int) {
        guard let controllers = viewControllers, controllers.indices.contains(index) else { return }
        selectedIndex = index
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
        }
        if animated {
            UIView.animate(withDuration: Motion.quick, animations: changes)
        } else {
            changes()
        }
        let avoidance = visible ? PlayerBarView.barHeight + FloatingMetrics.gap * 2 : 0
        for child in viewControllers ?? [] {
            child.additionalSafeAreaInsets.bottom = avoidance
        }
    }
}
