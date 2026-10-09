import UIKit
import AnycastKit

/// `PlaylistEpisodesList` (playlists.dart:61-238): one playlist's
/// drag-reorderable card list. The reorder is the project's highest-risk
/// gesture (03 §3.2 / 05 §6.3 P0):
/// - whole-card drag after a 150 ms long press, no drag handle — a custom
///   `UILongPressGestureRecognizer(minimumPressDuration: 0.15)` drives
///   `beginInteractiveMovementForItem` / `updateInteractiveMovement…` /
///   `endInteractiveMovement` (07 §6; UICollectionView has no
///   `installsStandardGestureForInteractiveMovement` switch, but the
///   custom gesture always recognizes first, so 150 ms is the effective
///   threshold);
/// - 1.1x lift: the moving cell carries a 1.1 scale transform
///   (proxyDecorator, 03 §4) — drag sessions raised through the
///   `UICollectionViewDragDelegate` additionally get a 1.1x custom preview;
/// - reorder transactions land in the diffable `reorderingHandlers`
///   (`didReorder`, never `moveItemAt`);
/// - drag start collapses any expanded strip; edge auto-scroll is system;
/// - index-0-involving moves pause and swap the player source to the
///   post-reorder head (states/playlist_episode.dart:93-122; the 100 ms
///   blocking sleep is not ported, 08 §11.4);
/// - persistence goes through `PlaylistRepository.insertOrUpdateByIndex`
///   with the K26-fixed move math (gesture-space target index).
@MainActor
final class PlaylistEpisodeListViewController: UIViewController {

    private let context: UIContext
    let playlistId: Int64

    private(set) var episodes: [PlaylistEpisodeRow] = []
    private var isLoading = true

    private var dataSource: UICollectionViewDiffableDataSource<Int, String>!
    private(set) var binder: PlaylistEpisodeListBinder!
    private let expandCoordinator = CardExpandCoordinator()
    private let queueObservation = ObservationLoop()

    private let collectionView = UICollectionView(frame: .zero, collectionViewLayout: UICollectionViewLayout())
    private let spinner = UIActivityIndicatorView(style: .medium)
    private let emptyState = UIView()
    private let emptyExploreButton = UIButton(type: .system)

