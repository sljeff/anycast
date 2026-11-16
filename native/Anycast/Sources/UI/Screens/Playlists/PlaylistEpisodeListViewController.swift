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
///   (proxyDecorator, 03 §4); system drag & drop is disabled — the 150 ms
///   interactive movement is the single reorder path (a system drag
///   session hijacked ≥ 0.5 s holds and dropped the reorder);
/// - reorder transactions land in the diffable `reorderingHandlers`
///   (`didReorder`, never `moveItemAt`);
/// - drag start closes the list action group; edge auto-scroll is system;
/// - index-0-involving moves pause and swap the player source to the
///   post-reorder head (states/playlist_episode.dart:93-122; the 100 ms
///   blocking sleep is not ported, 08 §11.4);
/// - persistence goes through `PlaylistRepository.insertOrUpdateByIndex`
///   with the K26-fixed move math (gesture-space target index).
@MainActor
final class PlaylistEpisodeListViewController: UIViewController, ScrollEdgePage {

    private let context: UIContext
    let playlistId: Int64

    private(set) var episodes: [PlaylistEpisodeRow] = []
    private var isLoading = true
    /// The first non-empty list rises in once per instance
    /// (`CardEntranceAnimator`); later reloads and reorders never replay it.
    private var didPlayEntrance = false
    /// Prototype: keep the first list at alpha 0 until its entrance pose is
    /// parked, so the final layout is not drawn for a frame and then hidden.
    private var holdingEntrance = false

    private var dataSource: UICollectionViewDiffableDataSource<Int, String>!
    private(set) var binder: PlaylistEpisodeListBinder!
    private(set) var actionController: ListActionController!

    #if DEBUG
    private(set) var snapshotApplyCount = 0
    private(set) var cellProviderCalls: [String: Int] = [:]
    #endif
    private let queueObservation = ObservationLoop()

    private let collectionView = ListActionCollectionView(frame: .zero, collectionViewLayout: UICollectionViewLayout())
    var edgeScrollView: UIScrollView { collectionView }
    private let spinner = UIActivityIndicatorView(style: .medium)
    private let emptyState = EmptyStateView()
    private let emptyExploreButton = UIButton(type: .system)
    /// Weak "Listening history" link under the empty state; shown only when
    /// History has rows.
    private let emptyHistoryLink = HistoryLinkButton(accessibilityIdentifier: "playlist-listening-history")
    /// Element kind of the list-end footer: the queue summary, with the
    /// pull-up orb beneath it.
    static let endFooterKind = "playlist-end-footer"
    /// The footer copy for the current list and speed; nil hides the line.
    /// Recomputed on list and speed changes only, never on a position tick.
    private(set) var footerText: PlaylistQueueSummary.Text?
    private let speedObservation = ObservationLoop()
    /// Pull-up-to-History state. `displayedPull` drives the orb;
    /// `draggedPull` is only written while a finger is dragging, so the
    /// release decision reads the pull the user actually let go at, not the
    /// spring-back that follows it.
    private var displayedPull: CGFloat = 0
    private var draggedPull: CGFloat = 0
    private var firedPullHaptic = false
    private var emptyTopConstraint: NSLayoutConstraint?
    private var spinnerCenterConstraint: NSLayoutConstraint?

    /// Height of the pinned chrome this list runs under (set by the host;
    /// 0 when nothing overlaps). It pushes the first row, the empty state
    /// and the spinner back below the chrome, so the resting layout is the
    /// one the list had when it started under the chrome.
    var topChromeInset: CGFloat = 0 {
        didSet { applyTopChromeInset(from: oldValue) }
    }

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
            owner: self, context: context, playlistId: playlistId
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
        configureActionController()

