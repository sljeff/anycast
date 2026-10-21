import UIKit
import AnycastKit

/// The global search sheet (lib/pages/discover.dart:104-313, 03 §2.6),
/// presented from the header search button. Header: the system grabber, an
/// editable search field, and the Channels/Episodes tab strip over a
/// swipeable two-page body. An empty query opens the entry state (field
/// focused, no strip or results); submitting runs a fresh search. Each tab's
/// search runs on its first display AND on every revisit (the Dart
/// TabBarView children carry no KeepAliveWrapper). The Episodes page renders
/// episode cards with play / add-to-playlist (UNGATED add — the SearchPage
/// correction) through a fresh CardExpandCoordinator per sheet
/// (`Get.put(CardListController())` per SearchPage build). The bottom hosts
/// the player bar WITHOUT the bottom-safe wrapper (03 §2.6 verified
/// difference vs Channel pages) — pinned to the sheet's bottom edge.
@MainActor
final class SearchPageViewController: UIViewController {

    private let context: UIContext
    private var viewModel: SearchPageViewModel

    private let searchField = UITextField()
    private let tabStrip: ChipTabBarView
    private var pagingContainer: DiscoverPagingContainer!
    private var channelsPage: SearchChannelsPageViewController
    private var episodesPage: SearchEpisodesPageViewController

    private let playerBar: PlayerBarView
    private let playerBarHeight: NSLayoutConstraint
    private let playbackObservation = ObservationLoop()
    /// Guards double activation when a scrub is followed by its settle.
    private var lastActivatedTab = -1

    // MARK: - Construction

    init(context: UIContext, searchText: String) {
        self.context = context
        self.viewModel = SearchPageViewModel(searchText: searchText, api: context.api)

        tabStrip = ChipTabBarView(titles: ["Channels", "Episodes"])
        channelsPage = SearchChannelsPageViewController(context: context, viewModel: viewModel)
        episodesPage = SearchEpisodesPageViewController(context: context, viewModel: viewModel)

        playerBar = context.makePlayerBar(style: .capsule)
        playerBar.translatesAutoresizingMaskIntoConstraints = false
        playerBarHeight = playerBar.heightAnchor.constraint(equalToConstant: 58)

        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    /// Present factory (appbar.dart:101-106 — submit opens the sheet).
    static func present(
        from presenter: UIViewController,
        context: UIContext,
        searchText: String
    ) {
        AppSheets.presentExpand(
            SearchPageViewController(context: context, searchText: searchText),
            from: presenter
        )
    }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        Theme.installPageBase(on: view)
        sheetPresentationController?.prefersGrabberVisible = true

        buildViewHierarchy()

        playbackObservation.track(
            read: { [weak self] in
                guard let self else { return }
                _ = self.context.playback.currentEpisode
            },
            onChange: { [weak self] in self?.renderPlayerBar() }
        )
        renderPlayerBar()

        // The sheet opens on the Channels tab — its FutureBuilder is the
        // one that builds (discover.dart:169); the Episodes tab's search
        // fires on its first visit (no KeepAliveWrapper on these tabs).
        // An empty query stays in the entry state and searches nothing.
        if hasQuery {
            activateTabIfNeeded(0)
        } else {
            setResultsVisible(false)
        }
    }

    private var hasQuery: Bool {
        !viewModel.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func setResultsVisible(_ visible: Bool) {
        tabStrip.isHidden = !visible
        pagingContainer.view.isHidden = !visible
    }

    /// Runs a new search: the view model's text is immutable, so both tabs
    /// get a fresh model and fresh pages.
    private func submitSearch() {
        let query = (searchField.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return }
        searchField.resignFirstResponder()

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
        if !hasQuery, tabStrip.isHidden {
            searchField.becomeFirstResponder()
        }
    }

    // MARK: - Build

    private func buildViewHierarchy() {
        // clearButtonMode must be set before the style: the style installs
        // its right spacer only for `.never`.
        searchField.clearButtonMode = .whileEditing
        searchField.applyAnycastStyle(placeholder: "Shows, episodes, and more", icon: AppIcons.search)
        searchField.text = viewModel.searchText
        searchField.returnKeyType = .search
        searchField.autocorrectionType = .no
        searchField.autocapitalizationType = .none
        searchField.accessibilityLabel = "Search"
        searchField.accessibilityIdentifier = "search-page-field"
        searchField.addAction(UIAction { [weak self] _ in self?.submitSearch() }, for: .primaryActionTriggered)
        searchField.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(searchField)

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

        // The bar floats as a capsule just above the home indicator, inset
        // by pageH sideways like the Channel pages; the lists run under it.
        view.addSubview(playerBar)

        // Scrim behind the capsule so rows are not hard-cut by it (G-7).
        let bottomFade = ScrollEdgeFade(edge: .bottom)
        view.insertSubview(bottomFade, belowSubview: playerBar)

        NSLayoutConstraint.activate([
            searchField.topAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 20
            ),
            searchField.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: Spacing.pageH),
            searchField.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -Spacing.pageH),
            searchField.heightAnchor.constraint(equalToConstant: 48),

            tabStrip.topAnchor.constraint(equalTo: searchField.bottomAnchor, constant: Spacing.gap),
            tabStrip.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tabStrip.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tabStrip.heightAnchor.constraint(equalToConstant: 44),

            pagingContainer.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            pagingContainer.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            pagingContainer.view.topAnchor.constraint(equalTo: tabStrip.bottomAnchor),
            pagingContainer.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            playerBar.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: Spacing.pageH),
            playerBar.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -Spacing.pageH),
            playerBar.bottomAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -Spacing.xs
            ),
            playerBarHeight,

            bottomFade.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            bottomFade.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            bottomFade.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            bottomFade.topAnchor.constraint(
                equalTo: playerBar.topAnchor, constant: -ScrollEdgeFade.fadeLength
            ),
        ])
    }

    /// PlayerBar without bottomSafe still shrinks away entirely when
    /// nothing plays (bottom_nav_bar.dart:86-88).
    private func renderPlayerBar() {
        let visible = context.playback.currentEpisode != nil
        playerBar.isHidden = !visible
        playerBarHeight.constant = visible ? 58 : 0
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
        collectionView = UICollectionView(
            frame: .zero,
            collectionViewLayout: Self.makeListLayout()
        )
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    /// ListView.separated insets (discover.dart:187-195 / 222-228):
    /// pageH 16 sides, gap 12 top, pageBottomSafe 88 bottom — identical for
    /// both tabs' lists.
    static func makeListLayout(horizontalInset: CGFloat = 16) -> UICollectionViewCompositionalLayout {
        UICollectionViewCompositionalLayout { _, _ in
            let item = NSCollectionLayoutItem(
                layoutSize: NSCollectionLayoutSize(
                    widthDimension: .fractionalWidth(1),
                    heightDimension: .estimated(PodcastCardCell.cardHeight)
                )
            )
            let group = NSCollectionLayoutGroup.horizontal(
                layoutSize: item.layoutSize, subitems: [item]
            )
            let section = NSCollectionLayoutSection(group: group)
            section.contentInsets = NSDirectionalEdgeInsets(
                top: 12, leading: horizontalInset, bottom: 88, trailing: horizontalInset
            )
            section.interGroupSpacing = PodcastCardCell.spacing
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

        statusLabel.font = TypographyV2.bodyLarge.font()
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
            collectionViewLayout: SearchChannelsPageViewController.makeListLayout()
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

        statusLabel.font = TypographyV2.bodyLarge.font()
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
