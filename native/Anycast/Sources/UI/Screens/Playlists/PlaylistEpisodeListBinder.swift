import UIKit
import Lottie
import AnycastKit

/// Shared wiring of `EpisodeCardCell` rows for one playlist's episode list
/// (playlists.dart:122-195): the list-owned actions, live play/pause and
/// robot-lottie overlays, the Detail sheet on cover tap, and the download indicator. Reordering is
/// owned by the list controller's 150 ms interactive movement (07 §6) —
/// this binder carries no drag-and-drop surface.
@MainActor
final class PlaylistEpisodeListBinder: NSObject {

    private unowned let owner: UIViewController
    private let context: UIContext
    let playlistId: Int64

    weak var actionController: ListActionController?

    /// Manual card downloads (the old `CacheController.download`) —
    /// play-driven downloads report through `PlaybackService.cacheStates`.
    private(set) var manualDownloadProgress: [String: Double] = [:]
    private var manualDownloadTasks: [String: Task<Void, Never>] = [:]

    /// URLs known cached on disk at load time (CacheController.onInit port).
    private(set) var diskCachedURLs: Set<String> = []

    private let playbackObservation = ObservationLoop()
    private let downloadObservation = ObservationLoop()
    private let positionObservation = ObservationLoop()
    private let aiObservation = ObservationLoop()

    weak var collectionView: UICollectionView?

    /// The owning list controller (row authority for live refreshes).
    weak var episodeSource: PlaylistEpisodeDataSource?

    /// Fired whenever list-affecting state changed — the owning list reloads
    /// its data while retaining cells by identity.
    var onListContentChanged: (() -> Void)?

    init(
        owner: UIViewController,
        context: UIContext,
        playlistId: Int64
    ) {
        self.owner = owner
        self.context = context
        self.playlistId = playlistId
    }

    deinit {
        for task in manualDownloadTasks.values { task.cancel() }
    }

    // MARK: - Cell configuration

    func register(in collectionView: UICollectionView) {
        collectionView.register(EpisodeCardCell.self, forCellWithReuseIdentifier: EpisodeCardCell.reuseIdentifier)
        self.collectionView = collectionView
    }

    func configure(
        cell: EpisodeCardCell,
        episode: PlaylistEpisodeRow,
        at indexPath: IndexPath,
        in collectionView: UICollectionView,
        nowEpochMilliseconds: Int64 = Int64(Date().timeIntervalSince1970 * 1000)
    ) {
        let enclosureURL = episode.enclosureUrl ?? ""
        let playback = context.playback
        let isCurrent = !enclosureURL.isEmpty && playback.currentEpisode?.enclosureUrl == enclosureURL

        let input = PlaylistCardDisplay.Input(
            isCurrentEpisode: isCurrent,
            livePositionMilliseconds: playback.positionData.positionMilliseconds,
            liveDurationMilliseconds: playback.positionData.durationMilliseconds,
            playedDurationMilliseconds: episode.playedDuration,
            durationMilliseconds: episode.duration,
            pubDateMilliseconds: episode.pubDate,
            nowEpochMilliseconds: nowEpochMilliseconds
        )
        let content = EpisodeCardContent(
            title: episode.title ?? "",
            channelTitle: episode.channelTitle ?? "",
            rightText: PlaylistCardDisplay.rightText(input),
            imageURL: episode.imageUrl,
            showsProgress: true,
            progressFraction: PlaylistCardDisplay.progressFraction(input),
            downloadDisplay: downloadDisplay(for: enclosureURL),
            layout: .playlist,
            nowPlaying: isCurrent ? (playback.isPlaying ? .playing : .paused) : .none
        )
        cell.configure(content, actions: [])
        installAccessibilityReorderActions(on: cell, episode: episode)

        // Closures resolve the row's CURRENT index at tap time — a cell that
        // moved (drag reorder, apply without reconfigure) would otherwise
        // keep acting on its configure-time position (e.g. a former head
        // card still pausing playback on play-tap).
        cell.onCardTap = { [weak self] in
            guard let self else { return }
            self.actionController?.toggle(id: enclosureURL)
        }
        cell.onCoverTap = { [weak self] in
            self?.presentDetail(episode: episode)
        }
        cell.onDownloadTap = { [weak self] in
            self?.downloadTapped(enclosureURL)
        }
    }

    /// Pushes coarse playback/AI/download state into the visible cells
    /// (play icon snapshot, AI four-state, download indicator) without a
    /// full data reload.
    func refreshVisibleCards() {
        refreshGroup()
        refreshNowPlaying()
        forEachVisibleCard { cell, enclosureURL in
            cell.updateDownload(downloadDisplay(for: enclosureURL))
        }
    }

