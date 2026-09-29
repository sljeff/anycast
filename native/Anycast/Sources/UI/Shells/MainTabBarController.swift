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

/// The Feeds screen (later M3 task) implements this; the shell dispatches
/// through `UIContext.tabs`. NOTE the quirk: the target is the Inbox list
/// EVEN WHEN the Subscriptions inner tab is currently visible — the shipped
/// code never conditioned on the inner tab (03 §1.1, 2026-09-22 corrigendum).
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

/// Derives the fly-in animation endpoint from the LIVE tab bar layout
/// (07 §3 widget #11): the playlist tab icon's center in the current
/// geometry, degrading to the visible tab bar's area center, then to the
/// window bottom center (A1-accepted adaptation). The shell attaches
/// itself through `tabBarProvider` at install time.
@MainActor
final class TabBarFlyInEndpointProvider: PlaylistFlyInEndpointProvider {

    var tabBarProvider: (() -> MainTabBarController?)?

    private let fallback = WindowCenterBottomEndpointProvider()

    func playlistFlyInEndpoint(in window: UIWindow) -> CGPoint {
        guard let tabBar = tabBarProvider?()?.tabBar else {
            return fallback.playlistFlyInEndpoint(in: window)
        }
        let buttons = Self.tabBarButtons(in: tabBar)
        if !buttons.isEmpty {
            // With 3 tabs the playlist item is the middle button; clamp the
            // index so a degenerate hierarchy cannot over-read.
            let index = min(1, buttons.count - 1)
            return window.convert(buttons[index].center, from: tabBar)
        }
        if tabBar.window != nil {
            return window.convert(CGPoint(x: tabBar.bounds.midX, y: tabBar.bounds.midY), from: tabBar)
        }
        return fallback.playlistFlyInEndpoint(in: window)
    }

    /// The private tab bar buttons, x-sorted. Recursively searched by class
    /// name (the buttons are not guaranteed to be DIRECT subviews on every
    /// OS layout), degrading to the previous direct-subview heuristic when
    /// the private class is not found.
    private static func tabBarButtons(in tabBar: UITabBar) -> [UIView] {
        var found: [UIView] = []
        func visit(_ view: UIView) {
            if NSStringFromClass(type(of: view)).contains("UITabBarButton") {
                found.append(view)
                return
            }
            for subview in view.subviews {
                visit(subview)
            }
        }
        visit(tabBar)
        if found.isEmpty {
            return tabBar.subviews
                .filter { $0.frame.width > 1 && !$0.isHidden && $0.alpha > 0.01 }
                .sorted { $0.frame.minX < $1.frame.minX }
        }
        return found.sorted { $0.frame.minX < $1.frame.minX }
    }
}

/// The three-tab shell (03 §1.1): children stay resident (IndexedStack
/// equivalent) and are all PREWARMED at startup — a first tab switch must
/// be instant, including Discover's eager category prefetch, which fires
/// from its own load (07 §2.1 note). iOS 26 gets the floating glass tab
/// bar automatically; the mini player lives in `bottomAccessory` there and
/// in a floating view above the tab bar on iOS 18 (widget #10 fallback —
/// the ONLY place besides GlassContainerView that branches on iOS 26).
@MainActor
final class MainTabBarController: UITabBarController, UITabBarControllerDelegate {

    private let context: UIContext

    private let errorObservation = ObservationLoop()
    private let visibilityObservation = ObservationLoop()

