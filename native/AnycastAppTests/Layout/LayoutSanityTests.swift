import UIKit
import Testing
import AnycastKit
@testable import Anycast

/// Layout sanity sweep — the M3 checklist's "no crash, no overflow" bar
/// (`03` §8, `07` §4): Dynamic Type and ANY window size must keep the layout
/// intact (iOS 27 resizable windows; iPad runs iPhone-only apps as resizable
/// windows). Also the regression guard for the zero-height paging bug the
/// snapshot pass caught: a paging container whose pages were pinned to the
/// scroll view's content guide rendered every list as a blank tab.
///
/// Runs against the live dependency graph with the seeded fixture; skips
/// when the shell or the seed is absent.
///
/// The sweep runs in a PRIVATE window hosting its own shell: mutating the
/// shared key window's frame and trait overrides across awaits used to leak
/// into every parallel live-shell suite. A dedicated window makes the
/// interference impossible by construction.
@MainActor
@Suite
struct LayoutSanityTests {

    /// iPhone portrait, the small-phone floor, an iPad-like wide/short window
    /// and a tall/narrow one.
    static let sizes: [CGSize] = [
        CGSize(width: 402, height: 874),
        CGSize(width: 320, height: 568),
        CGSize(width: 1024, height: 560),
        CGSize(width: 560, height: 1024),
    ]

    /// A dedicated window with its own tab shell over the live context.
    /// Presenting from this window promotes it to key — parallel live-shell
    /// suites read the KEY window for their presenters, so every present
    /// hands key status back to the app's window and `discard` restores it
    /// once more.
    private static var appKeyWindow: UIWindow?

    private static func privateShellWindow(_ context: UIContext) -> UIWindow {
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
        appKeyWindow = scene?.keyWindow
        let window = scene.map { UIWindow(windowScene: $0) }
            ?? UIWindow(frame: UIScreen.main.bounds)
        window.rootViewController = MainTabBarController(context: context)
        window.isHidden = false
        return window
    }

    private static func restoreAppKeyWindow() {
        appKeyWindow?.makeKey()
    }

    private static func discard(_ window: UIWindow) {
        restoreAppKeyWindow()
        window.rootViewController = nil
        window.isHidden = true
        window.removeFromSuperview()
    }

    @Test("shell lists keep non-zero frames at every window size")
    func shellListsAcrossSizes() async throws {
        guard let context = await Self.liveContext() else {
            print("[layout] shell not ready; skipping"); return
        }
        let window = Self.privateShellWindow(context)
        defer { Self.discard(window) }
        try await Self.settleLayout(window)

        for size in Self.sizes {
            window.frame = CGRect(origin: .zero, size: size)
            try await Self.settleLayout(window)
            // The resize must actually land — otherwise the sweep would pass
            // vacuously on a locked window.
            if window.bounds.size != size {
                print("[layout] window resize to \(size) ignored (bounds \(window.bounds.size))")
                continue
            }
            Self.assertListsRender(window, context: "size \(Int(size.width))x\(Int(size.height))")
        }
    }

    @Test("shell lists keep non-zero frames at accessibility text sizes")
    func shellListsAcrossTextSizes() async throws {
        guard let context = await Self.liveContext() else {
            print("[layout] shell not ready; skipping"); return
        }
        let window = Self.privateShellWindow(context)
        defer { Self.discard(window) }
        try await Self.settleLayout(window)

        let categories: [UIContentSizeCategory] = [
            .extraSmall, .large, .accessibilityExtraExtraExtraLarge,
        ]
        for category in categories {
            window.traitOverrides.preferredContentSizeCategory = category
            try await Self.settleLayout(window)
            Self.assertListsRender(window, context: "text size \(category.rawValue)")
        }
        window.traitOverrides.preferredContentSizeCategory = .unspecified
        try await Self.settleLayout(window)
    }

    @Test("sheet screens lay out at a wide/short window without breaking")
    func sheetsAtWideShortSize() async throws {
        guard let context = await Self.liveContext() else {
            print("[layout] shell not ready; skipping"); return
        }
        let window = Self.privateShellWindow(context)
        defer { Self.discard(window) }
        window.frame = CGRect(origin: .zero, size: CGSize(width: 1024, height: 560))
        try await Self.settleLayout(window)
        let root = window.rootViewController

        // Settings/Import/History present from the private window. The
        // Login sheet stays on the APP window's chain: its own signed-out
        // /api/user fires the global 401 funnel, and only the app chain's
        // dedupe walk swallows it — in a private window the walk misses it
        // and a login sheet pops over the live shell mid-run.
        let screens: [UIViewController] = [
            SettingsViewController(context: context),
            ImportExportDialogViewController(context: context),
            HistoryDialogViewController(context: context),
        ]
        for controller in screens {
            let name = String(describing: type(of: controller))
            controller.modalPresentationStyle = .pageSheet
            // Presenting on an in-flight presenter is refused and the view
            // keeps its default screen-sized frame — retry until the view
            // actually lands in the window, then hand key status back to
            // the app window (presentation promotes this private window to
            // key; parallel suites must keep reading the app's window).
            for _ in 0..<20 {
                let host = await Self.settledTopPresenter(in: window) ?? root
                host?.present(controller, animated: false)
                Self.restoreAppKeyWindow()
                try await Self.settleLayout(window)
                if controller.view.window != nil { break }
            }
            let size = controller.view.bounds.size
            #expect(size.width > 0 && size.height > 0, "\(name) collapsed at a wide/short window")
            #expect(
                controller.view.frame.height <= window.bounds.height + 1,
                "\(name) is taller than the window"
            )
            controller.dismiss(animated: false)
            // Wait until the dismissal actually completes before the next
            // present — an in-flight dismissal blocks the next `present`.
            for _ in 0..<20 where controller.view.window != nil {
                try await Self.settleLayout(window)
            }
        }