    /// Moves the now-playing marker to the current episode's card and
    /// toggles its animation with play/pause. Cell-level pushes only —
    /// playback ticks never reach here, so no card is reconfigured.
    private func refreshNowPlaying() {
        let playback = context.playback
        let currentURL = playback.currentEpisode?.enclosureUrl
        let isPlaying = playback.isPlaying
        forEachVisibleCard { cell, enclosureURL in
            let isCurrent = !enclosureURL.isEmpty && enclosureURL == currentURL
            cell.updateNowPlaying(isCurrent ? (isPlaying ? .playing : .paused) : .none)
        }
    }

    /// Each live source refreshes only the part of the card it drives: a
    /// download tick must not rebuild the group's live overlays.
    private func refreshVisiblePlayOverlays() {
        guard let controller = actionController, let id = controller.selectedID,
              let button = controller.groupView.button(for: "play") else { return }
        updatePlayOverlay(on: button, enclosureURL: id)
    }

    private func refreshVisibleAIDisplays() {
        guard let controller = actionController, let id = controller.selectedID,
              let button = controller.groupView.button(for: "transcript") else { return }
        applyAIDisplay(on: button, enclosureURL: id)
    }

    private func refreshVisibleDownloads() {
        forEachVisibleCard { cell, enclosureURL in cell.updateDownload(downloadDisplay(for: enclosureURL)) }
    }

    private func forEachVisibleCard(_ body: (EpisodeCardCell, String) -> Void) {
        guard let collectionView else { return }
        for path in collectionView.indexPathsForVisibleItems {
            guard let cell = collectionView.cellForItem(at: path) as? EpisodeCardCell,
                  let episode = episode(at: path) else { continue }
            body(cell, episode.enclosureUrl ?? "")
        }
    }

    /// Per-tick live progress for the CURRENT row only (card.dart:71-79).
    func pushLiveProgress() {
        guard let collectionView,
              let currentURL = context.playback.currentEpisode?.enclosureUrl else { return }
        for path in collectionView.indexPathsForVisibleItems {
            guard let cell = collectionView.cellForItem(at: path) as? EpisodeCardCell,
                  let episode = episode(at: path),
                  episode.enclosureUrl == currentURL else { continue }
            let positionData = context.playback.positionData
            cell.updateLiveProgress(
                fraction: PlaylistCardDisplay.progressFraction(PlaylistCardDisplay.Input(
                    isCurrentEpisode: true,
                    livePositionMilliseconds: positionData.positionMilliseconds,
                    liveDurationMilliseconds: positionData.durationMilliseconds,
                    playedDurationMilliseconds: episode.playedDuration,
                    durationMilliseconds: episode.duration,
                    pubDateMilliseconds: episode.pubDate,
                    nowEpochMilliseconds: 0
                )),
                rightText: PlaylistCardDisplay.timeLeft(
                    durationMilliseconds: positionData.durationMilliseconds,
                    playedMilliseconds: positionData.positionMilliseconds
                )
            )
        }
    }

    /// Seeds the disk-cached set (CacheController.onInit: check every
    /// playlist episode against the cache store).
    func refreshDiskCachedURLs(_ urls: Set<String>) {
        diskCachedURLs = urls
    }

    // MARK: - Observations

    func startObservingLiveState() {
        let playback = context.playback
        playbackObservation.track(
            read: {
                _ = playback.currentEpisodeContent
                _ = playback.isPlaying
                _ = playback.isLoading
            },
            onChange: { [weak self] in
                self?.refreshNowPlaying()
                self?.refreshVisiblePlayOverlays()
            }
        )
        downloadObservation.track(
            read: { _ = playback.cacheStates },
            onChange: { [weak self] in self?.refreshVisibleDownloads() }
        )
        positionObservation.track(
            read: { _ = playback.positionData },
            onChange: { [weak self] in self?.pushLiveProgress() }
        )
        // Deferred removals commit once the playing episode changes: the
        // in-memory queue still holds their rows and could advance into one.
        batch.onCommit = {
            ToastPresenter.shared.dismissAction(capsuleIdentifier: Self.capsuleIdentifier)
        }
        trackObservation.track(
            read: { _ = playback.currentEpisodeContent },
            onChange: { [weak self] in
                guard let self, self.ownTrackChanges == 0 else { return }
                let deferred = Set(self.batch.items.filter {
                    if case .stored = $0.storage { true } else { false }
                }.map(\.url))
                if PlaylistRemovalLogic.shouldCommitOnTrackChange(
                    pendingURLs: deferred,
                    currentURLAtRemoval: self.currentURLAtRemoval,
                    currentURL: playback.currentEpisode?.enclosureUrl
                ) {
                    Task { await self.batch.commitNow() }
                }
            }
        )
        let subtitles = context.subtitles
        aiObservation.track(
            read: { _ = subtitles.statuses },
            onChange: { [weak self] in self?.refreshVisibleAIDisplays() }
        )
    }

