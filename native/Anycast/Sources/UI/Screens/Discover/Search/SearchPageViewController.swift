import UIKit
import AnycastKit

/// The Search tab (lib/pages/discover.dart:104-313, 03 §2.6), its own tab at
/// the trailing end of the tab bar since 2026-10-21. Header: the "Search"
/// display title with Settings, then the Channels/Episodes tab strip over a
/// swipeable two-page body. The field follows the platform: on iOS 26 it is
/// the search tab's system field, at the bottom with the tab bar; iOS 18
/// keeps the Anycast field under the header. An empty query is the entry
/// state (no strip or results); submitting runs a fresh search. Each tab's
/// search runs on its first display AND on every revisit (the Dart
/// TabBarView children carry no KeepAliveWrapper). The Episodes page renders
/// episode cards with play / add-to-playlist (UNGATED add — the SearchPage
/// correction) through a fresh CardExpandCoordinator per search. The mini
/// player comes from the shell, as on every tab.
@MainActor
final class SearchPageViewController: UIViewController, UISearchBarDelegate {

    static let fieldPlaceholder = "Shows, episodes, and more"

    private let context: UIContext
    private var viewModel: SearchPageViewModel

    private let header = HeaderView()
    /// iOS 18 field under the header.
    private let searchField = UITextField()
    /// iOS 26 search-tab field (installed on `navigationItem`).
    private let searchController = UISearchController(searchResultsController: nil)
    private let tabStrip: ChipTabBarView
    private var pagingContainer: DiscoverPagingContainer!
    private var channelsPage: SearchChannelsPageViewController
    private var episodesPage: SearchEpisodesPageViewController

    /// Guards double activation when a scrub is followed by its settle.
    private var lastActivatedTab = -1

    // MARK: - Construction

    init(context: UIContext) {
        self.context = context
        self.viewModel = SearchPageViewModel(searchText: "", api: context.api)

        tabStrip = ChipTabBarView(titles: ["Channels", "Episodes"])
        channelsPage = SearchChannelsPageViewController(context: context, viewModel: viewModel)
        episodesPage = SearchEpisodesPageViewController(context: context, viewModel: viewModel)

        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    /// The iOS 26 search tab hosts the system field through its navigation
    /// item, so the page sits in a navigation controller whose bar stays
    /// hidden; iOS 18 hosts the page directly.
    static func makeTabRoot(context: UIContext) -> UIViewController {
        let page = SearchPageViewController(context: context)
        guard #available(iOS 26.0, *) else { return page }
        let navigation = UINavigationController(rootViewController: page)
        navigation.setNavigationBarHidden(true, animated: false)
        return navigation
    }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        Theme.installPageBase(on: view)
        buildViewHierarchy()
        setResultsVisible(false)
    }

    private var hasQuery: Bool {
        !viewModel.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func setResultsVisible(_ visible: Bool) {
        tabStrip.isHidden = !visible
        pagingContainer.view.isHidden = !visible
    }

    /// Runs `text` as a new search: the view model's text is immutable, so
    /// both tabs get a fresh model and fresh pages.
    func search(_ text: String) {
        let query = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return }
        searchField.text = query
        searchController.searchBar.text = query
        searchField.resignFirstResponder()
        searchController.searchBar.resignFirstResponder()

        viewModel = SearchPageViewModel(searchText: query, api: context.api)
        channelsPage = SearchChannelsPageViewController(context: context, viewModel: viewModel)
        episodesPage = SearchEpisodesPageViewController(context: context, viewModel: viewModel)
        pagingContainer.replace(channelsPage, at: 0)
        pagingContainer.replace(episodesPage, at: 1)
        pagingContainer.select(0, animated: false)
        tabStrip.select(0, animated: false)
        setResultsVisible(true)
        lastActivatedTab = -1
        activateTabIfNeeded(0)
    }

    func searchBarSearchButtonClicked(_ searchBar: UISearchBar) {
        search(searchBar.text ?? "")
    }

    /// Tab activation with the settle guard: a tab ACTIVATION (first build
    /// or a revisit after leaving) re-runs that tab's search.
    private func activateTabIfNeeded(_ index: Int) {
        guard index != lastActivatedTab else { return }
        lastActivatedTab = index
        viewModel.activate(tab: index)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        episodesPage.refreshMembership()
        // iOS 26 activates the search tab's field itself.
        if #unavailable(iOS 26.0), !hasQuery {
            searchField.becomeFirstResponder()
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        // Leaving the tab takes the keyboard down with it.
        view.endEditing(true)
    }

    // MARK: - Build

