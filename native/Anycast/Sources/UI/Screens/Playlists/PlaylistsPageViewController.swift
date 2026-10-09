import UIKit
import AnycastKit

/// The queue tab (lib/pages/playlists.dart:24-59, IA per 09 §3.4): one
/// page per playlist, switched by horizontal swipe ONLY — the Dart Scaffold
/// has a TabBarView but NO TabBar (03 §10.1: usually the single default
/// list; a visible tab strip must not be invented here). A shared page
/// header exposes search and settings. The full Playlist v2 reskin
/// (archive cover strip + queue cards, 1020:7525) is V3 batch-2 scope.
@MainActor
final class PlaylistsPageViewController: UIViewController {

    private let context: UIContext

    /// The swipe-only playlist paging (PlaylistPageModel is the pure half).
    private var pageModel = PlaylistPageModel(playlistIDs: [])
    private var pageController: UIPageViewController!
    private var pages: [Int64: PlaylistEpisodeListViewController] = [:]

    private let header = HeaderView()

    init(context: UIContext) {
        self.context = context
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        Theme.installPageBase(on: view)
        buildHeader()
        buildPaging()
        Task { await reloadPlaylists() }
    }

    // MARK: - v2 header (09 §3.8)

    private func buildHeader() {
        header.configure(HeaderView.Configuration(title: "Playlist"))
        header.onSettings = { [weak self] in
            guard let self else { return }
            AppSheets.presentExpand(SettingsViewController(context: self.context), from: self.topMostPresented())
        }
        header.onSearch = { [weak self] query in
            guard let self else { return }
            SearchPageViewController.present(
                from: self.topMostPresented(), context: self.context, searchText: query
            )
        }
        header.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(header)
        NSLayoutConstraint.activate([
            header.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            header.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            header.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
        ])
    }

    // MARK: - Swipe-only playlist paging (03 §10.1)

    private func buildPaging() {
        pageController = UIPageViewController(
            transitionStyle: .scroll, navigationOrientation: .horizontal
        )
        pageController.dataSource = self
        pageController.delegate = self
        pageController.view.backgroundColor = .clear
        pageController.view.translatesAutoresizingMaskIntoConstraints = false
        addChild(pageController)
        view.addSubview(pageController.view)
        pageController.didMove(toParent: self)

        NSLayoutConstraint.activate([
            pageController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            pageController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            pageController.view.topAnchor.constraint(
                equalTo: header.bottomAnchor, constant: Spacing.xs
            ),
            pageController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    private func reloadPlaylists() async {
        let playlists = (try? await context.database.playlistRepository().listPlaylists()) ?? []
        let ids = playlists.compactMap(\.id)
        let previous = pageModel
        pageModel = previous.replacingPlaylistIDs(ids)

        let stale = Set(pages.keys).subtracting(ids)
        for id in stale { pages[id] = nil }

        let currentID = pageModel.currentPlaylistID
        if let currentID {
            let page = page(for: currentID)
            let direction: UIPageViewController.NavigationDirection =
                pageModel.currentIndex >= previous.currentIndex ? .forward : .reverse
            pageController.setViewControllers([page], direction: direction, animated: false)
        }
        // An empty playlist table cannot occur with the schema's guaranteed
        // default row (K31 idempotent INSERT OR IGNORE at open).
    }

    private func page(for playlistID: Int64) -> PlaylistEpisodeListViewController {
        if let cached = pages[playlistID] { return cached }
        let page = PlaylistEpisodeListViewController(context: context, playlistId: playlistID)
        pages[playlistID] = page
        return page
    }
}

// MARK: - UIPageViewControllerDataSource (swipe-only tab switching)

extension PlaylistsPageViewController: UIPageViewControllerDataSource {

    func pageViewController(
        _ pageViewController: UIPageViewController,
        viewControllerBefore viewController: UIViewController
    ) -> UIViewController? {
        guard let list = viewController as? PlaylistEpisodeListViewController,
              let index = pageModel.playlistIDs.firstIndex(of: list.playlistId),
              let before = pageModel.page(before: index) else { return nil }
        pageModel.currentIndex = before
        return page(for: pageModel.playlistIDs[before])
    }

    func pageViewController(
        _ pageViewController: UIPageViewController,
        viewControllerAfter viewController: UIViewController
    ) -> UIViewController? {
        guard let list = viewController as? PlaylistEpisodeListViewController,
              let index = pageModel.playlistIDs.firstIndex(of: list.playlistId),
              let after = pageModel.page(after: index) else { return nil }
        pageModel.currentIndex = after
        return page(for: pageModel.playlistIDs[after])
    }
}

// MARK: - UIPageViewControllerDelegate (swipe settle)

extension PlaylistsPageViewController: UIPageViewControllerDelegate {

    /// The data-source query callbacks advance `currentIndex` the moment the
    /// PageViewController asks for the adjacent page — DURING the gesture —
    /// so a canceled swipe leaves the model desynced from the visible page.
    /// This settle (the UIPageViewController equivalent of
    /// DiscoverPagingContainer's end-decelerating/end-dragging sync) fires
    /// when the swipe settles, completed or bounced back, and re-reads the
    /// index off the page actually displayed.
    func pageViewController(
        _ pageViewController: UIPageViewController,
        didFinishAnimating finished: Bool,
        previousViewControllers: [UIViewController],
        transitionCompleted completed: Bool
    ) {
        guard let list = pageController.viewControllers?.first
                as? PlaylistEpisodeListViewController,
              let index = pageModel.playlistIDs.firstIndex(of: list.playlistId)
        else { return }
        pageModel.currentIndex = index
    }
}
