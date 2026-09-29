import UIKit
import AnycastKit

/// Tab 1 (lib/pages/playlists.dart:24-59): one page per playlist, switched
/// by horizontal swipe ONLY — the Dart Scaffold has a TabBarView but NO
/// TabBar (03 §10.1: usually the single default list; a visible tab strip
/// must not be invented here). Hosts the shared MyAppBar treatment
/// (gradient PLAYLIST title, gear, embedded search, 03 §2.2).
@MainActor
final class PlaylistsPageViewController: UIViewController {

    private let context: UIContext

    /// The swipe-only playlist paging (PlaylistPageModel is the pure half).
    private var pageModel = PlaylistPageModel(playlistIDs: [])
    private var pageController: UIPageViewController!
    private var pages: [Int64: PlaylistEpisodeListViewController] = [:]

    private let searchField = UITextField()
    private let cancelButton = UIButton(type: .system)

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
        buildHeader()
        buildPaging()
        Task { await reloadPlaylists() }
    }

    // MARK: - AppBar (03 §2.2 — the same structure every tab page hosts)

    private func buildHeader() {
        let title = GradientTextLabel()
        title.text = "PLAYLIST"

        let gear = UIButton(type: .custom)
        gear.setImage(AppIcons.settings, for: .normal)
        gear.tintColor = Theme.secondaryText
        gear.backgroundColor = Theme.cardBackground
        gear.layer.cornerRadius = 18
        gear.layer.cornerCurve = .continuous
        gear.isAccessibilityElement = true
        gear.accessibilityLabel = "Settings"
        gear.addAction(
            UIAction { [weak self] _ in self?.openSettings() },
            for: .touchUpInside
        )
        gear.widthAnchor.constraint(equalToConstant: 36).isActive = true
        gear.heightAnchor.constraint(equalToConstant: 36).isActive = true

        let titleRow = UIStackView(arrangedSubviews: [title, gear])
        titleRow.axis = .horizontal
        titleRow.alignment = .center
        titleRow.spacing = 12

        buildSearchRow()

        // The green Cancel sits BESIDE the field and collapses until text
        // exists (appbar.dart:120-143).
        cancelButton.isHidden = true
        let searchRow = UIStackView(arrangedSubviews: [searchField, cancelButton])
        searchRow.axis = .horizontal
        searchRow.alignment = .center
        searchRow.spacing = 12

        let header = UIStackView(arrangedSubviews: [titleRow, searchRow])
        header.axis = .vertical
        header.spacing = 12
        header.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(header)

        NSLayoutConstraint.activate([
            header.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            header.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            header.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
        ])
    }

    private func buildSearchRow() {
        let icon = UIImageView(image: AppIcons.search)
        icon.tintColor = Theme.secondaryText
        icon.contentMode = .center
        icon.translatesAutoresizingMaskIntoConstraints = false
        let iconBox = UIView()
        iconBox.translatesAutoresizingMaskIntoConstraints = false
        iconBox.addSubview(icon)
        NSLayoutConstraint.activate([
            iconBox.widthAnchor.constraint(equalToConstant: 44),
            iconBox.heightAnchor.constraint(equalToConstant: 24),

            icon.leadingAnchor.constraint(equalTo: iconBox.leadingAnchor, constant: 14),
            icon.centerYAnchor.constraint(equalTo: iconBox.centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 24),
            icon.heightAnchor.constraint(equalToConstant: 24),
        ])

        searchField.leftView = iconBox
        searchField.leftViewMode = .always
        searchField.placeholder = "Shows, episodes, and more"
        searchField.font = UIFontMetrics(forTextStyle: .body).scaledFont(
            for: .systemFont(ofSize: 16)
        )
        searchField.adjustsFontForContentSizeCategory = true
        searchField.textColor = Theme.primaryLightMax
        searchField.attributedPlaceholder = NSAttributedString(
            string: searchField.placeholder ?? "",
            attributes: [.foregroundColor: Theme.hintGray]
        )
        searchField.backgroundColor = Theme.cardBackground
        searchField.layer.cornerRadius = 12
        searchField.layer.cornerCurve = .continuous
        searchField.returnKeyType = .search
        searchField.autocorrectionType = .no
        searchField.autocapitalizationType = .none
        searchField.clearButtonMode = .whileEditing
        searchField.translatesAutoresizingMaskIntoConstraints = false
        // Floor, not a fixed height: the body font scales with Dynamic Type
        // and a required == 56 clips the text at accessibility sizes.
        searchField.heightAnchor.constraint(greaterThanOrEqualToConstant: 56).isActive = true
        searchField.addTarget(self, action: #selector(searchEditingChanged), for: .editingChanged)
        searchField.addTarget(self, action: #selector(searchSubmitted), for: .primaryActionTriggered)

        cancelButton.setTitle("Cancel", for: .normal)
        cancelButton.setTitleColor(Theme.primary, for: .normal)
        cancelButton.titleLabel?.font = Typography.mainText.font()
        cancelButton.addAction(
            UIAction { [weak self] _ in self?.cancelSearch() },
            for: .touchUpInside
        )
        cancelButton.translatesAutoresizingMaskIntoConstraints = false
        cancelButton.heightAnchor.constraint(equalToConstant: 24).isActive = true
    }

    @objc private func searchEditingChanged() {
        cancelButton.isHidden = (searchField.text ?? "").isEmpty
    }

    /// Non-empty submit opens the SearchPage sheet (appbar.dart:97-107).
    @objc private func searchSubmitted() {
        let text = (searchField.text ?? "").trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        searchField.resignFirstResponder()
        AppSheets.presentExpand(
            SearchPageViewController(context: context, searchText: text),
            from: topMostPresented()
        )
    }

    private func cancelSearch() {
        searchField.text = nil
        searchEditingChanged()
        searchField.resignFirstResponder()
    }

    private func openSettings() {
        AppSheets.presentExpand(SettingsViewController(context: context), from: topMostPresented())
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
                equalTo: searchField.bottomAnchor, constant: 12
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