    // MARK: - Download indicator (card.dart:232-275)

    func downloadDisplay(for enclosureURL: String) -> DownloadDisplay {
        PlaylistDownloadDisplay.display(
            cacheState: context.playback.cacheStates[enclosureURL],
            manualProgress: manualDownloadProgress[enclosureURL],
            diskCached: diskCachedURLs.contains(enclosureURL)
        )
    }

    /// The 16×16 blue circle tap: start the manual download (only reachable
    /// in the not-downloaded state — the ring/check views carry no gesture).
    func downloadTapped(_ enclosureURL: String) {
        guard !enclosureURL.isEmpty,
              case .notDownloaded = downloadDisplay(for: enclosureURL),
              manualDownloadTasks[enclosureURL] == nil else { return }
        manualDownloadProgress[enclosureURL] = 0
        refreshVisibleCards()
        let cacheStore = context.cacheStore
        manualDownloadTasks[enclosureURL] = Task { [weak self] in
            let task = await cacheStore.startDownload(url: enclosureURL) { [weak self] progress in
                Task { @MainActor [weak self] in
                    guard let self, let progress,
                          DownloadProgressStep.isVisibleChange(
                              from: self.manualDownloadProgress[enclosureURL], to: progress
                          )
                    else { return }
                    self.manualDownloadProgress[enclosureURL] = progress
                    self.refreshVisibleDownloads()
                }
            }
            let downloadResult = try? await task.value
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.manualDownloadTasks[enclosureURL] = nil
                if downloadResult != nil {
                    self.manualDownloadProgress[enclosureURL] = 1
                    self.diskCachedURLs.insert(enclosureURL)
                } else {
                    // A failed download must not read as done (green):
                    // drop the progress entry so the card reverts to its
                    // not-downloaded display.
                    self.manualDownloadProgress.removeValue(forKey: enclosureURL)
                }
                self.refreshVisibleCards()
            }
        }
    }

    // MARK: - List-owned actions

    func groupItems(for episode: PlaylistEpisodeRow) -> [ListActionItem] {
        [
            ListActionItem(id: "play", content: .icon(AppIcons.play), accessibilityLabel: "Play") { [weak self] in
                self?.playTapped(episode)
            },
            ListActionItem(id: "transcript", content: .icon(AppIcons.aiTranscript),
                           accessibilityLabel: "Transcribe with AI") { [weak self] in
                self?.aiTapped(episode)
            },
            ListActionItem(id: "remove", content: .icon(AppIcons.remove), accessibilityLabel: "Remove") { [weak self] in
                self?.removeTapped(episode)
            },
            ListActionItem(id: "details", content: .title("Details"), accessibilityLabel: "Details") { [weak self] in
                self?.presentDetail(episode: episode)
            },
        ]
    }

    /// Detail keeps its own static actions; only the list owns live overlays.
    private func actions(for episode: PlaylistEpisodeRow) -> [EpisodeCardAction] {
        [
            EpisodeCardAction(icon: AppIcons.play, accessibilityLabel: "Play") { [weak self] in
                self?.playTapped(episode)
            },
            EpisodeCardAction(icon: AppIcons.aiTranscript, accessibilityLabel: "Transcribe with AI") { [weak self] in
                self?.aiTapped(episode)
            },
            EpisodeCardAction(icon: AppIcons.remove, accessibilityLabel: "Remove") { [weak self] in
                self?.removeTapped(episode)
            },
        ]
    }

    /// Resolve the CURRENT index: identity-kept cells can move without configure.
    private func playTapped(_ episode: PlaylistEpisodeRow) {
        guard let url = episode.enclosureUrl,
              let item = episodeSource?.visibleIndex(ofEnclosureURL: url) else { return }
        let playback = context.playback
        // The loaded head toggles pause/resume in place and keeps the group
        // open. Moving any other episode to the head must finish closing the
        // group first, so its controls cannot travel into a different Play tap.
        if item == 0, playback.currentPlaylistId == playlistId,
           playback.currentEpisode?.enclosureUrl == url {
            Task { [weak self] in
                await playback.togglePlay()
                self?.refreshVisibleCards()
            }
            return
        }
        let play: () -> Void = { [weak self] in
            Task { await self?.moveToTopAndPlay(episode) }
        }
        if let actionController {
            actionController.close(animated: true, completion: play)
        } else {
            play()
        }
    }

    /// moveToTop + playByEpisode — also reused by the history dialog's play
    /// action for this playlist's rows.
    func moveToTopAndPlay(_ episode: PlaylistEpisodeRow) async {
        var row = episode
        row.playlistId = playlistId
        try? await context.database.playlistRepository().insertOrUpdateByIndex(
            row, playlistId: playlistId, index: 0
        )
        if let stored = try? await context.database.playlistRepository()
            .episode(byEnclosureURL: episode.enclosureUrl ?? "") {
            row = stored
        }
        await context.playback.playByEpisode(row)
        onListContentChanged?()
    }

    /// AI transcribe four-state tap (playlists.dart:149-181).
    private func aiTapped(_ episode: PlaylistEpisodeRow) {
        guard let enclosureURL = episode.enclosureUrl, !enclosureURL.isEmpty else { return }
        let display = AITranscriptDisplay.display(status: context.subtitles.statuses[enclosureURL])
        switch AITranscriptAction.action(display: display) {
        case .requestTranscript:
            Task { [weak self] in
                guard let self else { return }
                let signal = await self.context.subtitles.add(url: enclosureURL)
                // K27: user-triggered failures stay visible; the poller
                // itself is silent and routes 401 to login. A quota 403
                // opens the same paywall the player capsule uses.
                guard let signal else {
                    let status = self.context.subtitles.statuses[enclosureURL]
                    if AuthAccountSnapshot.current(context: self.context).signedIn,
                       status == "processing" || status == "succeeded" {
                        TranscriptAllowanceCache.shared.invalidate()
                    }
                    return
                }
                await TranscriptRequests.presentFailure(
                    signal: signal,
                    context: self.context,
                    from: self.owner,
                    episode: Self.paywallEpisode(for: episode)
                )
            }
        case .toast(let message):
            if let window = owner.view?.window {
                ToastPresenter.shared.show(message, in: window, duration: 3)
            }
        case .none:
            break
        }
    }

    // MARK: - Remove with Undo

    /// One removed row of the batch. A class: the eager work and the commit
    /// both settle its state after the batch value has been handed around.
    @MainActor
    final class RemovedEpisode {
        enum Storage {
            /// The row is still stored; the commit deletes it.
            case stored
            /// Deleted already (eager); Undo re-inserts it at `index`.
            case deleted(row: PlaylistEpisodeRow, index: Int)
            /// Nothing to delete or restore (the row was already gone).
            case gone
        }

        let url: String
        let wasCurrent: Bool
        /// The live position at tap time; the stored progress is up to 2 s
        /// behind.
        let livePosition: Int64
        var storage: Storage = .stored

        init(url: String, wasCurrent: Bool, livePosition: Int64) {
            self.url = url
            self.wasCurrent = wasCurrent
            self.livePosition = livePosition
        }
    }

    private enum BatchKind { case remove }

    /// The serialized DB/playback work of eager removals, shared with the
    /// commit closure so a commit finishes after it.
    @MainActor
    private final class EagerWork {
        var chain: Task<Void, Never>?
        func settle() async { await chain?.value }
    }

    /// Every removal inside one Undo window. A deferred row (later in the
    /// queue) is only hidden and stays stored until the commit. An eager row
    /// (playing, or next in the in-memory queue, which could advance into
    /// it) leaves the card list at tap time like any other row, then its
    /// delete and the playback change run on `eagerWork`.
    private let batch = PendingBatch<BatchKind, RemovedEpisode>()
    private let eagerWork = EagerWork()
    /// Rows the list filters out of every reload: removed in this batch, or
    /// committed with their write still running.
    private(set) var hiddenEpisodeURLs: Set<String> = []
    private var currentURLAtRemoval: String?
    /// Playback changes this screen causes itself (stop-and-load-next, an
    /// Undo that restores the current episode) never commit the batch.
    private var ownTrackChanges = 0
    private let trackObservation = ObservationLoop()
    private static let capsuleIdentifier = "playlist-removal-capsule"

    /// Remove (playlists.dart:182-190), undoable for 5 s, merged with the
    /// removals before it. The card leaves at once. Removing the playing
    /// episode stops it and loads the next one paused. The current-track
    /// check is BY IDENTITY, captured before the first await (a reload
    /// landing mid-task would reshuffle indexes).
    func removeTapped(_ episode: PlaylistEpisodeRow) {
        guard let enclosureURL = episode.enclosureUrl, !enclosureURL.isEmpty,
              !hiddenEpisodeURLs.contains(enclosureURL) else { return }
        Haptics.queueRemoved()
        let playback = context.playback
        let wasCurrent = playback.currentEpisode?.enclosureUrl == enclosureURL
        let eager = PlaylistRemovalLogic.isEager(
            url: enclosureURL, wasCurrent: wasCurrent, playlistId: playlistId,
            playingPlaylistId: playback.currentPlaylistId, queueURLs: playback.queueEnclosureURLs
        )
        let item = RemovedEpisode(
            url: enclosureURL, wasCurrent: wasCurrent,
            livePosition: wasCurrent ? playback.positionData.positionMilliseconds : 0
        )
        hiddenEpisodeURLs.insert(enclosureURL)
        batch.add(item, kind: .remove, commit: makeCommit())
        if !eager { currentURLAtRemoval = playback.currentEpisode?.enclosureUrl }
        // UI first: the card leaves now, the work follows.
        episodeSource?.hideEpisode(byEnclosureURL: enclosureURL)
        showRemovalCapsule()
        if eager { enqueueEagerRemoval(item) }
    }

    /// Commits the pending batch now (the list is leaving, or a drag reorder
    /// is about to write); resolves once every write finished.
    func commitPendingRemoval() async {
        await batch.commitNow()
        await eagerWork.settle()
    }

    /// Waits for the eager removals' delete and playback work to finish.
    func settleEagerRemovals() async {
        await eagerWork.settle()
    }

    private func makeCommit() -> @MainActor ([RemovedEpisode]) async -> Void {
        let repository = context.database.playlistRepository()
        let cacheStore = context.cacheStore
        let playback = context.playback
        let playlistId = playlistId
        let work = eagerWork
        return { [weak self] items in
            await work.settle()
            // Only the queue row and cached audio go. Transcripts and their
            // in-flight polling stay (the Dart K3 cascade is dropped).
            var deletedDeferred = false
            for item in items {
                guard case .stored = item.storage else { continue }
                if (try? await repository.removeEpisode(byEnclosureURL: item.url)) != nil {
                    item.storage = .gone
                    deletedDeferred = true
                }
            }
            // The audio file is kept until the window ends, so Undo never
            // forces a re-download.
            for item in items { await cacheStore.remove(url: item.url) }
            self?.hiddenEpisodeURLs.subtract(items.map(\.url))
            if deletedDeferred, playback.currentPlaylistId == playlistId {
                // The in-memory queue must lose the rows too, or a head
                // completion later pulls a dead row back out of it.
                await playback.reloadQueue()
            }
            self?.onListContentChanged?()
        }
    }

    private func enqueueEagerRemoval(_ item: RemovedEpisode) {
        let predecessor = eagerWork.chain
        eagerWork.chain = Task { [weak self] in
            await predecessor?.value
            await self?.performEagerRemoval(item)
        }
    }

    /// Deletes the row and applies the playback change. Rows hidden by
    /// earlier deferred removals are deleted first, so the in-memory queue
    /// can reach none of them once the head moves; their stored indexes are
    /// taken in this same order, which Undo reverses.
    private func performEagerRemoval(_ item: RemovedEpisode) async {
        ownTrackChanges += 1
        defer {
            currentURLAtRemoval = context.playback.currentEpisode?.enclosureUrl
            ownTrackChanges -= 1
        }
        let repository = context.database.playlistRepository()
        let playback = context.playback
        // Every row still stored goes first, in batch order: the player must
        // never load a hidden row as the next episode. Undo reverses exactly
        // this order.
        let pending = batch.items.contains { $0 === item } ? batch.items : [item]
        for removed in pending { await delete(removed, repository: repository) }
        // Decided now, by identity, not at tap time: an earlier removal of
        // this batch may have made this row current, and the episode may have
        // completed and advanced the queue while the awaits above ran.
        if playback.currentEpisode?.enclosureUrl == item.url {
            await playback.replaceCurrentWithNext()
        } else if playback.currentPlaylistId == playlistId {
            await playback.reloadQueue()
        }
        onListContentChanged?()
    }

    /// Deletes the row of an item that is still stored; any other state is
    /// final.
    private func delete(_ item: RemovedEpisode, repository: PlaylistRepository) async {
        guard case .stored = item.storage else { return }
        guard var stored = await PlaylistRemovalLogic.snapshot(
            url: item.url, playlistId: playlistId, repository: repository
        ) else {
            item.storage = .gone
            return
        }
        // The stored progress is up to 2 s behind the player.
        if item.wasCurrent, item.livePosition > 0 { stored.row.playedDuration = item.livePosition }
        guard (try? await repository.removeEpisode(byEnclosureURL: item.url)) != nil else { return }
        item.storage = .deleted(row: stored.row, index: stored.index)
    }

    private func undoRemoval() {
        guard let undone = batch.undo() else { return }
        UIAccessibility.post(notification: .announcement, argument: "Restored")
        ownTrackChanges += 1
        Task { [weak self] in
            guard let self else { return }
            // Eager work settles first, so every item's storage is final.
            await self.eagerWork.settle()
            await self.restore(undone.items)
            self.currentURLAtRemoval = self.context.playback.currentEpisode?.enclosureUrl
            self.ownTrackChanges -= 1
        }
    }

    /// `items` come newest first: each stored index is only valid right
    /// before its own removal, so re-inserting last-to-first rebuilds the
    /// original order. Rows that were only hidden need nothing.
    private func restore(_ items: [RemovedEpisode]) async {
        let repository = context.database.playlistRepository()
        let playback = context.playback
        let playlistId = playlistId
        // Pressing Play on the episode that took over during the window is
        // the user's choice; the restored one then queues behind it.
        let playbackMoved = playback.isPlaying
        let formerCurrent = items.last { $0.wasCurrent }
        for item in items {
            guard case .deleted(let row, let index) = item.storage else { continue }
            let target = item === formerCurrent && playbackMoved ? max(index, 1) : index
            await PlaylistRemovalLogic.reinsert(row, at: target, playlistId: playlistId, repository: repository)
        }
        hiddenEpisodeURLs.subtract(items.map(\.url))
        if let formerCurrent, case .deleted = formerCurrent.storage, !playbackMoved {
            // The queue head is the current episode again, paused, at its
            // original progress.
            await playback.restoreCurrentPaused(enclosureURL: formerCurrent.url, playlistId: playlistId)
        } else if items.contains(where: { if case .deleted = $0.storage { true } else { false } }),
                  playback.currentPlaylistId == playlistId {
            await playback.reloadQueue()
        }
        onListContentChanged?()
    }

    private func showRemovalCapsule() {
        let count = batch.count
        let message = count > 1 ? "Removed \(count) episodes" : "Removed"
        if ToastPresenter.shared.updateAction(message, capsuleIdentifier: Self.capsuleIdentifier) { return }
        guard let window = owner.view?.window else { return }
        ToastPresenter.shared.showAction(
            message,
            actionTitle: "Undo",
            in: window,
            above: (owner.tabBarController as? MainTabBarController)?.bottomChromeTopAnchor,
            capsuleIdentifier: Self.capsuleIdentifier,
            actionIdentifier: "playlist-removal-undo",
            onAction: { [weak self] in self?.undoRemoval() },
            // Another toast replaced the capsule: Undo is out of reach.
            onSuperseded: { [weak self] in
                guard let self else { return }
                Task { await self.batch.commitNow() }
            }
        )
    }

    // MARK: - Live overlays (PlayIcon / AIIcon, play_icon.dart)

    func refreshGroup() {
        guard let controller = actionController, let id = controller.selectedID else { return }
        if let button = controller.groupView.button(for: "play") {
            installPlayOverlay(on: button, enclosureURL: id)
        }
        refreshVisibleAIDisplays()
    }

    private func installPlayOverlay(on button: ListActionCircle, enclosureURL: String) {
        if !button.contentHost.subviews.contains(where: { $0 is PlayPauseIconControl }) {
            let overlay = PlayPauseIconControl(size: 24)
            overlay.isUserInteractionEnabled = false
            overlay.isAccessibilityElement = false
            overlay.translatesAutoresizingMaskIntoConstraints = false
            button.contentHost.addSubview(overlay)
            NSLayoutConstraint.activate([
                overlay.centerXAnchor.constraint(equalTo: button.contentHost.centerXAnchor),
                overlay.centerYAnchor.constraint(equalTo: button.contentHost.centerYAnchor),
                // PR #9: center pins alone let the loading Lottie canvas grow
                // to hundreds of points. Always pin BOTH dimensions explicitly.
                overlay.widthAnchor.constraint(equalToConstant: overlay.size),
                overlay.heightAnchor.constraint(equalToConstant: overlay.size),
            ])
        }
        button.setDefaultContentHidden(true)
        updatePlayOverlay(on: button, enclosureURL: enclosureURL)
    }

    private func updatePlayOverlay(on button: ListActionCircle, enclosureURL: String) {
        guard let overlay = button.contentHost.subviews.compactMap({ $0 as? PlayPauseIconControl }).first else { return }
        let playback = context.playback
        overlay.update(
            snapshot: PlayPauseIconControl.Snapshot(
                enclosureURL: enclosureURL,
                currentEnclosureURL: playback.currentEpisode?.enclosureUrl,
                isPlaying: playback.isPlaying,
                isLoading: playback.isLoading
            ),
            tint: Theme.onSurface
        )
        button.accessibilityLabel = overlay.accessibilityLabel
    }

    private func applyAIDisplay(on button: ListActionCircle, enclosureURL: String) {
        let display = AITranscriptDisplay.display(status: context.subtitles.statuses[enclosureURL])
        switch display {
        case .processing:
            button.setDefaultContentHidden(true)
            if let robot = button.contentHost.subviews.compactMap({ $0 as? LottieAnimationView }).first {
                if !robot.isAnimationPlaying { robot.play() }
            } else {
                Self.installRobotOverlay(on: button.contentHost).play()
            }
        default:
            button.contentHost.subviews.compactMap { $0 as? LottieAnimationView }.forEach {
                $0.stop()
                $0.removeFromSuperview()
            }
            button.setIcon(display.icon, tint: display.tintColor)
            button.setDefaultContentHidden(false)
        }
        button.accessibilityLabel = Self.aiAccessibilityLabel(for: display)
    }

    /// Installs the processing-state robot lottie centered in the circle's
    /// content host, pinned to the animation's own canvas aspect: height 24,
    /// width derived. The canvas is 1920×1080 — a square 24×24 slot
    /// aspect-fits that wide scene down to 24×13.5, and the robot renders
    /// roughly half the neighboring glyph sizes. An explicit width also
    /// stays mandatory: a lottie pinned only by center + height lets its
    /// animation canvas stretch the view horizontally — the same class of
    /// blow-up as the play overlay (PR #9 device regression). Internal for
    /// the UIFixRegressionTests slot guard.
    static func installRobotOverlay(on button: UIView) -> LottieAnimationView {
        let robot = LottieAnimationView(name: "robot_loading")
        robot.contentMode = .scaleAspectFit
        robot.loopMode = .loop
        robot.translatesAutoresizingMaskIntoConstraints = false
        robot.isUserInteractionEnabled = false
        button.addSubview(robot)
        let canvas = robot.animation?.size ?? CGSize(width: 24, height: 24)
        NSLayoutConstraint.activate([
            robot.centerXAnchor.constraint(equalTo: button.centerXAnchor),
            robot.centerYAnchor.constraint(equalTo: button.centerYAnchor),
            robot.heightAnchor.constraint(equalToConstant: 24),
            robot.widthAnchor.constraint(
                equalToConstant: 24 * canvas.width / canvas.height
            ),
        ])
        return robot
    }

    private static func paywallEpisode(for episode: PlaylistEpisodeRow) -> PaywallModel.Episode {
        PaywallModel.Episode(
            title: episode.title ?? "",
            showName: episode.channelTitle ?? "",
            durationMilliseconds: episode.duration,
            artworkURL: episode.imageUrl.flatMap(URL.init(string:))
        )
    }

    private static func aiAccessibilityLabel(for display: AITranscriptDisplay) -> String {
        switch display {
        case .default, .unknown: return "Transcribe with AI"
        case .processing: return "Generating transcript"
        case .succeeded: return "Transcript ready"
        case .failed: return "Transcript failed"
        }
    }

    // MARK: - Accessibility reorder (whole-card drag has no handle)

    /// Whole-card drag is a touch-only gesture; VoiceOver users reorder
    /// through custom actions on the card title, reachable with the group closed.
    private func installAccessibilityReorderActions(
        on cell: EpisodeCardCell, episode: PlaylistEpisodeRow
    ) {
        // Each action resolves the row's current index when fired — the
        // configure-time index goes stale after a drag — and no-ops at the
        // list edges (item 0 up / last down would otherwise move row 0 with
        // (0, -1) and flip the playback source).
        cell.menuActions = [
            EpisodeCardAction(icon: UIImage(), accessibilityLabel: "Show details") { [weak self] in
                self?.presentDetail(episode: episode)
            },
            EpisodeCardAction(icon: UIImage(), accessibilityLabel: "Move up") { [weak self] in
                guard let self,
                      let url = episode.enclosureUrl,
                      let item = self.episodeSource?.visibleIndex(ofEnclosureURL: url),
                      item > 0 else { return }
                self.reorderHandler?(item, item - 1)
            },
            EpisodeCardAction(icon: UIImage(), accessibilityLabel: "Move down") { [weak self] in
                guard let self,
                      let url = episode.enclosureUrl,
                      let item = self.episodeSource?.visibleIndex(ofEnclosureURL: url),
                      item < (self.episodeSource?.visibleCount ?? 0) - 1 else { return }
                self.reorderHandler?(item, item + 1)
            },
        ] + actions(for: episode)
    }

    /// Programmatic reorder entry (accessibility actions, tests). The list
    /// controller installs the implementation.
    var reorderHandler: ((Int, Int) -> Void)?

    // MARK: - Detail (cover tap → the same three actions inside Detail)

    private func presentDetail(episode: PlaylistEpisodeRow) {
        // The Play capsule resumes from the live position for the current
        // episode and from the stored playedDuration otherwise.
        let positionData = context.playback.positionData
        let isCurrent = episode.enclosureUrl != nil
            && context.playback.currentEpisode?.enclosureUrl == episode.enclosureUrl
        let detailEpisode = DetailViewController.Episode(
            title: episode.title ?? "",
            channelTitle: episode.channelTitle ?? "",
            pubDateMilliseconds: episode.pubDate,
            durationMilliseconds: isCurrent ? positionData.durationMilliseconds : episode.duration,
            playedMilliseconds: isCurrent ? positionData.positionMilliseconds : episode.playedDuration,
            imageURL: episode.imageUrl,
            rssFeedURL: episode.rssFeedUrl ?? "",
            enclosureURL: episode.enclosureUrl ?? "",
            descriptionHTML: episode.description ?? ""
        )
        DetailViewController.present(
            from: owner.topMostPresented(),
            episode: detailEpisode,
            actions: actions(for: episode),
            htmlRenderer: HTMLContentRenderer(),
            shortenURL: { [weak self] url in
                await self?.context.api.getShortURL(for: url) ?? url
            },
            transcript: DetailTranscriptCoordinator(
                context: context,
                episode: detailEpisode,
                prepareEpisode: { [weak self] in
                    await self?.prepareTranscriptEpisode(episode)
                }
            )
        )
    }

    /// Play's move-to-top without starting audio.
    private func prepareTranscriptEpisode(_ episode: PlaylistEpisodeRow) async -> PlaylistEpisodeRow? {
        guard let enclosureURL = episode.enclosureUrl, !enclosureURL.isEmpty else { return nil }
        var row = episode
        row.playlistId = playlistId
        try? await context.database.playlistRepository().insertOrUpdateByIndex(
            row, playlistId: playlistId, index: 0
        )
        if let stored = try? await context.database.playlistRepository()
            .episode(byEnclosureURL: enclosureURL) {
            row = stored
        }
        return row
    }

    // MARK: - Helpers

    /// Row resolution goes through the owning list controller (the diffable
    /// data source is not the row authority).
    private func episode(at indexPath: IndexPath) -> PlaylistEpisodeRow? {
        episodeSource?.episode(at: indexPath)
    }
}

/// The data-source surface the binder needs to resolve an index path back
/// to its row (the diffable data source conforms in the list controller).
@MainActor
protocol PlaylistEpisodeDataSource: AnyObject {
    func episode(at indexPath: IndexPath) -> PlaylistEpisodeRow?
    /// The row's CURRENT position — closures captured at configure time go
    /// stale after a drag reorder (moved cells are not reconfigured).
    func index(of episode: PlaylistEpisodeRow) -> IndexPath?
    var rowCount: Int { get }
    /// Drops the card of a deferred removal from the list (animated like any
    /// removed row); the stored row stays.
    func hideEpisode(byEnclosureURL url: String)
    /// The URL's position among the VISIBLE rows (non-nil enclosure URLs —
    /// the same space the diffable snapshot and reorder coordinates use).
    /// Legacy rows with a NULL enclosureUrl are invisible to the snapshot;
    /// reorder inputs must be expressed in visible-row space.
    func visibleIndex(ofEnclosureURL url: String) -> Int?
    /// Count of visible (non-nil URL) rows.
    var visibleCount: Int { get }
}