    /// The 150 ms whole-card drag starter
    /// (MyReorderableDelayedDragStartListener, playlists.dart:127-129).
    private lazy var dragGesture: UILongPressGestureRecognizer = {
        let gesture = UILongPressGestureRecognizer(target: self, action: #selector(dragGestureFired(_:)))
        gesture.minimumPressDuration = 0.15
        return gesture
    }()

    init(context: UIContext, playlistId: Int64) {
        self.context = context
        self.playlistId = playlistId
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        Theme.installPageBase(on: view)
        binder = PlaylistEpisodeListBinder(
            owner: self, context: context, playlistId: playlistId, expandCoordinator: expandCoordinator
        )
        binder.episodeSource = self
        binder.onListContentChanged = { [weak self] in
            Task { await self?.reloadEpisodes() }
        }
        binder.reorderHandler = { [weak self] from, to in
            self?.performReorder(from: from, to: to)
        }

        buildCollectionView()
        buildEmptyState()
        buildSpinner()
        configureDataSource()

        binder.startObservingLiveState()
        observeQueueChanges()
        Task { await reloadEpisodes() }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        // Cross-screen mutations (adds from Channel/Feeds, K3 completions)
        // are picked up on appear — the repository is not observable.
        Task { await reloadEpisodes() }
    }

    // MARK: - Build

    private func buildCollectionView() {
        collectionView.backgroundColor = .clear
        // Default .automatic adjustment: the shell's floating mini player
        // avoidance arrives through additionalSafeAreaInsets — .never here
        // let the bar cover the last card.
        collectionView.keyboardDismissMode = .interactive
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        // 07 §6: the system reorder gesture has a fixed ~0.5 s hold; the
        // custom 150 ms gesture below begins interactive movement first,
        // so the effective whole-card drag threshold is 150 ms. The drag
        // delegate (1.1x preview) also serves any system-initiated drag.
        collectionView.dragInteractionEnabled = true
        collectionView.dragDelegate = binder
        collectionView.reorderingCadence = .immediate
        collectionView.addGestureRecognizer(dragGesture)
        view.addSubview(collectionView)
        NSLayoutConstraint.activate([
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            collectionView.topAnchor.constraint(equalTo: view.topAnchor),
            collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        binder.register(in: collectionView)
    }

    private func buildSpinner() {
        spinner.color = Theme.primary
        spinner.hidesWhenStopped = true
        spinner.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(spinner)
        NSLayoutConstraint.activate([
            spinner.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            spinner.centerYAnchor.constraint(equalTo: view.centerYAnchor),
        ])
    }

    /// AnycastEmptyState (playlists.dart:71-84): "All caught up? Explore new
    /// shows!" with the green Explore button jumping to the Discover tab.
    private func buildEmptyState() {
        emptyState.isHidden = true
        emptyState.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(emptyState)

        let iconCircle = UIView()
        iconCircle.backgroundColor = Theme.cardBackground
        iconCircle.layer.cornerRadius = 32
        iconCircle.translatesAutoresizingMaskIntoConstraints = false
        let icon = UIImageView(image: UIImage(systemName: "music.note.list"))
        icon.tintColor = Theme.primary
        icon.contentMode = .scaleAspectFit
        icon.translatesAutoresizingMaskIntoConstraints = false
        iconCircle.addSubview(icon)

        let titleLabel = UILabel()
        titleLabel.text = "All caught up?"
        titleLabel.font = Typography.secondaryTitle.font()
        titleLabel.textColor = Theme.primaryLightMax
        titleLabel.textAlignment = .center
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.numberOfLines = 0

        let messageLabel = UILabel()
        messageLabel.text = "Explore new shows!"
        messageLabel.font = Typography.defaultText.font()
        messageLabel.textColor = Theme.secondaryText
        messageLabel.textAlignment = .center
        messageLabel.adjustsFontForContentSizeCategory = true
        messageLabel.numberOfLines = 0

        var exploreConfiguration = UIButton.Configuration.filled()
        exploreConfiguration.image = AppIcons.explore
        exploreConfiguration.imagePadding = 8
        exploreConfiguration.baseBackgroundColor = Theme.brandGreen
        exploreConfiguration.baseForegroundColor = .white
        exploreConfiguration.attributedTitle = AttributedString(
            "Explore", attributes: AttributeContainer([
                .font: Typography.mainText.font(),
            ])
        )
        exploreConfiguration.cornerStyle = .capsule
        emptyExploreButton.configuration = exploreConfiguration
        emptyExploreButton.addTarget(self, action: #selector(exploreTapped), for: .touchUpInside)

        let stack = UIStackView(arrangedSubviews: [iconCircle, titleLabel, messageLabel, emptyExploreButton])
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 12
        stack.setCustomSpacing(24, after: messageLabel)
        stack.translatesAutoresizingMaskIntoConstraints = false
        emptyState.addSubview(stack)

        NSLayoutConstraint.activate([
            icon.widthAnchor.constraint(equalToConstant: 30),
            icon.heightAnchor.constraint(equalToConstant: 30),
            icon.centerXAnchor.constraint(equalTo: iconCircle.centerXAnchor),
            icon.centerYAnchor.constraint(equalTo: iconCircle.centerYAnchor),

            stack.leadingAnchor.constraint(greaterThanOrEqualTo: emptyState.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: emptyState.trailingAnchor, constant: -24),
            stack.centerYAnchor.constraint(equalTo: emptyState.centerYAnchor),

            emptyState.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            emptyState.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            emptyState.topAnchor.constraint(equalTo: view.topAnchor),
            emptyState.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    @objc private func exploreTapped() {
        // v2 09 §3.5: Discover retired — discovery lives behind the search
        // circle (was Get.find<HomeTabController>().onItemTapped(2)).
        AppSheets.presentForm(SearchEntryViewController(context: context), from: topMostPresented())
    }

    // MARK: - Layout (ReorderableListView padding: top 12 / bottom 64)

    private func makeLayout() -> UICollectionViewCompositionalLayout {
        UICollectionViewCompositionalLayout { _, _ in
            let item = NSCollectionLayoutItem(
                layoutSize: NSCollectionLayoutSize(
                    widthDimension: .fractionalWidth(1),
                    heightDimension: .estimated(EpisodeCardCell.cardRowHeight)
                )
            )
            item.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16)
            let group = NSCollectionLayoutGroup.horizontal(
                layoutSize: item.layoutSize, subitems: [item]
            )
            let section = NSCollectionLayoutSection(group: group)
            section.interGroupSpacing = EpisodeCardCell.spacing
            section.contentInsets = NSDirectionalEdgeInsets(top: 12, leading: 0, bottom: 64, trailing: 0)
            return section
        }
    }

    // MARK: - Data source

    private func configureDataSource() {
        collectionView.setCollectionViewLayout(makeLayout(), animated: false)
        let binder = self.binder!
        dataSource = UICollectionViewDiffableDataSource<Int, String>(
            collectionView: collectionView
        ) { [weak self] collectionView, indexPath, enclosureURL in
            guard let self,
                  let cell = collectionView.dequeueReusableCell(
                      withReuseIdentifier: EpisodeCardCell.reuseIdentifier, for: indexPath
                  ) as? EpisodeCardCell,
                  // O(1) lookup — the linear scan per cell made every full
                  // render O(n²) on long playlists.
                  let episode = self.episodeByURL[enclosureURL] else {
                return EpisodeCardCell()
            }
            binder.configure(cell: cell, episode: episode, at: indexPath, in: collectionView)
            return cell
        }
        // Route a: drag-driven reorder commits through the diffable
        // reorderingHandlers (never `moveItemAt`).
        dataSource.reorderingHandlers.canReorderItem = { _ in true }
        dataSource.reorderingHandlers.didReorder = { [weak self] _ in
            self?.commitSnapshotReorder()
        }
    }

    private func applySnapshot() {
        var snapshot = NSDiffableDataSourceSnapshot<Int, String>()
        snapshot.appendSections([0])
        snapshot.appendItems(episodes.compactMap(\.enclosureUrl))
        dataSource.apply(snapshot, animatingDifferences: false)
        renderLoadingState()
    }

    private func renderLoadingState() {
        spinner.isHidden = !isLoading
        if isLoading { spinner.startAnimating() } else { spinner.stopAnimating() }
        emptyState.isHidden = isLoading || !episodes.isEmpty
        collectionView.isHidden = isLoading || episodes.isEmpty
    }

    // MARK: - Loading

    /// Monotonic: an older overlapping DB read must never overwrite a newer
    /// reload's rows.
    private var reloadGeneration = 0

    /// Chained reorder persistence: consecutive drops run their write +
    /// playback + reload steps strictly in commit order.
    private var reorderChain: Task<Void, Never>?

    /// URL → row index for the cell provider (rebuilt whenever `episodes`
    /// is assigned as a whole — the only mutation pattern this screen uses).
    private var episodeByURL: [String: PlaylistEpisodeRow] = [:]

    private func rebuildEpisodeIndex() {
        episodeByURL = Dictionary(
            episodes.compactMap { row in row.enclosureUrl.map { ($0, row) } },
            uniquingKeysWith: { first, _ in first }
        )
    }

    func reloadEpisodes() async {
        reloadGeneration += 1
        let generation = reloadGeneration
        let rows = (try? await context.database.playlistRepository()
            .listEpisodes(playlistId: playlistId)) ?? []
        guard generation == reloadGeneration else { return }
        // A read landing mid-drag would reset the collection view to the
        // pre-reorder database order and silently discard the drop's
        // reorder; the drag's own commit applies and persists the new
        // order, so the reload's result is dropped instead.
        guard liftedCell == nil else { return }
        episodes = rows
        rebuildEpisodeIndex()
        isLoading = false
        applySnapshot()
        await refreshDiskCacheState()
    }

    /// CacheController.onInit port: seed the download indicator's disk state.
    /// The per-episode look-ups run concurrently (a TaskGroup) — `cachedFile`
    /// also refreshes the LRU `touched` timestamp, and parallel touches are
    /// fine — while the resulting set stays identical to the serial pass.
    private func refreshDiskCacheState() async {
        let cacheStore = context.cacheStore
        let urls = episodes.compactMap(\.enclosureUrl).filter { !$0.isEmpty }
        let cached = await withTaskGroup(of: String?.self) { group in
            for url in urls {
                group.addTask {
                    await cacheStore.cachedFile(for: url) != nil ? url : nil
                }
            }
            var result = Set<String>()
            for await hit in group {
                if let hit { result.insert(hit) }
            }
            return result
        }
        binder.refreshDiskCachedURLs(cached)
        binder.refreshVisibleCards()
    }

    private func observeQueueChanges() {
        // K3 completions and cross-screen mutations reshape the queue; the
        // DB read here is the resync.
        let playback = context.playback
        queueObservation.track(
            read: { _ = playback.queue.map(\.enclosureUrl) },
            onChange: { [weak self] in
                Task { await self?.reloadEpisodes() }
            }
        )
    }

    // MARK: - Drag gesture (150 ms whole-card drag, 03 §3.2)

    /// The cell being dragged (weak: the collection view owns it).
    private weak var liftedCell: UICollectionViewCell?

    @objc private func dragGestureFired(_ gesture: UILongPressGestureRecognizer) {
        switch gesture.state {
        case .began:
            guard !episodes.isEmpty else { return }
            let point = gesture.location(in: collectionView)
            guard let indexPath = collectionView.indexPathForItem(at: point),
                  indexPath.section == 0,
                  indexPath.item < episodes.count,
                  collectionView.beginInteractiveMovementForItem(at: indexPath) else { return }
            // Lift visual: the 1.1x proxyDecorator (03 §4) — the legacy
            // movement lift itself is not customizable, so the moving cell
            // carries the scale for the duration of the drag.
            let cell = collectionView.cellForItem(at: indexPath)
            UIView.animate(withDuration: 0.15, delay: 0, options: [.curveEaseInOut]) {
                cell?.transform = CGAffineTransform(scaleX: 1.1, y: 1.1)
            }
            liftedCell = cell
            // onReorderStart (playlists.dart:97-99): collapse any open
            // strip the moment the drag starts. The drag-delegate path
            // (itemsForBeginning) does the same for system-raised drags.
            expandCoordinator.close()
            binder.refreshExpandedState(in: collectionView)
        case .changed:
            let point = gesture.location(in: collectionView)
            collectionView.updateInteractiveMovementTargetPosition(point)
        case .ended:
            collectionView.endInteractiveMovement()
            unliftCell()
        case .cancelled, .failed:
            collectionView.cancelInteractiveMovement()
            unliftCell()
        default:
            break
        }
    }

    private func unliftCell() {
        let cell = liftedCell
        liftedCell = nil
        UIView.animate(withDuration: 0.15, delay: 0, options: [.curveEaseInOut]) {
            cell?.transform = .identity
        }
    }

    // MARK: - Reorder commit (states/playlist_episode.dart:93-122)

    /// Derives (from, to) from the data source's post-drop snapshot and
    /// applies the Dart move semantics.
    private func commitSnapshotReorder() {
        let after = dataSource.snapshot().itemIdentifiers
        let before = episodes.compactMap(\.enclosureUrl)
        guard let (from, to) = Self.movedIndex(before: before, after: after) else { return }
        performReorder(from: from, to: to)
    }

    /// Exactly one item is dragged in a single reorder; its before/after
    /// offsets are the move's (from, to) in final coordinates. Several items
    /// *shift* index, so a bare index-diff is ambiguous — only the dragged
    /// item's (from, to) reproduces the after list when re-applied to the
    /// before list; candidates that merely shifted are rejected.
    static func movedIndex(before: [String], after: [String]) -> (from: Int, to: Int)? {
        guard before.count == after.count else { return nil }
        for url in before {
            guard let from = before.firstIndex(of: url),
                  let to = after.firstIndex(of: url),
                  from != to else { continue }
            // A real single-item move replays to exactly the observed list.
            guard let outcome = PlaylistReorderLogic.moveOutcome(from: from, to: to, urls: before),
                  outcome.reorderedURLs == after else { continue }
            return (from, to)
        }
        return nil
    }

    /// The single reorder entry: a11y actions and the drop commit both land
    /// here, in VISIBLE-row coordinates (non-nil enclosure URLs — the
    /// snapshot's space). Legacy rows with a NULL enclosureUrl are not in
    /// that space but ARE in `episodes` and the database, so both the
    /// in-memory reorder and the repository write translate by identity
    /// into full-row coordinates first.
    func performReorder(from: Int, to: Int) {
        let visibleBefore = episodes.compactMap(\.enclosureUrl)
        guard let outcome = PlaylistReorderLogic.moveOutcome(from: from, to: to, urls: visibleBefore)
        else { return }
        let movedURL = visibleBefore[from]
        guard let arrayFrom = episodes.firstIndex(where: { $0.enclosureUrl == movedURL })
        else { return }
        // Visible to full-row coordinates: after the removal the dragged row
        // must sit right before its visible successor (or at the end).
        let finalIndex = outcome.finalIndex
        var arrayTo: Int
        if finalIndex + 1 < outcome.reorderedURLs.count,
           let successorIndex = episodes.firstIndex(where: {
               $0.enclosureUrl == outcome.reorderedURLs[finalIndex + 1]
           }) {
            arrayTo = successorIndex > arrayFrom ? successorIndex - 1 : successorIndex
        } else {
            arrayTo = episodes.count - 1
        }
        guard let reordered = PlaylistReorderLogic.reorderedRows(episodes, from: arrayFrom, to: arrayTo)
        else { return }

        episodes = reordered
        rebuildEpisodeIndex()
        applySnapshot()

        let movedRow = reordered[arrayTo]
        // Final → gesture space, full-row coordinates (the repository takes
        // the unadjusted gesture slot; it re-applies the adjustment).
        let repositoryIndex = arrayTo > arrayFrom ? arrayTo + 1 : arrayTo
        let steps = PlaylistReorderLogic.playbackSteps(
            swapsPlaybackSource: outcome.swapsPlaybackSource,
            newHeadEnclosureURL: outcome.newHeadEnclosureURL
        )
        let playlistId = self.playlistId
        let repository = context.database.playlistRepository()
        let playback = context.playback
        // Consecutive reorders must persist in the order they were dropped:
        // chained tasks keep the database's final order matching the last
        // visual state instead of racing two writes.
        let predecessor = reorderChain
        reorderChain = Task { [weak self] in
            await predecessor?.value
            try? await repository.insertOrUpdateByIndex(
                movedRow, playlistId: playlistId, index: repositoryIndex
            )
            // The Dart sequence: pause, (100 ms sleep — dropped, 08 §11.4),
            // setByEpisode on the post-reorder head.
            for step in steps {
                switch step {
                case .pausePlayback:
                    playback.pause()
                case .setSource:
                    if let head = reordered.first {
                        await playback.setByEpisode(head)
                    }
                }
            }
            if playback.currentPlaylistId == playlistId {
                await playback.reloadQueue()
            }
            await self?.reloadEpisodes()
        }
    }
}

// MARK: - PlaylistEpisodeDataSource (binder → row resolution)

extension PlaylistEpisodeListViewController: PlaylistEpisodeDataSource {

    func episode(at indexPath: IndexPath) -> PlaylistEpisodeRow? {
        guard indexPath.section == 0, episodes.indices.contains(indexPath.item) else { return nil }
        return episodes[indexPath.item]
    }

    func index(of episode: PlaylistEpisodeRow) -> IndexPath? {
        episodes.firstIndex { $0.enclosureUrl == episode.enclosureUrl }
            .map { IndexPath(item: $0, section: 0) }
    }

    var rowCount: Int { episodes.count }

    func visibleIndex(ofEnclosureURL url: String) -> Int? {
        episodes.compactMap(\.enclosureUrl).firstIndex(of: url)
    }

    var visibleCount: Int { episodes.compactMap(\.enclosureUrl).count }
}
