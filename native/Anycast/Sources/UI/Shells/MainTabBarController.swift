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

/// Derives the fly-in animation endpoint from the LIVE pill bar layout
/// (07 §3 widget #11): the queue chip's center in the current geometry —
/// with the v2 pill bar the middle chip (index 1) is the queue entry —
/// degrading to the visible bar's area center, then to the window bottom
/// center (A1-accepted adaptation). The shell attaches itself through
/// `pillBarProvider` at install time.
@MainActor
final class TabBarFlyInEndpointProvider: PlaylistFlyInEndpointProvider {

    var pillBarProvider: (() -> BottomTabBarView?)?

    private let fallback = WindowCenterBottomEndpointProvider()

    func playlistFlyInEndpoint(in window: UIWindow) -> CGPoint {
        guard let pillBar = pillBarProvider?(), pillBar.window != nil else {
            return fallback.playlistFlyInEndpoint(in: window)
        }
        let buttons = pillBar.pillButtons
        if !buttons.isEmpty {
            // With 3 chips the queue entry is the middle one; clamp the
            // index so a degenerate hierarchy cannot over-read.
            let index = min(1, buttons.count - 1)
            let button = buttons[index]
            let host = button.superview ?? pillBar
            guard host.window != nil else {
                return fallback.playlistFlyInEndpoint(in: window)
            }
            return window.convert(button.center, from: host)
        }
        return window.convert(
            CGPoint(x: pillBar.bounds.midX, y: pillBar.bounds.midY), from: pillBar
        )
    }
}

/// The v2 three-tab shell (09 §3.1/§10 V2): a plain self-managed container
/// — NOT a UITabBarController — hosting the BottomTabBarView pill over
/// full-bleed resident children (Inbox / queue / library), all PREWARMED at
/// startup. The Discover tab retired (09 §3.5 — discovery moves to the
/// search circle); the search circle pushes the search entry sheet. The
/// mini player is the v2 floating capsule above the pill on every OS —
/// with the custom pill bar there is no UITabBarController left to host a
/// UITabAccessory, so the former iOS 26 accessory path folds into the same
/// floating capsule (09 §3.6, V2 note).
@MainActor
final class MainTabBarController: UIViewController {

    private let context: UIContext

    private let errorObservation = ObservationLoop()
    private let visibilityObservation = ObservationLoop()

    private var tabChildren: [UIViewController] = []
    /// The full-bleed pins per child — a detached view's constraints are
    /// auto-deactivated by UIKit, so `show` re-activates them on attach.
    private var childPins: [[NSLayoutConstraint]] = []
    private(set) var selectedIndex = 0

    /// The pill bar (BottomTabBarView owns the scrim, chips, search circle).
    private(set) var tabBarView: BottomTabBarView!
    /// The v2 mini player capsule, floating above the pill.
    private let playerBar: PlayerBarView

    /// Chrome constraints re-fitted when the bottom safe-area inset arrives.
    private var tabBarHeightConstraint: NSLayoutConstraint!
    private var playerBarBottomConstraint: NSLayoutConstraint!

    /// Chrome geometry. The pill sits `bottomGutter` above the bottom
    /// SAFE-AREA edge (the home-indicator zone — the Figma clone keeps the
    /// pill clear of the indicator), so every derived metric depends on the
    /// current bottom inset. `safeBottom: 0` reproduces the pre-indicator
    /// layout (unit tests host the shell without safe-area insets).
    private enum ChromeMetrics {
        // The Figma scrim (Buttom Tab component 243:7288) pads 24 above the
        // pill before fading from transparent — the fade zone, not a tall
        // frosted band.
        static let scrimAbovePill: CGFloat = 24
        // The dark design frame (76:2614 render): the mini player card's
        // bottom sits 14 pt above the pill's top edge. The first v2 build
        // anchored the capsule above the whole scrim band (32 pt gap), which
        // read as a floating blank strip between the two.
        static let capsuleGap: CGFloat = 14
        static func pillTopInset(safeBottom: CGFloat) -> CGFloat {
            safeBottom + BottomTabBarView.bottomGutter + BottomTabBarView.pillHeight
        }
        static func barOverlayHeight(safeBottom: CGFloat) -> CGFloat {
            scrimAbovePill + pillTopInset(safeBottom: safeBottom)
        }
        /// The mini player floats above the PILL TOP (not the scrim band).
        static func restingClearance(safeBottom: CGFloat) -> CGFloat {
            pillTopInset(safeBottom: safeBottom) + capsuleGap
        }
        static func capsuleClearance(safeBottom: CGFloat) -> CGFloat {
            restingClearance(safeBottom: safeBottom) + PlayerBarView.barHeight + capsuleGap
        }
    }