    private func buildViewHierarchy() {
        header.configure(HeaderView.Configuration(title: "Search"))
        header.onSettings = { [weak self] in
            guard let self else { return }
            AppSheets.presentExpand(SettingsViewController(context: self.context), from: self.topMostPresented())
        }
        header.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(header)

        let stripTop: NSLayoutConstraint
        if #available(iOS 26.0, *) {
            searchController.obscuresBackgroundDuringPresentation = false
            searchController.searchBar.placeholder = Self.fieldPlaceholder
            searchController.searchBar.autocorrectionType = .no
            searchController.searchBar.autocapitalizationType = .none
            searchController.searchBar.delegate = self
            searchController.searchBar.searchTextField.accessibilityIdentifier = "search-page-field"
            navigationItem.searchController = searchController
            stripTop = tabStrip.topAnchor.constraint(equalTo: header.bottomAnchor, constant: Spacing.gap)
        } else {
            // clearButtonMode must be set before the style: the style
            // installs its right spacer only for `.never`.
            searchField.clearButtonMode = .whileEditing
            searchField.applyAnycastStyle(placeholder: Self.fieldPlaceholder, icon: AppIcons.search)
            searchField.returnKeyType = .search
            searchField.autocorrectionType = .no
            searchField.autocapitalizationType = .none
            searchField.accessibilityLabel = "Search"
            searchField.accessibilityIdentifier = "search-page-field"
            searchField.addAction(UIAction { [weak self] _ in
                self?.search(self?.searchField.text ?? "")
            }, for: .primaryActionTriggered)
            searchField.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(searchField)
            NSLayoutConstraint.activate([
                searchField.topAnchor.constraint(equalTo: header.bottomAnchor, constant: Spacing.gap),
                searchField.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: Spacing.pageH),
                searchField.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -Spacing.pageH),
                searchField.heightAnchor.constraint(equalToConstant: 48),
            ])
            stripTop = tabStrip.topAnchor.constraint(equalTo: searchField.bottomAnchor, constant: Spacing.gap)
        }

        tabStrip.translatesAutoresizingMaskIntoConstraints = false
        tabStrip.onSelect = { [weak self] index in
            guard let self else { return }
            self.pagingContainer.select(index, animated: true)
            self.activateTabIfNeeded(index)
        }
        view.addSubview(tabStrip)

        pagingContainer = DiscoverPagingContainer(pageCount: 2)
        pagingContainer.view.translatesAutoresizingMaskIntoConstraints = false
        addChild(pagingContainer)
        view.addSubview(pagingContainer.view)
        pagingContainer.didMove(toParent: self)
        pagingContainer.install(channelsPage, at: 0)
        pagingContainer.install(episodesPage, at: 1)
        pagingContainer.onSwipeSelect = { [weak self] index in
            guard let self else { return }
            self.tabStrip.select(index, animated: true)
            self.activateTabIfNeeded(index)
        }
        // A drag toward the Episodes tab builds it mid-gesture (PageView);
        // the settle guard prevents the double refetch.
        pagingContainer.onScrub = { [weak self] index in
            self?.activateTabIfNeeded(index)
        }

        NSLayoutConstraint.activate([
            header.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            header.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            header.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),

            stripTop,
            tabStrip.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tabStrip.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tabStrip.heightAnchor.constraint(equalToConstant: 44),

            pagingContainer.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            pagingContainer.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            pagingContainer.view.topAnchor.constraint(equalTo: tabStrip.bottomAnchor),
            pagingContainer.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }
}

// MARK: - Channels page (discover.dart:169-203)

/// PodcastCard results; tap opens the Channel sheet.
@MainActor
final class SearchChannelsPageViewController: UIViewController, UICollectionViewDataSource {

    private let context: UIContext
    private let viewModel: SearchPageViewModel

    private let collectionView: UICollectionView
    private let spinner = UIActivityIndicatorView(style: .large)
    private let statusLabel = UILabel()
    private let observation = ObservationLoop()
    private var lastChannelSignature: [String?] = []

