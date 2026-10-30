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
        // The show-name button is "Open channel", then "Open channel
        // <title>" once a channel name lands.
        let channelControls = views.filter {
            $0.accessibilityLabel?.hasPrefix("Open channel") == true
        }
        #expect(channelControls.count >= 1, "title block show name missing")
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
        // Only labels the window actually laid out: a configured-but-detached
        // cell (list-section prefetch in this private shell) legitimately has
        // no geometry — same doctrine as the layout-sweep helper.
        let populated = labels.filter { !($0.text ?? "").isEmpty && $0.window != nil }
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

    /// The inbox card (UI kit form): the description and the bottom row both
    /// resolve real frames off the autolayout height chain (a broken chain
    /// shows up as a collapsed description).
    @Test("inbox card lays out description and bottom row")
    func inboxV2CardLayout() {
        let cell = InboxEpisodeCardCell(frame: CGRect(x: 0, y: 0, width: 370, height: 200))
        cell.configure(
            InboxCardContent(
                title: "An episode title that wraps",
                showName: "Just pod",
                metaText: "Nov 21, 2025 · 45 min",
                descriptionHTML: nil,
                imageURL: nil,
                descriptionPlainText: "A description line that also wraps a little"
            )
        )
        cell.layoutIfNeeded()
        let labels = Self.subviewsRecursive(in: cell).compactMap { $0 as? UILabel }
        let desc = labels.first { $0.accessibilityIdentifier == "episode-card-description" }
        #expect(desc?.text == "A description line that also wraps a little")
        #expect(desc?.bounds.height ?? 0 > 0, "v2 description label collapsed")
        // Sentence-case title, show line in the feed's own casing.
        #expect(labels.contains { $0.text == "An episode title that wraps" }, "title recased")
        #expect(labels.contains { $0.text == "Just pod" }, "show name was recased")
        // The more button gets its menu from the mirrored payload.
        cell.menuActions = [
            EpisodeCardAction(icon: UIImage(), accessibilityLabel: "Play") {},
        ]
        #expect(cell.moreButton.menu?.children.count == 1, "more menu not built")
    }

    /// Reconfigure storms (expand taps, playback ticks, membership refresh)
    /// must not blank an already-resolved description: configuring again
    /// with the same HTML keeps the text synchronously.
    @Test("episode card keeps a resolved description across same-HTML reconfigure")
    func cardDescriptionSurvivesReconfigure() async throws {
        let cell = EpisodeCardCell(frame: CGRect(x: 0, y: 0, width: 354, height: 104))
        let content = EpisodeCardContent(
            title: "Episode", channelTitle: "Channel", rightText: "1:00",
            descriptionHTML: "<p>Same description</p>", imageURL: nil
        )
        cell.configure(content, actions: [])
        let desc = try #require(Self.subviewsRecursive(in: cell)
            .compactMap { $0 as? UILabel }
            .first { $0.accessibilityIdentifier == "episode-card-description" })
        try await Self.waitForText(desc)
        let resolved = desc.text
        cell.configure(content, actions: [])
        #expect(desc.text == resolved, "same-HTML reconfigure blanked the description")
    }

    @Test("inbox card keeps a resolved description across same-HTML reconfigure")
    func inboxCardDescriptionSurvivesReconfigure() async throws {
        let cell = InboxEpisodeCardCell(frame: CGRect(x: 0, y: 0, width: 370, height: 200))
        let content = InboxCardContent(
            title: "Episode", showName: "Show", metaText: "1 min",
            descriptionHTML: "<p>Same description</p>", imageURL: nil
        )
        cell.configure(content)
        let desc = try #require(Self.subviewsRecursive(in: cell)
            .compactMap { $0 as? UILabel }
            .first { $0.accessibilityIdentifier == "episode-card-description" })
        try await Self.waitForText(desc)
        let resolved = desc.text
        cell.configure(content)
        #expect(desc.text == resolved, "same-HTML reconfigure blanked the description")
    }

    /// Polls until the async description resolve lands in `label`.
    private static func waitForText(_ label: UILabel) async throws {
        for _ in 0..<100 where (label.text ?? "").isEmpty {
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        try #require(!(label.text ?? "").isEmpty, "description never resolved")
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
                // A legitimately empty column (fresh-install Inbox collapses
                // to zero sections; its empty state is the background view)
                // aborts on numberOfItems(inSection:) — skip those.
                if list.numberOfSections > 0, list.numberOfItems(inSection: 0) > 0 {
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

// MARK: - Card motion (entrance rise-in, action-strip reveal)

/// A window hosting a plain card list, so the motion helpers run against
/// real cells without the app shell.
@MainActor
private final class CardListHost: UIViewController, UICollectionViewDataSource {

    let collectionView: UICollectionView
    let window: UIWindow
    private let count: Int

    init(count: Int) {
        self.count = count
        let item = NSCollectionLayoutItem(layoutSize: NSCollectionLayoutSize(
            widthDimension: .fractionalWidth(1),
            heightDimension: .estimated(EpisodeCardCell.cardRowHeight)
        ))
        let group = NSCollectionLayoutGroup.horizontal(layoutSize: item.layoutSize, subitems: [item])
        let section = NSCollectionLayoutSection(group: group)
        section.interGroupSpacing = EpisodeCardCell.spacing
        collectionView = UICollectionView(
            frame: .zero, collectionViewLayout: UICollectionViewCompositionalLayout(section: section)
        )
        window = UIWindow(frame: CGRect(x: 0, y: 0, width: 402, height: 874))
        super.init(nibName: nil, bundle: nil)
        collectionView.dataSource = self
        collectionView.register(EpisodeCardCell.self, forCellWithReuseIdentifier: EpisodeCardCell.reuseIdentifier)
        collectionView.frame = window.bounds
        view.addSubview(collectionView)
        window.rootViewController = self
        window.isHidden = false
        window.layoutIfNeeded()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int { count }

    func collectionView(
        _ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath
    ) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(
            withReuseIdentifier: EpisodeCardCell.reuseIdentifier, for: indexPath
        ) as! EpisodeCardCell
        cell.configure(
            EpisodeCardContent(
                title: "Episode \(indexPath.item)", channelTitle: "Channel", rightText: "1:00",
                imageURL: nil, descriptionPlainText: "Plain description"
            ),
            actions: []
        )
        return cell
    }

    func cardCells() -> [EpisodeCardCell] {
        collectionView.visibleCells
            .compactMap { $0 as? EpisodeCardCell }
            .sorted { $0.frame.minY < $1.frame.minY }
    }

    func tearDown() {
        window.isHidden = true
        window.rootViewController = nil
    }
}

@MainActor
@Suite
struct CardMotionTests {

    private static func drawer(of cell: EpisodeCardCell) -> UIView? {
        var stack = cell.subviews
        while let view = stack.popLast() {
            if view is CapsuleView { return view }
            stack.append(contentsOf: view.subviews)
        }
        return nil
    }

    /// Animations on the view's layer that would move or resize it.
    private static func frameAnimationKeys(of view: UIView) -> [String] {
        (view.layer.animationKeys() ?? []).filter { key in
            ["position", "bounds", "transform"].contains { key.localizedCaseInsensitiveContains($0) }
        }
    }

    @Test("entrance parks the cards at the start pose, then rests them at identity")
    func entranceEndsAtRest() async throws {
        let host = CardListHost(count: 6)
        defer { host.tearDown() }
        host.collectionView.reloadData()
        CardEntranceAnimator.play(in: host.collectionView, reduceMotion: false)

        let cells = host.cardCells()
        try #require(cells.count >= 3)
        // Every card is animating (rise + fade) the moment `play` returns —
        // the model values are already final, so nothing can stay offset.
        for cell in cells {
            let keys = cell.contentView.layer.animationKeys() ?? []
            #expect(!keys.isEmpty, "card has no entrance animation")
        }
        try await Task.sleep(for: .milliseconds(1200))
        for cell in cells {
            #expect(cell.contentView.alpha == 1)
            #expect(cell.contentView.transform == .identity)
            #expect(cell.contentView.layer.animationKeys() == nil, "entrance animation never finished")
        }
    }

    @Test("reduce-motion entrance fades only")
    func reducedEntranceDoesNotTranslate() async throws {
        let host = CardListHost(count: 4)
        defer { host.tearDown() }
        host.collectionView.reloadData()
        CardEntranceAnimator.play(in: host.collectionView, reduceMotion: true)
        for cell in host.cardCells() {
            #expect(cell.contentView.transform == .identity)
            let keys = cell.contentView.layer.animationKeys() ?? []
            #expect(!keys.contains { $0.localizedCaseInsensitiveContains("transform")
                || $0.localizedCaseInsensitiveContains("position") }, "reduce motion moved a card: \(keys)")
        }
        try await Task.sleep(for: .milliseconds(800))
        for cell in host.cardCells() {
            #expect(cell.contentView.alpha == 1)
        }
    }

    @Test("a reused cell never keeps an entrance pose")
    func reuseResetsEntrancePose() {
        let cell = EpisodeCardCell(frame: CGRect(x: 0, y: 0, width: 354, height: 112))
        cell.contentView.alpha = 0
        cell.contentView.transform = CGAffineTransform(translationX: 0, y: 12)
        cell.prepareForReuse()
        #expect(cell.contentView.alpha == 1)
        #expect(cell.contentView.transform == .identity)
    }

    @Test("expand then collapse leaves the strip hidden, closed and ready for the next reveal")
    func stripStateStaysConsistent() async throws {
        let host = CardListHost(count: 4)
        defer { host.tearDown() }
        host.collectionView.reloadData()
        host.collectionView.layoutIfNeeded()
        let path = IndexPath(item: 1, section: 0)
        let cell = try #require(host.collectionView.cellForItem(at: path) as? EpisodeCardCell)
        let closedHeight = cell.bounds.height
        let coordinator = CardExpandCoordinator()
        // The card plate is the stack's first row; only the strip may move.
        let plate = try #require((cell.contentView.subviews.first as? UIStackView)?.arrangedSubviews.first)
        let plateFrame = plate.frame

        coordinator.toggle(at: path)
        CardExpandAnimator.refresh(expandedPath: coordinator.expandedIndexPath, in: host.collectionView)
        #expect(cell.isStripExpanded)
        // The strip target lands before the item resizes: the plate must
        // already sit at its own frame and carry no frame animation (the
        // headless host has no presentation layer to sample mid-flight).
        #expect(plate.frame == plateFrame, "card plate resized or moved when the strip opened")
        #expect(Self.frameAnimationKeys(of: plate).isEmpty, "card plate animated when the strip opened")
        let drawer = try #require(Self.drawer(of: cell))
        // The reveal's model values are final at once.
        #expect(drawer.alpha == 1 && drawer.transform == .identity)
        try await Task.sleep(for: .milliseconds(700))
        #expect(cell.bounds.height - closedHeight == EpisodeCardCell.stripHeight, "item did not grow by the strip")

        coordinator.toggle(at: path)
        CardExpandAnimator.refresh(expandedPath: coordinator.expandedIndexPath, in: host.collectionView)
        try await Task.sleep(for: .milliseconds(Int(Motion.stripFadeOut * 1000) + 60))
        #expect(plate.frame == plateFrame, "card plate resized or moved when the strip closed")
        #expect(Self.frameAnimationKeys(of: plate).isEmpty, "card plate animated when the strip closed")
        try await Task.sleep(for: .milliseconds(700))
        #expect(!cell.isStripExpanded)
        #expect(cell.bounds.height == closedHeight, "item did not close with the strip")
        #expect(drawer.alpha == 1 && drawer.transform == .identity, "drawer not reset for the next reveal")
    }

    @Test("a collapse fade interrupted by a new toggle ends open and fully visible")
    func interruptedCollapseEndsConsistent() async throws {
        let host = CardListHost(count: 4)
        defer { host.tearDown() }
        host.collectionView.reloadData()
        host.collectionView.layoutIfNeeded()
        let path = IndexPath(item: 1, section: 0)
        let cell = try #require(host.collectionView.cellForItem(at: path) as? EpisodeCardCell)
        let closedHeight = cell.bounds.height
        let drawer = try #require(Self.drawer(of: cell))
        let coordinator = CardExpandCoordinator()

        coordinator.toggle(at: path)
        CardExpandAnimator.refresh(expandedPath: coordinator.expandedIndexPath, in: host.collectionView)
        try await Task.sleep(for: .milliseconds(700))

        // Collapse starts its fade; a second toggle lands before it ends.
        coordinator.toggle(at: path)
        CardExpandAnimator.refresh(expandedPath: coordinator.expandedIndexPath, in: host.collectionView)
        try await Task.sleep(for: .milliseconds(40))
        coordinator.toggle(at: path)
        CardExpandAnimator.refresh(expandedPath: coordinator.expandedIndexPath, in: host.collectionView)
        try await Task.sleep(for: .milliseconds(700))

        #expect(cell.isStripExpanded)
        #expect(drawer.alpha == 1 && drawer.transform == .identity, "strip left half-faded")
        #expect(cell.bounds.height - closedHeight == EpisodeCardCell.stripHeight)
    }
}
