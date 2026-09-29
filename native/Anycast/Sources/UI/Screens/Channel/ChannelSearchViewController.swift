import UIKit
import AnycastKit

/// The in-channel search sheet (lib/pages/channel.dart:750-895, 03 §1.3
/// row 8): a nested expand sheet over the Channel sheet listing the
/// channel's episodes filtered by the submitted text (`contains` over
/// titles, in-memory — channel.dart:781-785). The Dart page has NO search
/// field of its own — the Channel page's field owns the query — and it DOES
/// host `PlayerBar(bottomSafe: true)` (channel.dart:767).
@MainActor
final class ChannelSearchViewController: UIViewController {

    private let context: UIContext
    private let searchText: String
    private var viewModel: ChannelViewModel?

    private let collectionView: UICollectionView
    private let playerBar: PlayerBarView
    private let playerBarHeight: NSLayoutConstraint
    private let grabber = SheetGrabberView()
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
        self.searchText = ""
        (collectionView, playerBar, playerBarHeight) = Self.makeCoreViews(context: context)
        super.init(nibName: nil, bundle: nil)
    }

    init(context: UIContext, rssFeedURL: String, searchText: String) {
        self.context = context
        self.searchText = searchText
        (collectionView, playerBar, playerBarHeight) = Self.makeCoreViews(context: context)
        configuredRSSFeedURL = rssFeedURL
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    private var configuredRSSFeedURL: String?

    /// Present factory (channel.dart:682-690 — the nested sheet on submit).
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

        let playerBar = context.makePlayerBar()
        playerBar.translatesAutoresizingMaskIntoConstraints = false
        let height = playerBar.heightAnchor.constraint(equalToConstant: 58)
        return (collectionView, playerBar, height)
    }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        Theme.installDarkBase(on: view)
        // Custom grabber below; the header band taps to close.
        sheetPresentationController?.prefersGrabberVisible = false

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
    }

    private func buildViewHierarchy() {
        grabber.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(grabber)

        // Grabber-band tap closes (05 §6.3 A2 header-tap adaptation, applied
        // to this nested sheet like SearchPage).
        let headerTap = UITapGestureRecognizer(target: self, action: #selector(closeTapped))
        headerTap.delegate = self
        view.addGestureRecognizer(headerTap)

        noResultsLabel.text = "No results"
        noResultsLabel.font = UIFontMetrics(forTextStyle: .title3).scaledFont(
            for: .systemFont(ofSize: 22, weight: .semibold)
        )
        noResultsLabel.adjustsFontForContentSizeCategory = true
        noResultsLabel.textColor = Theme.primaryLightMax
        noResultsLabel.isHidden = true
        noResultsLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(noResultsLabel)

        view.addSubview(collectionView)
        view.addSubview(playerBar)

        NSLayoutConstraint.activate([
            grabber.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            grabber.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            grabber.widthAnchor.constraint(equalToConstant: 42),
            grabber.heightAnchor.constraint(equalToConstant: 6),

            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            collectionView.topAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 18
            ),
            collectionView.bottomAnchor.constraint(equalTo: playerBar.topAnchor),

            playerBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            playerBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            playerBar.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            playerBarHeight,

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
        return ChannelSearchFilter.apply(searchText, to: viewModel.showEpisodes)
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

    @objc private func closeTapped() {
        dismiss(animated: true)
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

/// Only the grabber band acts as the close affordance (Detail pattern).
extension ChannelSearchViewController: UIGestureRecognizerDelegate {
    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldReceive touch: UITouch
    ) -> Bool {
        touch.location(in: view).y <= view.safeAreaInsets.top + 20
    }
}