        binder.startObservingLiveState()
        observeQueueChanges()
        observeSpeed()
        Task { await reloadEpisodes() }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        playEntranceIfNeeded()
        // Cross-screen mutations (adds from Channel/Feeds, K3 completions)
        // are picked up on appear — the repository is not observable.
        Task { await reloadEpisodes() }
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        // The Undo capsule belongs to this list: leaving it commits.
        Task { await binder.commitPendingRemoval() }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        playEntranceIfNeeded()
        if holdingEntrance {
            // No cells to park; show the list instead of leaving it blank.
            holdingEntrance = false
            collectionView.alpha = 1
        }
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
        // so the effective whole-card drag threshold is 150 ms. System
        // drag & drop stays OFF: a drag session raised by the system's own
        // ~0.5 s lift recognizer raced the in-flight movement, cancelled
        // it, and floated a SQUARE full-cell preview (the rounded card is
        // only a subview of the wider item) whose drop had no handler —
        // the reorder silently died on any hold ≥ 0.5 s. The 150 ms
        // interactive movement is the single reorder path; its lift is the
        // real cell carrying the 1.1x transform.
        collectionView.dragInteractionEnabled = false
        collectionView.addGestureRecognizer(dragGesture)
        // The pull-up to History must work on a list shorter than the
        // viewport too, so the list always bounces.
        collectionView.alwaysBounceVertical = true
        collectionView.onContentOffsetChange = { [weak self] in self?.contentOffsetDidChange() }
        collectionView.panGestureRecognizer.addTarget(self, action: #selector(scrollPanChanged(_:)))
        view.addSubview(collectionView)
        NSLayoutConstraint.activate([
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            collectionView.topAnchor.constraint(equalTo: view.topAnchor),
            collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        binder.register(in: collectionView)
        collectionView.contentInset.top = topChromeInset
    }

    private func buildSpinner() {
        spinner.color = Theme.primary
        spinner.hidesWhenStopped = true
        spinner.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(spinner)
        let centerY = spinner.centerYAnchor.constraint(equalTo: view.centerYAnchor, constant: topChromeInset / 2)
        spinnerCenterConstraint = centerY
        NSLayoutConstraint.activate([
            spinner.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            centerY,
        ])
    }

    private func applyTopChromeInset(from previous: CGFloat) {
        guard isViewLoaded else { return }
        let wasAtTop = collectionView.contentOffset.y <= -collectionView.adjustedContentInset.top + 0.5
        collectionView.contentInset.top = topChromeInset
        if wasAtTop, previous != topChromeInset {
            collectionView.contentOffset.y = -collectionView.adjustedContentInset.top
        }
        emptyTopConstraint?.constant = topChromeInset
        spinnerCenterConstraint?.constant = topChromeInset / 2
    }

    /// "Nothing queued." The queue is filled from the Inbox, so the action
    /// goes there; with an empty Inbox it offers "Find a show" instead.
    private func buildEmptyState() {
        emptyState.isHidden = true
        emptyState.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(emptyState)

        emptyExploreButton.addPressFeedback(scale: Motion.pressScaleSubtle)
        emptyExploreButton.addTarget(self, action: #selector(emptyActionTapped), for: .touchUpInside)
        configureEmptyState(inboxIsEmpty: false)
        emptyHistoryLink.addAction(UIAction { [weak self] _ in self?.presentHistory() }, for: .touchUpInside)
        emptyHistoryLink.install(in: view)

        let top = emptyState.topAnchor.constraint(
            equalTo: view.safeAreaLayoutGuide.topAnchor, constant: topChromeInset
        )
        emptyTopConstraint = top
        NSLayoutConstraint.activate([
            emptyState.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            emptyState.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            top,
            emptyState.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
        ])
    }

    private var emptyActionFindsShow = false

    private func configureEmptyState(inboxIsEmpty: Bool) {
        emptyActionFindsShow = inboxIsEmpty
        emptyExploreButton.configuration = AnycastButton.configuration(
            .primary, title: inboxIsEmpty ? "Find a show" : "Go to Inbox"
        )
        emptyState.configure(EmptyStateView.Content(
            title: "Nothing queued.",
            message: "Add episodes from the Inbox to play next.",
            actions: [emptyExploreButton]
        ))
    }

    /// Re-reads whether the Inbox has anything, to pick the action.
    private func refreshEmptyAction() {
        let repository = context.database.feedRepository()
        Task { [weak self] in
            let count = (try? await repository.count()) ?? 1
            guard let self, self.emptyState.isHidden == false else { return }
            self.configureEmptyState(inboxIsEmpty: count == 0)
        }
    }

    private func presentHistory() {
        HistoryDialogViewController.present(from: self, context: context)
    }

    @objc private func emptyActionTapped() {
        // Inbox (tab 0) or Search (tab 3), closing this list first when it
        // is presented as a sheet.
        let tabs = context.tabs
        let index = emptyActionFindsShow ? 3 : 0
        if presentingViewController != nil {
            dismiss(animated: true) { tabs.select(index) }
        } else {
            tabs.select(index)
        }
    }

    // MARK: - Layout (ReorderableListView padding: top 12)

    private func makeLayout() -> UICollectionViewCompositionalLayout {
        UICollectionViewCompositionalLayout { _, _ in
            let item = NSCollectionLayoutItem(
                layoutSize: NSCollectionLayoutSize(
                    widthDimension: .fractionalWidth(1),
                    heightDimension: .estimated(EpisodeCardCell.playlistRowHeight)
                )
            )
            item.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16)
            let group = NSCollectionLayoutGroup.horizontal(
                layoutSize: item.layoutSize, subitems: [item]
            )
            let section = NSCollectionLayoutSection(group: group)
            section.interGroupSpacing = EpisodeCardCell.spacing
            // The end footer carries the room below the last card (its own top
            // padding, the summary line and the pull-up orb), so no section
            // inset is added under it.
            section.contentInsets = NSDirectionalEdgeInsets(top: 12, leading: 0, bottom: 0, trailing: 0)
            // The queue summary closes the list. A boundary item, not a
            // second section: the reorder gesture and the action controller
            // keep a one-section index space.
            let footer = NSCollectionLayoutBoundarySupplementaryItem(
                layoutSize: NSCollectionLayoutSize(
                    widthDimension: .fractionalWidth(1),
                    heightDimension: .estimated(PlaylistEndFooterView.minimumHeight)
                ),
                elementKind: Self.endFooterKind,
                alignment: .bottom
            )
            section.boundarySupplementaryItems = [footer]
            return section
        }
    }

    // MARK: - Data source

    private func configureDataSource() {
        collectionView.setCollectionViewLayout(makeLayout(), animated: false)
        collectionView.register(
            PlaylistEndFooterView.self,
            forSupplementaryViewOfKind: Self.endFooterKind,
            withReuseIdentifier: PlaylistEndFooterView.reuseIdentifier
        )
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
            #if DEBUG
            self.cellProviderCalls[enclosureURL, default: 0] += 1
            #endif
            binder.configure(cell: cell, episode: episode, at: indexPath, in: collectionView)
            self.actionController.reapplyGap(to: cell, id: enclosureURL)
            return cell
        }
        dataSource.supplementaryViewProvider = { [weak self] collectionView, kind, indexPath in
            let view = collectionView.dequeueReusableSupplementaryView(
                ofKind: kind, withReuseIdentifier: PlaylistEndFooterView.reuseIdentifier, for: indexPath
            )
            if let footer = view as? PlaylistEndFooterView, let self {
                footer.setText(self.footerText)
                footer.setPull(self.displayedPull, animated: false)
            }
            return view
        }
        // Route a: drag-driven reorder commits through the diffable
        // reorderingHandlers (never `moveItemAt`). The legacy interactive
        // movement (system drag & drop is disabled below) applies its
        // reordering transaction synchronously inside
        // `endInteractiveMovement`, so this handler runs UNDERNEATH the
        // data source's own snapshot apply — applying the reorder's
        // follow-up snapshot right here would nest applies and trip
        // UIKit's deadlock detector. Capture the drop's final order and
        // commit one main-actor hop later, after that apply finishes.
        dataSource.reorderingHandlers.canReorderItem = { _ in true }
        dataSource.reorderingHandlers.didReorder = { [weak self] transaction in
            let after = transaction.finalSnapshot.itemIdentifiers
            Task { @MainActor [weak self] in
                self?.commitSnapshotReorder(after: after)
            }
        }
    }

    private func configureActionController() {
        actionController = ListActionController(
            collectionView: collectionView,
            itemsProvider: { [weak self] id in
                guard let self, let episode = self.episodeByURL[id] else { return [] }
                return self.binder.groupItems(for: episode)
            },
            idAt: { [weak self] path in self?.dataSource.itemIdentifier(for: path) },
            indexPathFor: { [weak self] id in self?.dataSource.indexPath(for: id) },
            safeArea: { [weak self] in self?.actionSafeLines() ?? (0, 0) }
        )
        binder.actionController = actionController
        actionController.onGroupUpdate = { [weak self] in self?.binder.refreshGroup() }
        // PlaylistsPageViewController.focusScrollView only retargets edge
        // effects. Its HeaderView is fixed, with no offset-driven collapsed
        // title to defer through onMotionStateChange.
    }

    private func actionSafeLines() -> (top: CGFloat, bottom: CGFloat) {
        // The page starts under the status bar. topChromeInset is the pinned
        // HeaderView height + Spacing.xs; automatic adjustment adds safeArea.top.
        // Thus adjustedContentInset.top is the viewport-y line below BOTH.
        let top = collectionView.adjustedContentInset.top
        var bottom = collectionView.bounds.height - collectionView.safeAreaInsets.bottom
        // Frame-based on every plan (the mini player can come and go); a
        // constraint to the shell's guide cannot be activated while this
        // list is outside the shell's hierarchy (tests, page transitions).
        if let shell = tabBarController as? MainTabBarController,
           let line = shell.bottomChromeTopY(in: collectionView) {
            bottom = line - collectionView.bounds.minY
        }
        return (top, bottom - 52)
    }

    private var animatesSnapshot: Bool {
        !Motion.reduceMotion && didPlayEntrance && liftedCell == nil && pendingReorderCount == 0
    }

    private func applySnapshot(animatingDifferences: Bool) {
        var snapshot = NSDiffableDataSourceSnapshot<Int, String>()
        snapshot.appendSections([0])
        snapshot.appendItems(episodes.compactMap(\.enclosureUrl))
        let hold = !didPlayEntrance && !episodes.isEmpty
        if hold {
            collectionView.alpha = 0
            holdingEntrance = true
        }
        // The end footer remains in contentSize.
        // Only ListActionController extends contentInset.bottom for its floor.
        #if DEBUG
        snapshotApplyCount += 1
        #endif
        dataSource.apply(snapshot, animatingDifferences: animatingDifferences)
        // Every change of the queue (reload, reorder, hide) lands here.
        refreshFooterText()
        renderLoadingState()
        playEntranceIfNeeded()
    }

    /// Plays the entrance right after the list was applied. The first load
    /// can land before the view is in a window (no layout, nothing to
    /// animate), so that case is retried from `viewDidAppear`.
    private func playEntranceIfNeeded() {
        guard !didPlayEntrance, view.window != nil, !isLoading, !episodes.isEmpty else { return }
        guard collectionView.bounds.width > 0 else { return }
        collectionView.layoutIfNeeded()
        let cards = collectionView.visibleCells.filter { $0 is EpisodeCardCell }
        guard !cards.isEmpty else { return }
        didPlayEntrance = true
        holdingEntrance = false
        CardEntranceAnimator.play(in: collectionView)
        collectionView.alpha = 1
    }

    private func renderLoadingState() {
        spinner.isHidden = !isLoading
        if isLoading { spinner.startAnimating() } else { spinner.stopAnimating() }
        emptyState.isHidden = isLoading || !episodes.isEmpty
        if !emptyState.isHidden { refreshEmptyAction() }
        emptyHistoryLink.refresh(pageIsEmpty: !isLoading && episodes.isEmpty, database: context.database)
        collectionView.isHidden = isLoading || episodes.isEmpty
    }

    // MARK: - Loading

    /// Monotonic: an older overlapping DB read must never overwrite a newer
    /// reload's rows.
    private var reloadGeneration = 0

    /// Chained reorder persistence: consecutive drops run their write +
    /// playback + reload steps strictly in commit order.
    private var reorderChain: Task<Void, Never>?

    /// A queue-changing read landed mid-drag and was dropped
    /// (`reloadEpisodes`); the gesture's end replays it so completions and
    /// cross-screen removals cannot linger as ghost cards.
    private var needsReloadAfterDrag = false

    /// Reorder commits whose chain task has not finished (persist + resync).
    /// While any is in flight, `reloadEpisodes` drops its read: it would
    /// race the move write and land the PRE-move order after the drop's
    /// visual state (cards jumping back, then forward again when the
    /// chain's own tail reload lands). Includes the replayed mid-drag
    /// reload and queue-observation reloads triggered by the 2 s progress
    /// tick during a long drag.
    private var pendingReorderCount = 0

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
        let stored = (try? await context.database.playlistRepository()
            .listEpisodes(playlistId: playlistId)) ?? []
        // A removal waiting out its Undo window is still stored.
        let rows = PlaylistRemovalLogic.displayed(stored, excluding: binder.hiddenEpisodeURL)
        guard generation == reloadGeneration else { return }
        // A read landing mid-drag would reset the collection view to the
        // pre-reorder database order and silently discard the drop's
        // reorder; the drag's own commit applies and persists the new
        // order, so the reload's result is dropped instead.
        guard liftedCell == nil else {
            // A completion that cascaded a row away while the drag was in
            // flight leaves a ghost card when the user drops in place or
            // cancels — `movedIndex` never fires and nothing else resyncs.
            needsReloadAfterDrag = true
            return
        }
        // Same for an in-flight reorder commit: the chain task's tail
        // reload is the authoritative resync.
        guard pendingReorderCount == 0 else { return }
        // Captured after the awaits and guards, in the same main-actor turn
        // as the assignment — a reorder landing mid-read must not make the
        // reshape comparison run against a stale sequence.
        let previousURLs = episodes.compactMap(\.enclosureUrl)
        let nextURLs = rows.compactMap(\.enclosureUrl)
        let reshaped = nextURLs != previousURLs
        isLoading = false
        let assign = {
            self.episodes = rows
            self.rebuildEpisodeIndex()
            self.applySnapshot(animatingDifferences: false)
        }
        if reshaped, let selected = actionController.selectedID, !nextURLs.contains(selected),
           binder.consumeUserLeave(selected) {
            // The user's own Remove (eager path): the next card fills.
            actionController.performLeave(id: selected, apply: assign)
        } else if reshaped {
            actionController.itemsDidChange(apply: assign)
        } else {
            episodes = rows
            rebuildEpisodeIndex()
            applySnapshot(animatingDifferences: animatesSnapshot)
        }
        binder.refreshGroup()
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
            read: { _ = playback.queueEnclosureURLs },
            onChange: { [weak self] in
                Task { await self?.reloadEpisodes() }
            }
        )
    }

    // MARK: - Queue summary footer

    /// The footer view while it is on screen (it is a boundary supplementary
    /// of the one section, so it is a direct subview of the collection view).
    private var visibleFooter: PlaylistEndFooterView? {
        collectionView.subviews.lazy.compactMap { $0 as? PlaylistEndFooterView }.first
    }

    private func observeSpeed() {
        let playback = context.playback
        speedObservation.track(
            read: { _ = playback.speed },
            onChange: { [weak self] in self?.refreshFooterText() }
        )
    }

    /// Recomputes "X h Y m left · done around H:MM at N×". Called from the
    /// snapshot apply and the speed observation only — never per position
    /// tick; the playing episode reads its live position once, here.
    private func refreshFooterText() {
        let playback = context.playback
        let currentURL = playback.currentEpisode?.enclosureUrl
        let live = playback.positionData
        let rows = episodes.map { episode -> PlaylistQueueSummary.Row in
            if let url = episode.enclosureUrl, url == currentURL, live.durationMilliseconds > 0 {
                return PlaylistQueueSummary.Row(
                    durationMilliseconds: live.durationMilliseconds,
                    playedMilliseconds: live.positionMilliseconds
                )
            }
            return PlaylistQueueSummary.Row(
                durationMilliseconds: episode.duration, playedMilliseconds: episode.playedDuration
            )
        }
        let text = PlaylistQueueSummary.text(rows: rows, speed: Double(playback.speed), now: Date())
        guard text != footerText else { return }
        footerText = text
        guard let footer = visibleFooter else { return }
        let before = footer.bounds.height
        footer.setText(text)
        let fitting = footer.systemLayoutSizeFitting(
            CGSize(width: collectionView.bounds.width, height: UIView.layoutFittingCompressedSize.height),
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel
        ).height
        // The line wraps at large text sizes; only a real height change
        // asks the layout to measure the footer again.
        if abs(fitting - before) > 0.5 { collectionView.collectionViewLayout.invalidateLayout() }
    }

    // MARK: - Pull-up to History

    /// Measures the drag past the end against the real maximum offset (the
    /// adjusted inset carries the action group's bottom extension) and
    /// drives the orb. Only a finger drag counts: a fling's rubber-band and
    /// programmatic offsets never show the orb or fire the haptic.
    private func contentOffsetDidChange() {
        guard collectionView.isDragging, !episodes.isEmpty, liftedCell == nil else {
            setDisplayedPull(0, animated: true)
            return
        }
        let inset = collectionView.adjustedContentInset
        let progress = PlaylistHistoryPull.progress(overscroll: PlaylistHistoryPull.overscroll(
            offsetY: collectionView.contentOffset.y,
            contentHeight: collectionView.contentSize.height,
            viewportHeight: collectionView.bounds.height,
            adjustedInsetTop: inset.top,
            adjustedInsetBottom: inset.bottom
        ))
        draggedPull = progress
        if PlaylistHistoryPull.opensOnRelease(progress: progress) {
            if !firedPullHaptic {
                firedPullHaptic = true
                Haptics.tap()
            }
        } else {
            firedPullHaptic = false
        }
        setDisplayedPull(progress, animated: false)
    }

    private func setDisplayedPull(_ progress: CGFloat, animated: Bool) {
        guard progress != displayedPull else { return }
        displayedPull = progress
        visibleFooter?.setPull(progress, animated: animated)
    }

    /// The release decision: the pull the finger left at, not the spring-back.
    @objc private func scrollPanChanged(_ pan: UIPanGestureRecognizer) {
        switch pan.state {
        case .began:
            draggedPull = 0
            firedPullHaptic = false
        case .ended:
            let opens = PlaylistHistoryPull.opensOnRelease(progress: draggedPull)
            draggedPull = 0
            firedPullHaptic = false
            if opens, !episodes.isEmpty, presentedViewController == nil { presentHistory() }
        case .cancelled, .failed:
            draggedPull = 0
            firedPullHaptic = false
        default:
            break
        }
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
            actionController.close(animated: true)
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
        if needsReloadAfterDrag {
            needsReloadAfterDrag = false
            Task { await reloadEpisodes() }
        }
    }

    // MARK: - Reorder commit (states/playlist_episode.dart:93-122)

    /// Derives (from, to) from the drop's final snapshot order (captured
    /// in `didReorder`) and applies the Dart move semantics.
    private func commitSnapshotReorder(after: [String]) {
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

        // VoiceOver reaches this path without a drag-start callback.
        actionController.close(animated: false)
        episodes = reordered
        rebuildEpisodeIndex()
        applySnapshot(animatingDifferences: animatesSnapshot)

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
        pendingReorderCount += 1
        reorderChain = Task { [weak self] in
            await predecessor?.value
            // A pending removal commits before the move write: stored
            // indexes must match the (already filtered) displayed ones.
            await self?.binder.commitPendingRemoval()
            // Move-only, and atomic with its existence check: a completion
            // that cascaded this row away mid-drag must not be resurrected
            // by an INSERT branch with stale progress — drop the reorder
            // and resync from the database instead.
            let persisted = (try? await repository.moveExisting(
                byEnclosureURL: movedURL, playlistId: playlistId, index: repositoryIndex
            )) ?? false
            guard persisted, let self else {
                // Release the hold BEFORE the resync read, or the read
                // drops itself (the guard in reloadEpisodes).
                if let self {
                    self.pendingReorderCount -= 1
                    await self.reloadEpisodes()
                }
                return
            }
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
            // Release the hold BEFORE the resync read (see above).
            self.pendingReorderCount -= 1
            await self.reloadEpisodes()
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

    func hideEpisode(byEnclosureURL url: String) {
        guard episodes.contains(where: { $0.enclosureUrl == url }) else { return }
        actionController.performLeave(id: url) {
            episodes.removeAll { $0.enclosureUrl == url }
            rebuildEpisodeIndex()
            applySnapshot(animatingDifferences: false)
        }
    }

    func visibleIndex(ofEnclosureURL url: String) -> Int? {
        episodes.compactMap(\.enclosureUrl).firstIndex(of: url)
    }

    var visibleCount: Int { episodes.compactMap(\.enclosureUrl).count }
}

// MARK: - End footer (queue summary + pull-up orb)

/// Closes the Playlist list: "<b>2 h 14 m</b> left · done around 9:41 PM at
/// 1.5×", with the History orb beneath it. The orb is invisible at rest and
/// grows with the pull-up (`setPull`); the room it needs is part of the
/// footer, so the end of the list is comfortable whether or not it shows.
final class PlaylistEndFooterView: UICollectionReusableView {

    static let reuseIdentifier = "PlaylistEndFooterView"
    static let orbSide: CGFloat = 28
    /// 12 above the line, the 20 pt line, 8, the orb, 16 below.
    static let minimumHeight: CGFloat = 12 + 20 + 8 + orbSide + 16

    private static let emphasisStyle = TypographyV2.Style(
        size: 15, lineHeight: 20, weight: .semibold, color: Theme.onSurface, scalingTextStyle: .subheadline
    )

    private let label = UILabel()
    private let orb = PlaylistHistoryOrbView()
    private var text: PlaylistQueueSummary.Text?

    /// The footer line as plain text (tests, VoiceOver parity).
    var displayedText: String? { text?.plain }
    /// The orb's current look, for tests.
    var orbAlpha: CGFloat { orb.alpha }
    var orbScale: CGFloat { orb.transform.a }

    override init(frame: CGRect) {
        super.init(frame: frame)
        label.numberOfLines = 0
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        orb.translatesAutoresizingMaskIntoConstraints = false
        orb.isAccessibilityElement = false
        setPull(0, animated: false)
        addSubview(orb)
        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: topAnchor, constant: Spacing.gap),
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Spacing.pageH),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Spacing.pageH),
            label.heightAnchor.constraint(greaterThanOrEqualToConstant: 20),
            orb.topAnchor.constraint(equalTo: label.bottomAnchor, constant: Spacing.md),
            orb.centerXAnchor.constraint(equalTo: centerXAnchor),
            orb.widthAnchor.constraint(equalToConstant: Self.orbSide),
            orb.heightAnchor.constraint(equalToConstant: Self.orbSide),
            orb.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -16),
        ])
        registerForTraitChanges([UITraitPreferredContentSizeCategory.self]) { (view: PlaylistEndFooterView, _) in
            view.render()
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func setText(_ text: PlaylistQueueSummary.Text?) {
        self.text = text
        render()
    }

    private func render() {
        guard let text else {
            label.attributedText = nil
            return
        }
        let result = NSMutableAttributedString(
            string: text.emphasis, attributes: attributes(for: Self.emphasisStyle)
        )
        result.append(NSAttributedString(string: text.rest, attributes: attributes(for: TypographyV2.meta)))
        label.attributedText = result
    }

    private func attributes(for style: TypographyV2.Style) -> [NSAttributedString.Key: Any] {
        var attributes = style.attributes(traits: traitCollection)
        let paragraph = (attributes[.paragraphStyle] as? NSParagraphStyle)?.mutableCopy()
            as? NSMutableParagraphStyle ?? NSMutableParagraphStyle()
        paragraph.alignment = .center
        attributes[.paragraphStyle] = paragraph
        return attributes
    }

    /// 0…1 pull progress: the orb grows 0.4 → 1 while it fades in. Reduce
    /// Motion keeps it at full size and only fades.
    func setPull(_ progress: CGFloat, animated: Bool) {
        let clamped = min(max(progress, 0), 1)
        let apply = {
            self.orb.alpha = clamped
            let scale = Motion.reduceMotion ? 1 : 0.4 + 0.6 * clamped
            self.orb.transform = CGAffineTransform(scaleX: scale, y: scale)
        }
        if animated {
            UIView.animate(
                withDuration: Motion.quick, delay: 0,
                options: [.beginFromCurrentState, .curveEaseOut, .allowUserInteraction], animations: apply
            )
        } else {
            apply()
        }
    }
}

/// The 28 pt gold orb: a radial gradient lit from the upper left (soft gold
/// into the brand gold), the prototype's `.orb`. Its CGColors are frozen at
/// assignment, so they are re-resolved when the appearance changes.
private final class PlaylistHistoryOrbView: UIView {

    override class var layerClass: AnyClass { CAGradientLayer.self }
    private var gradient: CAGradientLayer { layer as! CAGradientLayer }

    override init(frame: CGRect) {
        super.init(frame: frame)
        gradient.type = .radial
        gradient.startPoint = CGPoint(x: 0.35, y: 0.30)
        gradient.endPoint = CGPoint(x: 1.0, y: 0.95)
        gradient.locations = [0, 0.7]
        gradient.cornerRadius = PlaylistEndFooterView.orbSide / 2
        gradient.masksToBounds = true
        updateColors()
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (view: PlaylistHistoryOrbView, _) in
            view.updateColors()
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    private func updateColors() {
        gradient.colors = [
            AnycastColor.goldSoft.resolvedColor(with: traitCollection).cgColor,
            Theme.primary.resolvedColor(with: traitCollection).cgColor,
        ]
    }
}
