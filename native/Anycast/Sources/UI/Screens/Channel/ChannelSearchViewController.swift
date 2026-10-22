import UIKit
import AnycastKit

/// The in-channel search sheet (lib/pages/channel.dart:750-895, 03 §1.3
/// row 8): a nested expand sheet over the Channel sheet listing the
/// channel's episodes filtered live by its own search field (`contains` over
/// titles, in-memory — channel.dart:781-785). It hosts
/// `PlayerBar(bottomSafe: true)` (channel.dart:767).
@MainActor
final class ChannelSearchViewController: UIViewController {

    private let context: UIContext
    private var query: String
    private let searchField = UITextField()
    private var viewModel: ChannelViewModel?

    private let collectionView: UICollectionView
    private let playerBar: PlayerBarView
    private let playerBarHeight: NSLayoutConstraint
    private let noResultsLabel = UILabel()

    private let expandCoordinator = CardExpandCoordinator()
    private var binder: ChannelEpisodeListBinder?
    private let htmlRenderer = HTMLContentRenderer()

    private let modelObservation = ObservationLoop()
    private let playbackObservation = ObservationLoop()
    private var lastFilteredSignature: [String?] = []

    // MARK: - Construction (presenters keep the `init(context:)` name)

    init(context: UIContext) {
        self.context = context
        self.query = ""
        (collectionView, playerBar, playerBarHeight) = Self.makeCoreViews(context: context)
        super.init(nibName: nil, bundle: nil)
    }

    init(context: UIContext, rssFeedURL: String, searchText: String) {
        self.context = context
        self.query = searchText
        (collectionView, playerBar, playerBarHeight) = Self.makeCoreViews(context: context)
        configuredRSSFeedURL = rssFeedURL
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    private var configuredRSSFeedURL: String?

    /// Present factory (channel.dart:682-690 — the nested sheet).
    static func present(
        from presenter: UIViewController,
        context: UIContext,
        rssFeedURL: String,
        searchText: String
    ) {
        let controller = ChannelSearchViewController(
            context: context, rssFeedURL: rssFeedURL, searchText: searchText
        )
        AppSheets.presentExpand(controller, from: presenter)
    }

    private static func makeCoreViews(context: UIContext) -> (UICollectionView, PlayerBarView, NSLayoutConstraint) {
        let layout = UICollectionViewCompositionalLayout { _, _ in
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
            section.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 16, bottom: 88, trailing: 16)
            section.interGroupSpacing = EpisodeCardCell.spacing
            return section
        }
        let collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        collectionView.backgroundColor = .clear
        collectionView.contentInsetAdjustmentBehavior = .never
        collectionView.keyboardDismissMode = .interactive
        collectionView.translatesAutoresizingMaskIntoConstraints = false

        let playerBar = context.makePlayerBar(style: .capsule)
        playerBar.translatesAutoresizingMaskIntoConstraints = false
        let height = playerBar.heightAnchor.constraint(equalToConstant: 58)
        return (collectionView, playerBar, height)
    }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        Theme.installPageBase(on: view)
        sheetPresentationController?.prefersGrabberVisible = true

        buildViewHierarchy()
        resolveViewModel()