    /// Style follows the host the shell will actually use: the iOS 26+
    /// tab accessory draws the glass capsule itself, so the bar draws no
    /// background of its own; the iOS 18 floating fallback is standalone.
    private lazy var playerBar: PlayerBarView = {
        if #available(iOS 26.0, *) {
            return context.makePlayerBar(style: .systemAccessory)
        }
        return context.makePlayerBar(style: .standalone)
    }()
    /// Stored as AnyObject — the UITabAccessory type is iOS 26-only and
    /// stored properties must match the class's availability.
    private var accessory: AnyObject?
    private var floatingBarInstalled = false

    /// didSelect fires on user taps only; this tracks what was selected
    /// before the tap to detect re-taps (previousSelectedIndex is private
    /// API).
    private var lastUserSelectedIndex = 0

    private enum FallbackMetrics {
        /// Single source: the mini player's own height constant.
        static let barHeight: CGFloat = PlayerBarView.barHeight
        static let barBottomGap: CGFloat = 8
        static var totalAvoidance: CGFloat { barHeight + barBottomGap }
    }

    init(context: UIContext) {
        self.context = context
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        Theme.installDarkBase(on: view)
        delegate = self

        let podcasts = PodcastsTabContainer(context: context)
        podcasts.tabBarItem = Self.tabItem(title: "Podcast", image: AppIcons.home)

        let playlists = PlaylistsPageViewController(context: context)
        playlists.tabBarItem = Self.tabItem(title: "Playlist", image: AppIcons.playlist)

        let discover = DiscoverViewController(context: context)
        discover.tabBarItem = Self.tabItem(title: "Discover", image: AppIcons.discover)

        viewControllers = [podcasts, playlists, discover]

        tabBar.tintColor = Theme.tabSelectedGreen
        tabBar.unselectedItemTintColor = Theme.secondaryLabelGray

        // Prewarm (07 §2.1): all three children build their views NOW so
        // the first switch is instant.
        for child in children {
            child.loadViewIfNeeded()
        }

        lastUserSelectedIndex = selectedIndex

        observePlaybackError()
        updateMiniPlayerVisibility(animated: false)
        visibilityObservation.track(
            read: { [weak self] in _ = self?.context.playback.queue },
            onChange: { [weak self] in self?.updateMiniPlayerVisibility(animated: true) }
        )
    }

    private static func tabItem(title: String, image: UIImage) -> UITabBarItem {
        let item = UITabBarItem(title: title, image: image, selectedImage: nil)
        item.accessibilityLabel = title
        return item
    }

    // MARK: - Programmatic selection (UIContext.tabs.select)

    func selectTab(_ index: Int) {
        guard children.indices.contains(index) else { return }
        selectedIndex = index
        // Programmatic moves participate in the re-tap baseline: without
        // this, selectTab(2) followed by a user tap on tab 0 reads as a
        // re-tap (lastUserSelectedIndex still 0) and wrongly fires the
        // scroll-to-top refresh.
        lastUserSelectedIndex = index
    }

    // MARK: - Tab-0 re-tap (03 §1.1)

    func tabBarController(_ tabBarController: UITabBarController, didSelect viewController: UIViewController) {
        defer { lastUserSelectedIndex = selectedIndex }
        guard viewController === children.first, lastUserSelectedIndex == 0 else { return }
        // Quirk preserved: this targets the Inbox list regardless of which
        // inner tab is visible; the Feeds screen owns the scroll-vs-refresh
        // decision via TabZeroRetap.action.
        context.tabs.handleTabZeroReTap()
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

    private func updateMiniPlayerVisibility(animated: Bool) {
        let visible = MiniPlayerVisibility.isVisible(queueCount: context.playback.queue.count)
        if #available(iOS 26.0, *) {
            // System-managed glass/size; hiding is add/remove, there is no
            // isHidden (07 §2.1).
            if visible {
                if accessory == nil {
                    accessory = UITabAccessory(contentView: playerBar)
                }
                if bottomAccessory == nil, let accessory = accessory as? UITabAccessory {
                    setBottomAccessory(accessory, animated: animated)
                }
            } else if bottomAccessory != nil {
                setBottomAccessory(nil, animated: animated)
            }
        } else {
            // iOS 18 fallback (07 §3 widget #10): a floating view above the
            // tab bar; resident screens avoid it through
            // additionalSafeAreaInsets.
            playerBar.isHidden = !visible
            if visible, !floatingBarInstalled {
                floatingBarInstalled = true
                playerBar.translatesAutoresizingMaskIntoConstraints = false
                view.insertSubview(playerBar, aboveSubview: tabBar)
                NSLayoutConstraint.activate([
                    playerBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                    playerBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
                    playerBar.bottomAnchor.constraint(
                        equalTo: tabBar.topAnchor, constant: -FallbackMetrics.barBottomGap
                    ),
                ])
            }
            let avoidance = visible ? FallbackMetrics.totalAvoidance : 0
            for child in children {
                child.additionalSafeAreaInsets.bottom = avoidance
            }
        }
    }
}