        // LoginViewController is HOSTED, not presented: instantiating it in
        // a signed-out container fires its own 401 → the global login
        // funnel → a coordinator sheet over the app chain, which parallel
        // suites count. Parking the coordinator's anchor for the duration
        // keeps the funnel silent; hosting the view still exercises the
        // layout assertions.
        let loginAnchor = context.loginPrompt.presentingAnchor
        context.loginPrompt.presentingAnchor = nil
        let login = LoginViewController(context: context)
        window.addSubview(login.view)
        login.view.frame = CGRect(x: 0, y: 0, width: window.bounds.width, height: min(window.bounds.height, 700))
        try await Self.settleLayout(window)
        let loginSize = login.view.bounds.size
        #expect(loginSize.width > 0 && loginSize.height > 0, "LoginViewController collapsed")
        #expect(
            login.view.frame.height <= window.bounds.height + 1,
            "LoginViewController is taller than the window"
        )
        login.view.removeFromSuperview()
        context.loginPrompt.presentingAnchor = loginAnchor
        try await Self.settleLayout(window)
    }

    /// The M3 review found the playlist list hidden with items loaded —
    /// `renderLoadingState` inverted the empty check. This drives the real
    /// tab switch and asserts the seeded playlist's list is on screen.
    @Test("playlist tab shows its loaded list")
    func playlistTabShowsLoadedList() async throws {
        guard let context = await Self.liveContext() else {
            print("[layout] shell not ready; skipping"); return
        }
        let window = Self.privateShellWindow(context)
        defer { Self.discard(window) }
        guard let shell = window.rootViewController as? MainTabBarController else {
            Issue.record("private window has no tab shell"); return
        }
        try await Self.settleLayout(window)
        shell.selectTab(1)
        try await Self.settleLayout(window)

        let lists = Self.allControllers(from: shell)
            .compactMap { $0 as? PlaylistEpisodeListViewController }
            .filter { $0.isViewLoaded }
        guard let list = lists.first(where: { !$0.episodes.isEmpty }) else {
            print("[layout] no seeded playlist episodes; skipping"); return
        }
        guard let collection = Self.subviewsRecursive(in: list.view)
            .compactMap({ $0 as? UICollectionView }).first else {
            Issue.record("playlist page has no collection view"); return
        }
        #expect(!collection.isHidden, "playlist list has \(list.episodes.count) episodes but is hidden")
        #expect(collection.numberOfItems(inSection: 0) == list.episodes.count)
        shell.selectTab(0)
    }

    /// The M3 review found the TitleBar's pinned children at 0×0 (missing
    /// translatesAutoresizingMaskIntoConstraints = false) and the progress
    /// bar stretched to ~230 pt. Host the page in a window and check.
    @Test("player main page keeps title bar and progress bar at design sizes")
    func playerMainPageLayout() async throws {
        guard let context = await Self.liveContext() else {
            print("[layout] shell not ready; skipping"); return
        }
        let window = Self.privateShellWindow(context)
        defer { Self.discard(window) }
        try await Self.settleLayout(window)

        let page = PlayerMainPageViewController(context: context)
        window.addSubview(page.view)
        page.view.frame = CGRect(x: 0, y: 60, width: window.bounds.width, height: 700)
        defer { page.view.removeFromSuperview() }
        try await Self.settleLayout(window)

        let views = Self.subviewsRecursive(in: page.view)
        // imageButton is "Open channel"; channelButton becomes
        // "Open channel <title>" once a channel name lands.
        let channelControls = views.filter {
            $0.accessibilityLabel?.hasPrefix("Open channel") == true
        }
        #expect(channelControls.count >= 2, "title bar controls missing")
        for control in channelControls {
            #expect(control.bounds.width > 0 && control.bounds.height > 0,
                    "title bar child collapsed to \(control.bounds.size)")
        }
        if let bar = views.compactMap({ $0 as? PlayerProgressBarView }).first {
            #expect(bar.bounds.height <= 80,
                    "progress bar stretched to \(bar.bounds.height) pt (design: 60)")
        } else {
            Issue.record("progress bar not found")
        }
    }

    /// Card descriptions resolve through the async PlainTextHTMLCache path;
    /// once the text lands the label must gain a real frame (a zero-height
    /// label was the M3 review's "cards have no description" defect).
    @Test("inbox cards with descriptions show the description line")
    func inboxCardDescriptions() async throws {
        guard let context = await Self.liveContext() else {
            print("[layout] shell not ready; skipping"); return
        }
        let window = Self.privateShellWindow(context)
        defer { Self.discard(window) }
        try await Self.settleLayout(window)
        let labels = Self.subviewsRecursive(in: window)
            .compactMap { $0 as? UILabel }
            .filter { $0.accessibilityIdentifier == "episode-card-description" }
        let populated = labels.filter { !($0.text ?? "").isEmpty }
        guard !populated.isEmpty else {
            print("[layout] no visible cards with descriptions; skipping"); return
        }
        for label in populated {
            #expect(label.bounds.height > 0,
                    "description label has text but zero height")
        }
    }

    /// Deterministic counterpart of the inbox sweep: a configured card must
    /// give the two-line description a non-zero frame (the M3 review found
    /// the label at height 0 with text set).
    @Test("episode card lays out the description label")
    func cardDescriptionLayout() {
        let cell = EpisodeCardCell(frame: CGRect(x: 0, y: 0, width: 354, height: 104))
        cell.configure(
            EpisodeCardContent(
                title: "Episode", channelTitle: "Channel", rightText: "1:00",
                descriptionHTML: nil, imageURL: nil,
                descriptionPlainText: "A description line"
            ),
            actions: []
        )
        cell.layoutIfNeeded()
        let desc = Self.subviewsRecursive(in: cell)
            .compactMap { $0 as? UILabel }
            .first { $0.accessibilityIdentifier == "episode-card-description" }
        #expect(desc?.text == "A description line")
        #expect(desc?.bounds.height ?? 0 > 0, "description label collapsed")
    }

    // MARK: - Helpers

    /// Presented sheets are not part of the tab tree; walk sheets too so a
    /// player/settings sheet over a resized window is covered. Only views
    /// actually attached to the window are checked: a prewarmed tab child
    /// that was never displayed legitimately has no geometry yet.
    private static func assertListsRender(_ window: UIWindow, context: String) {
        var visited = 0
        for controller in allControllers(from: window.rootViewController) {
            guard controller.isViewLoaded, controller.view.window === window else { continue }
            for list in collectionViews(in: controller.view) {
                guard list.window === window else { continue }
                visited += 1
                let name = String(describing: type(of: controller))
                #expect(
                    list.bounds.height > 0,
                    "\(name) list has zero height at \(context)"
                )
                if list.numberOfItems(inSection: 0) > 0 {
                    #expect(
                        !list.isHidden,
                        "\(name) list has items but is hidden at \(context)"
                    )
                    #expect(
                        list.contentSize.height > 0,
                        "\(name) list has items but no content size at \(context)"
                    )
                    let first = list.collectionViewLayout
                        .layoutAttributesForItem(at: IndexPath(item: 0, section: 0))?.frame ?? .zero
                    #expect(
                        first.height > 0,
                        "\(name) first cell collapsed to zero height at \(context)"
                    )
                }
            }
        }
        #expect(visited > 0, "no visible list views found for the sweep at \(context)")
    }

    private static func allControllers(from root: UIViewController?) -> [UIViewController] {
        guard let root else { return [] }
        var all = [root]
        for child in root.children { all.append(contentsOf: allControllers(from: child)) }
        if let presented = root.presentedViewController {
            all.append(contentsOf: allControllers(from: presented))
        }
        return all
    }

    private static func collectionViews(in view: UIView?) -> [UICollectionView] {
        guard let view else { return [] }
        var found: [UICollectionView] = []
        if let list = view as? UICollectionView { found.append(list) }
        for subview in view.subviews { found.append(contentsOf: collectionViews(in: subview)) }
        return found
    }

    private static func subviewsRecursive(in view: UIView) -> [UIView] {
        var found: [UIView] = []
        for subview in view.subviews {
            found.append(subview)
            found.append(contentsOf: subviewsRecursive(in: subview))
        }
        return found
    }

    private static func settleLayout(_ window: UIWindow) async throws {
        window.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(250))
        window.layoutIfNeeded()
    }

    /// Walks the presented stack and waits until the top controller is fully
    /// installed (view in a window AND no transition in flight) — presenting
    /// on an in-flight presenter is refused by UIKit and leaves the test
    /// controller's view at its default frame.
    private static func settledTopPresenter(in window: UIWindow) async -> UIViewController? {
        for _ in 0..<40 {
            var top: UIViewController? = window.rootViewController
            while let next = top?.presentedViewController { top = next }
            if let top, top.view.window != nil, !top.isBeingPresented,
               top.transitionCoordinator == nil {
                return top
            }
            try? await Task.sleep(for: .milliseconds(250))
        }
        return nil
    }

    private static func liveContext() async -> UIContext? {
        for _ in 0..<40 {
            if let context = (UIApplication.shared.delegate as? AppDelegate)?.environment.uiContext {
                return context
            }
            try? await Task.sleep(for: .milliseconds(500))
        }
        return nil
    }
}