        modelObservation.track(
            read: { [weak self] in
                guard let self, let viewModel = self.viewModel else { return }
                _ = viewModel.channel
                _ = viewModel.episodes
                _ = viewModel.isLoading
                _ = viewModel.isReversed
            },
            onChange: { [weak self] in self?.render() }
        )
        playbackObservation.track(
            read: { [weak self] in
                guard let self else { return }
                _ = self.context.playback.currentEpisode
            },
            onChange: { [weak self] in self?.renderPlayerBar() }
        )
        // ObservationLoop never fires for an unchanged read: a cached
        // (K34) view model with no subsequent mutation would leave the
        // first frame unrendered — no "No results" label and a stale
        // player bar. Draw once here; the loops keep it live afterwards.
        render()
        renderPlayerBar()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        binder?.refreshPlaylistMembership()
        // Opened without a query: go straight to typing.
        if query.isEmpty { searchField.becomeFirstResponder() }
    }

    private func buildViewHierarchy() {
        // clearButtonMode must be set first: the style only installs the
        // right spacer when it is .never.
        searchField.clearButtonMode = .whileEditing
        searchField.applyAnycastStyle(placeholder: "Search episodes", icon: AppIcons.search)
        // A capsule like the Search tab's field (height Spacing.xxl).
        searchField.layer.cornerRadius = Spacing.xxl / 2
        searchField.returnKeyType = .search
        searchField.autocorrectionType = .no
        searchField.text = query
        searchField.accessibilityLabel = "Search episodes"
        searchField.translatesAutoresizingMaskIntoConstraints = false
        searchField.addTarget(self, action: #selector(queryChanged), for: .editingChanged)
        searchField.addAction(
            UIAction { [weak self] _ in self?.searchField.resignFirstResponder() },
            for: .primaryActionTriggered
        )
        view.addSubview(searchField)

        noResultsLabel.text = "No results"
        noResultsLabel.font = TypographyV2.emphasis.font()
        noResultsLabel.adjustsFontForContentSizeCategory = true
        noResultsLabel.textColor = Theme.onSurface
        noResultsLabel.isHidden = true
        noResultsLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(noResultsLabel)

        view.addSubview(collectionView)
        view.addSubview(playerBar)

        // Scrim behind the capsule so rows are not hard-cut by it (G-7).
        let bottomFade = ScrollEdgeFade(edge: .bottom)
        view.insertSubview(bottomFade, belowSubview: playerBar)

        NSLayoutConstraint.activate([
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            collectionView.topAnchor.constraint(equalTo: searchField.bottomAnchor, constant: Spacing.md),
            // Runs under the floating capsule; the section's 88 pt bottom
            // inset (plus the safe-area content inset) clears it.
            collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            // Below the system grabber.
            searchField.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 20),
            searchField.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: Spacing.pageH),
            searchField.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -Spacing.pageH),
            searchField.heightAnchor.constraint(equalToConstant: Spacing.xxl),

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

            noResultsLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            noResultsLabel.centerYAnchor.constraint(
                equalTo: collectionView.centerYAnchor, constant: 60
            ),
        ])

        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.register(EpisodeCardCell.self, forCellWithReuseIdentifier: EpisodeCardCell.reuseIdentifier)
    }

    /// Reuses the Channel view model from the session store (K34) — the
    /// Dart ChannelSearch reads the SAME ChannelController by tag.
    private func resolveViewModel() {
        guard let rssFeedURL = configuredRSSFeedURL ?? context.playback.currentEpisode?.rssFeedUrl,
              !rssFeedURL.isEmpty
        else { return }
        let entry = ChannelSessionStore.shared.entry(context: context, rssFeedURL: rssFeedURL, seed: nil)
        viewModel = entry.model
        let binder = ChannelEpisodeListBinder(
            owner: self,
            context: context,
            viewModel: entry.model,
            htmlRenderer: htmlRenderer,
            expandCoordinator: expandCoordinator
        )
        binder.onListContentChanged = { [weak self] in self?.refreshVisibleCards() }
        binder.collectionView = collectionView
        binder.startObservingPlayback()
        self.binder = binder
    }

    private var filteredEpisodes: [FeedEpisodeRow] {
        guard let viewModel else { return [] }
        return ChannelSearchFilter.apply(query, to: viewModel.showEpisodes)
    }

    /// The collection view ignores automatic inset adjustment, so the home
    /// indicator clearance is applied by hand.
    override func viewSafeAreaInsetsDidChange() {
        super.viewSafeAreaInsetsDidChange()
        collectionView.contentInset.bottom = view.safeAreaInsets.bottom
        collectionView.verticalScrollIndicatorInsets.bottom = view.safeAreaInsets.bottom
    }

    @objc private func queryChanged() {
        query = searchField.text ?? ""
        render()
    }

    // MARK: - Rendering

    private func render() {
        let filtered = filteredEpisodes
        let signature = filtered.map(\.enclosureUrl)
        if signature != lastFilteredSignature {
            lastFilteredSignature = signature
            UIView.performWithoutAnimation {
                collectionView.reloadData()
            }
            refreshVisibleCards()
        }
        noResultsLabel.isHidden = !filtered.isEmpty
        renderPlayerBar()
    }

    private func renderPlayerBar() {
        let visible = context.playback.currentEpisode != nil
        playerBar.isHidden = !visible
        playerBarHeight.constant = visible ? 58 : 0
    }

    private func refreshVisibleCards() {
        let filtered = filteredEpisodes
        for path in collectionView.indexPathsForVisibleItems {
            guard filtered.indices.contains(path.item),
                  let cell = collectionView.cellForItem(at: path) as? EpisodeCardCell
            else { continue }
            binder?.configure(cell: cell, episode: filtered[path.item], at: path, in: collectionView)
        }
    }
}

// MARK: - UICollectionViewDataSource / Delegate

extension ChannelSearchViewController: UICollectionViewDataSource, UICollectionViewDelegate {

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        filteredEpisodes.count
    }

    func collectionView(
        _ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath
    ) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(
            withReuseIdentifier: EpisodeCardCell.reuseIdentifier, for: indexPath
        ) as! EpisodeCardCell
        let filtered = filteredEpisodes
        if filtered.indices.contains(indexPath.item) {
            binder?.configure(cell: cell, episode: filtered[indexPath.item], at: indexPath, in: collectionView)
        }
        return cell
    }
}