    init(context: UIContext, viewModel: SearchPageViewModel) {
        self.context = context
        self.viewModel = viewModel
        // One grouped plate (discover.dart:187-195 insets: pageH 16 sides,
        // gap 12 top, pageBottomSafe 88 bottom).
        collectionView = UICollectionView(
            frame: .zero,
            collectionViewLayout: PodcastCardCell.makeGroupedLayout()
        )
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    /// The Episodes tab's stacked compact cards (discover.dart:222-228
    /// insets: pageH 16 sides, gap 12 top, pageBottomSafe 88 bottom).
    static func makeEpisodeListLayout(horizontalInset: CGFloat = 16) -> UICollectionViewCompositionalLayout {
        UICollectionViewCompositionalLayout { _, _ in
            let item = NSCollectionLayoutItem(
                layoutSize: NSCollectionLayoutSize(
                    widthDimension: .fractionalWidth(1),
                    heightDimension: .estimated(EpisodeCardCell.cardRowHeight)
                )
            )
            let group = NSCollectionLayoutGroup.horizontal(
                layoutSize: item.layoutSize, subitems: [item]
            )
            let section = NSCollectionLayoutSection(group: group)
            section.contentInsets = NSDirectionalEdgeInsets(
                top: 12, leading: horizontalInset, bottom: 88, trailing: horizontalInset
            )
            section.interGroupSpacing = EpisodeCardCell.spacing
            return section
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        Theme.installPageBase(on: view)
        build()
        observation.track(
            read: { [weak self] in
                guard let self else { return }
                _ = self.viewModel.channelsLoading
                _ = self.viewModel.channelsFailed
                _ = self.viewModel.channels
            },
            onChange: { [weak self] in self?.render() }
        )
        render()
    }

    private func build() {
        collectionView.backgroundColor = .clear
        collectionView.keyboardDismissMode = .interactive
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        collectionView.dataSource = self
        collectionView.register(
            PodcastCardCell.self, forCellWithReuseIdentifier: PodcastCardCell.reuseIdentifier
        )
        view.addSubview(collectionView)

        spinner.color = Theme.primary
        spinner.hidesWhenStopped = true
        spinner.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(spinner)

        statusLabel.font = TypographyV2.body.font()
        statusLabel.adjustsFontForContentSizeCategory = true
        statusLabel.textColor = Theme.onSurface
        statusLabel.textAlignment = .center
        statusLabel.isHidden = true
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(statusLabel)

        NSLayoutConstraint.activate([
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            collectionView.topAnchor.constraint(equalTo: view.topAnchor),
            collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            spinner.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            spinner.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            statusLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            statusLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor),
        ])
    }

    private func render() {
        switch viewModel.channelsPhase {
        case .loading:
            spinner.startAnimating()
            statusLabel.isHidden = true
        case .noResults:
            spinner.stopAnimating()
            statusLabel.text = "No results"
            statusLabel.isHidden = false
        case .networkError:
            spinner.stopAnimating()
            statusLabel.text = "Network Error"
            statusLabel.isHidden = false
        case .loaded:
            spinner.stopAnimating()
            statusLabel.isHidden = true
        }

        let signature = viewModel.channels.map(\.rssFeedUrl)
        if signature != lastChannelSignature {
            lastChannelSignature = signature
            UIView.performWithoutAnimation {
                collectionView.reloadData()
            }
        }
    }

    func collectionView(
        _ collectionView: UICollectionView, numberOfItemsInSection section: Int
    ) -> Int {
        viewModel.channels.count
    }

    func collectionView(
        _ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath
    ) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(
            withReuseIdentifier: PodcastCardCell.reuseIdentifier, for: indexPath
        ) as! PodcastCardCell
        if viewModel.channels.indices.contains(indexPath.item) {
            let channel = viewModel.channels[indexPath.item]
            cell.setPosition(
                isFirst: indexPath.item == 0, isLast: indexPath.item == viewModel.channels.count - 1
            )
            cell.configure(
                PodcastCardContent(
                    rssFeedURL: channel.rssFeedUrl ?? "",
                    title: channel.title ?? "",
                    description: channel.description ?? "",
                    imageURL: channel.imageUrl
                )
            )
            cell.onTap = { [weak self] content in
                guard let self else { return }
                let seed = SubscriptionRow(
                    rssFeedUrl: content.rssFeedURL,
                    title: content.title,
                    description: content.description,
                    imageUrl: content.imageURL
                )
                ChannelViewController.present(
                    from: self,
                    context: self.context,
                    rssFeedURL: content.rssFeedURL,
                    seed: seed
                )
            }
        }
        return cell
    }
}

// MARK: - Episodes page (discover.dart:204-293)

/// Episode cards with the play / unguarded add-to-playlist actions; one
/// fresh CardExpandCoordinator per SearchPage (Get.put per build).
@MainActor
final class SearchEpisodesPageViewController: UIViewController, UICollectionViewDataSource {

    private let context: UIContext
    private let viewModel: SearchPageViewModel

    private let collectionView: UICollectionView
    private let spinner = UIActivityIndicatorView(style: .large)
    private let statusLabel = UILabel()
    private let expandCoordinator = CardExpandCoordinator()
    /// Needs `self` as owner — created lazily (post-super.init).
    private lazy var binder = SearchEpisodeBinder(
        owner: self,
        context: context,
        htmlRenderer: HTMLContentRenderer(),
        expandCoordinator: expandCoordinator
    )
    private let playbackObservation = ObservationLoop()
    private let modelObservation = ObservationLoop()
    private var lastEpisodeSignature: [String?] = []
    /// Set when a new result list replaces the old one; the entrance plays
    /// once it can (`CardEntranceAnimator`). Pagination is not a new list.
    private var needsEntrance = false