    init(context: UIContext) {
        self.context = context
        self.playerBar = context.makePlayerBar(style: .capsule)
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        Theme.installDarkBase(on: view)

        tabChildren = [
            InboxPageViewController(context: context),
            PlaylistsPageViewController(context: context),
            LibraryViewController(context: context),
        ]

        for child in tabChildren {
            addChild(child)
            child.view.translatesAutoresizingMaskIntoConstraints = false
            // Full-bleed pins, activated on attach in `show` — only the
            // SELECTED child's view stays in the hierarchy (the
            // UITabBarController semantics: unselected children remain
            // resident but windowless, so walk-based QA sweeps and layout
            // passes do not run over hidden tabs).
            childPins.append([
                child.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                child.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
                child.view.topAnchor.constraint(equalTo: view.topAnchor),
                child.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            ])
            child.didMove(toParent: self)
            child.loadViewIfNeeded()
        }

        tabBarView = BottomTabBarView(items: [
            .init(title: "Inbox", icon: AppIcons.inbox),
            .init(title: "queue", icon: AppIcons.playlist),
            .init(title: "library", icon: AppIcons.subscriptions),
        ])
        tabBarView.translatesAutoresizingMaskIntoConstraints = false
        tabBarView.onTabTap = { [weak self] index, isRetap in
            self?.handleTabTap(index: index, isRetap: isRetap)
        }
        tabBarView.onSearchTap = { [weak self] in self?.openSearch() }
        view.addSubview(tabBarView)
        tabBarHeightConstraint = tabBarView.heightAnchor.constraint(
            equalToConstant: ChromeMetrics.barOverlayHeight(safeBottom: view.safeAreaInsets.bottom)
        )
        NSLayoutConstraint.activate([
            tabBarView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tabBarView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tabBarView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            tabBarHeightConstraint,
        ])

        playerBar.translatesAutoresizingMaskIntoConstraints = false
        view.insertSubview(playerBar, belowSubview: tabBarView)
        playerBarBottomConstraint = playerBar.bottomAnchor.constraint(
            equalTo: view.bottomAnchor,
            constant: -ChromeMetrics.restingClearance(safeBottom: view.safeAreaInsets.bottom)
        )
        NSLayoutConstraint.activate([
            playerBar.leadingAnchor.constraint(
                equalTo: view.leadingAnchor, constant: BottomTabBarView.horizontalInset
            ),
            playerBar.trailingAnchor.constraint(
                equalTo: view.trailingAnchor, constant: -BottomTabBarView.horizontalInset
            ),
            playerBarBottomConstraint,
        ])

        show(index: 0)

        observePlaybackError()
        updateMiniPlayerVisibility(animated: false)
        visibilityObservation.track(
            read: { [weak self] in _ = self?.context.playback.queue },
            onChange: { [weak self] in self?.updateMiniPlayerVisibility(animated: true) }
        )
    }

    override func viewSafeAreaInsetsDidChange() {
        super.viewSafeAreaInsetsDidChange()
        // The pill clears the home-indicator zone (BottomTabBarView pins
        // itself to the safe-area edge), so the scrim height, the mini
        // player's resting spot, and the children's content avoidance all
        // shift with the bottom inset.
        let safeBottom = view.safeAreaInsets.bottom
        tabBarHeightConstraint.constant = ChromeMetrics.barOverlayHeight(safeBottom: safeBottom)
        playerBarBottomConstraint.constant = -ChromeMetrics.restingClearance(safeBottom: safeBottom)
        updateMiniPlayerVisibility(animated: false)
    }

    // MARK: - Selection

    private func handleTabTap(index: Int, isRetap: Bool) {
        show(index: index)
        // The tab-0 re-tap rule (03 §1.1) rides the pill now; the Feeds
        // screen owns the scroll-vs-refresh decision via TabZeroRetap.
        if isRetap, index == 0 {
            context.tabs.handleTabZeroReTap()
        }
    }

    /// Resident-page switch: attach/detach the child views (the
    /// IndexedStack equivalent — 03 §1.1). Appearance transitions are
    /// driven MANUALLY once the shell is in a window — the resident pages'
    /// viewWillAppear quiet-refresh paths (Subscriptions, playlist lists)
    /// relied on UITabBarController firing them per switch.
    private func show(index: Int) {
        guard tabChildren.indices.contains(index) else { return }
        selectedIndex = index
        let inWindow = view.window != nil
        for (position, child) in tabChildren.enumerated() {
            if position == index {
                if child.view.superview == nil {
                    view.insertSubview(child.view, at: 0)
                    NSLayoutConstraint.activate(childPins[position])
                    if inWindow {
                        child.beginAppearanceTransition(true, animated: false)
                        child.endAppearanceTransition()
                    }
                }
            } else if child.view.superview != nil {
                if inWindow {
                    child.beginAppearanceTransition(false, animated: false)
                }
                NSLayoutConstraint.deactivate(childPins[position])
                child.view.removeFromSuperview()
                if inWindow {
                    child.endAppearanceTransition()
                }
            }
        }
        tabBarView.select(index, animated: false)
    }

    /// Programmatic selection (UIContext.tabs.select).
    func selectTab(_ index: Int) {
        show(index: index)
    }

    // MARK: - Search entry (09 §3.1: tap pushes the search screen)

    private func openSearch() {
        AppSheets.presentForm(
            SearchEntryViewController(context: context),
            from: topMostPresented()
        )
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

    // MARK: - Mini player hosting (v2 floating capsule, 09 §3.6)

    private func updateMiniPlayerVisibility(animated: Bool) {
        let visible = MiniPlayerVisibility.isVisible(queueCount: context.playback.queue.count)
        let changes = { [weak self] in
            guard let self else { return }
            self.playerBar.isHidden = !visible
        }
        if animated {
            UIView.animate(withDuration: Motion.quick, animations: changes)
        } else {
            changes()
        }
        let avoidance = visible
            ? ChromeMetrics.capsuleClearance(safeBottom: view.safeAreaInsets.bottom)
            : ChromeMetrics.restingClearance(safeBottom: view.safeAreaInsets.bottom)
        for child in tabChildren {
            child.additionalSafeAreaInsets.bottom = avoidance
        }
    }
}