    init(context: UIContext, viewModel: SearchPageViewModel) {
        self.context = context
        self.viewModel = viewModel
        collectionView = UICollectionView(
            frame: .zero,
            collectionViewLayout: SearchChannelsPageViewController.makeEpisodeListLayout()
        )
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func viewDidLoad() {
        super.viewDidLoad()
        Theme.installPageBase(on: view)
        build()

        modelObservation.track(
            read: { [weak self] in
                guard let self else { return }
                _ = self.viewModel.episodesLoading
                _ = self.viewModel.episodesFailed
                _ = self.viewModel.episodes
            },
            onChange: { [weak self] in self?.render() }
        )
        playbackObservation.track(
            read: { [weak self] in
                guard let self else { return }
                _ = self.context.playback.currentEpisode
                _ = self.context.playback.isPlaying
                _ = self.context.playback.isLoading
                _ = self.context.playback.queue.map(\.enclosureUrl)
            },
            onChange: { [weak self] in
                guard let self else { return }
                self.binder.refreshPlaylistMembership(episodes: self.viewModel.episodes)
            }
        )
        render()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        refreshMembership()
        playEntranceIfNeeded()
    }

    func refreshMembership() {
        binder.refreshPlaylistMembership(episodes: viewModel.episodes)
    }

    private func build() {
        collectionView.backgroundColor = .clear
        collectionView.keyboardDismissMode = .interactive
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        collectionView.dataSource = self
        binder.register(in: collectionView)
        view.addSubview(collectionView)

        spinner.color = Theme.primary
        spinner.hidesWhenStopped = true
        spinner.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(spinner)

        statusLabel.font = TypographyV2.body.font()
        statusLabel.adjustsFontForContentSizeCategory = true
        statusLabel.textColor = Theme.onSurface
        statusLabel.textAlignment = .center
        statusLabel.isHidden = true
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(statusLabel)

        NSLayoutConstraint.activate([
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            collectionView.topAnchor.constraint(equalTo: view.topAnchor),
            collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            spinner.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            spinner.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            statusLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            statusLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor),
        ])

        binder.onListContentChanged = { [weak self] in self?.refreshVisibleCards() }
    }

    private func render() {
        switch viewModel.episodesPhase {
        case .loading:
            spinner.startAnimating()
            statusLabel.isHidden = true
        case .noResults:
            spinner.stopAnimating()
            statusLabel.text = "No results"
            statusLabel.isHidden = false
        case .networkError:
            spinner.stopAnimating()
            statusLabel.text = "Network Error"
            statusLabel.isHidden = false
        case .loaded:
            spinner.stopAnimating()
            statusLabel.isHidden = true
        }

        let signature = viewModel.episodes.map(\.episode.enclosureUrl)
        if signature != lastEpisodeSignature {
            lastEpisodeSignature = signature
            UIView.performWithoutAnimation {
                collectionView.reloadData()
            }
            refreshMembership()
            needsEntrance = !signature.isEmpty
            playEntranceIfNeeded()
        }
    }

    /// Plays the entrance right after the new results were applied. A page
    /// that is not in a window yet has no layout to animate, so that case is
    /// retried from `viewDidAppear`.
    private func playEntranceIfNeeded() {
        guard needsEntrance, view.window != nil else { return }
        needsEntrance = false
        CardEntranceAnimator.play(in: collectionView)
    }

    private func refreshVisibleCards() {
        for path in collectionView.indexPathsForVisibleItems {
            guard viewModel.episodes.indices.contains(path.item),
                  let cell = collectionView.cellForItem(at: path) as? EpisodeCardCell
            else { continue }
            binder.configure(
                cell: cell,
                item: viewModel.episodes[path.item],
                at: path,
                in: collectionView
            )
        }
    }

    func collectionView(
        _ collectionView: UICollectionView, numberOfItemsInSection section: Int
    ) -> Int {
        viewModel.episodes.count
    }

    func collectionView(
        _ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath
    ) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(
            withReuseIdentifier: EpisodeCardCell.reuseIdentifier, for: indexPath
        ) as! EpisodeCardCell
        if viewModel.episodes.indices.contains(indexPath.item) {
            binder.configure(
                cell: cell,
                item: viewModel.episodes[indexPath.item],
                at: indexPath,
                in: collectionView
            )
        }
        return cell
    }
}
