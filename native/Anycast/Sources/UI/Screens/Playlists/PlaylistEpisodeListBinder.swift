import UIKit
import Lottie
import AnycastKit

/// Shared wiring of `EpisodeCardCell` rows for one playlist's episode list
/// (playlists.dart:122-195): the three strip actions (play/pause, AI
/// transcribe, remove), live play/pause and robot-lottie overlays, the
/// Detail sheet on cover tap, the download indicator, and the drag
/// delegate that serves system-raised drags a 1.1x lift preview (07 §6).
@MainActor
final class PlaylistEpisodeListBinder: NSObject, UICollectionViewDragDelegate {

    /// Action strip button tags (`EpisodeCardCell` tags buttons by index).
    private static let playActionTag = 0
    private static let aiActionTag = 1

    private unowned let owner: UIViewController
    private let context: UIContext
    let playlistId: Int64

    private let expandCoordinator: CardExpandCoordinator

    /// Manual card downloads (the old `CacheController.download`) —
    /// play-driven downloads report through `PlaybackService.cacheStates`.
    private(set) var manualDownloadProgress: [String: Double] = [:]
    private var manualDownloadTasks: [String: Task<Void, Never>] = [:]

    /// URLs known cached on disk at load time (CacheController.onInit port).
    private(set) var diskCachedURLs: Set<String> = []

    private let playbackObservation = ObservationLoop()
    private let positionObservation = ObservationLoop()
    private let aiObservation = ObservationLoop()

    weak var collectionView: UICollectionView?

    /// The owning list controller (row authority for live refreshes).
    weak var episodeSource: PlaylistEpisodeDataSource?

    /// Fired whenever list-affecting state changed — the owning list reloads
    /// its data and reconfigures visible cells.
    var onListContentChanged: (() -> Void)?

    init(
        owner: UIViewController,
        context: UIContext,
        playlistId: Int64,
        expandCoordinator: CardExpandCoordinator
    ) {
        self.owner = owner
        self.context = context
        self.playlistId = playlistId
        self.expandCoordinator = expandCoordinator
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
            descriptionHTML: episode.description,
            imageURL: episode.imageUrl,
            showsProgressBackdrop: true,
            progressFraction: PlaylistCardDisplay.progressFraction(input),
            downloadDisplay: downloadDisplay(for: enclosureURL)
        )
        cell.configure(content, actions: actions(for: episode))
        installPlayOverlay(on: cell, enclosureURL: enclosureURL)
        applyAIDisplay(on: cell, enclosureURL: enclosureURL)
        installAccessibilityReorderActions(on: cell, episode: episode)

        // Closures resolve the row's CURRENT index at tap time — a cell that
        // moved (drag reorder, apply without reconfigure) would otherwise
        // keep acting on its configure-time position (e.g. a former head
        // card still pausing playback on play-tap).
        cell.onCardTap = { [weak self] in
            guard let self else { return }
            guard let current = self.episodeSource?.index(of: episode) else { return }
            self.expandCoordinator.toggle(at: current)
            self.refreshExpandedState(in: collectionView)
        }
        cell.onCoverTap = { [weak self] in
            self?.presentDetail(episode: episode)
        }
        cell.onDownloadTap = { [weak self] in
            self?.downloadTapped(enclosureURL)
        }
        if expandCoordinator.expandedIndexPath == indexPath {
            cell.setExpanded(true)
        }
    }

    /// Re-applies strip state after reconfigure and animates item heights
    /// (the Channel-list precedent for the 0↔60 AnimatedContainer).
    func refreshExpandedState(in collectionView: UICollectionView) {
        CardExpandAnimator.refresh(
            expandedPath: expandCoordinator.expandedIndexPath,
            in: collectionView
        )
    }

    /// Pushes coarse playback/AI/download state into the visible cells
    /// (play icon snapshot, AI four-state, download indicator) without a
    /// full data reload.
    func refreshVisibleCards() {
        guard let collectionView else { return }
        for path in collectionView.indexPathsForVisibleItems {
            guard let cell = collectionView.cellForItem(at: path) as? EpisodeCardCell else { continue }
            guard let episode = episode(at: path) else { continue }
            let enclosureURL = episode.enclosureUrl ?? ""
            updatePlayOverlay(on: cell, enclosureURL: enclosureURL)
            applyAIDisplay(on: cell, enclosureURL: enclosureURL)
            cell.updateDownload(downloadDisplay(for: enclosureURL))
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
                rightText: TimeFormats.formatRemainingTime(
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
                _ = playback.currentEpisode
                _ = playback.isPlaying
                _ = playback.isLoading
                _ = playback.cacheStates
            },
            onChange: { [weak self] in self?.refreshVisibleCards() }
        )
        positionObservation.track(
            read: { _ = playback.positionData },
            onChange: { [weak self] in self?.pushLiveProgress() }
        )
        let subtitles = context.subtitles
        aiObservation.track(
            read: { _ = subtitles.statuses },
            onChange: { [weak self] in self?.refreshVisibleCards() }
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
                    guard let self, let progress else { return }
                    self.manualDownloadProgress[enclosureURL] = progress
                    self.refreshVisibleCards()
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

    // MARK: - Strip actions (playlists.dart:170-228)

    /// The card strip's play button renders through a live
    /// PlayPauseIconControl overlay — the strip action carries a BLANK icon
    /// (the overlay draws the glyph on top). Detail has no overlay, so its
    /// copy must swap in a real play glyph or the button renders as an
    /// empty white circle.
    private func actions(for episode: PlaylistEpisodeRow, livePlayOverlay: Bool = true) -> [EpisodeCardAction] {
        [
            EpisodeCardAction(
                // Blank: the live PlayPauseIconControl overlay renders the
                // icon/lottie on top of this button.
                icon: livePlayOverlay ? UIImage() : AppIcons.play,
                accessibilityLabel: "Play"
            ) { [weak self] in
                self?.playTapped(episode)
            },
            EpisodeCardAction(
                icon: AppIcons.aiTranscript ?? UIImage(),
                accessibilityLabel: "Transcribe with AI"
            ) { [weak self] in
                self?.aiTapped(episode)
            },
            EpisodeCardAction(
                icon: AppIcons.remove,
                accessibilityLabel: "Remove"
            ) { [weak self] in
                self?.removeTapped(episode)
            },
        ]
    }

    /// Play/pause (playlists.dart:136-148): playing the head pauses it;
    /// anything else moves to top and plays. The head check uses the row's
    /// CURRENT index — the configure-time index goes stale after a drag.
    private func playTapped(_ episode: PlaylistEpisodeRow) {
        guard let item = episodeSource?.index(of: episode)?.item else { return }
        let playback = context.playback
        let isPlayingThisList = playback.isPlaying
            && playback.currentPlaylistId == playlistId
        if isPlayingThisList && item == 0 {
            playback.pause()
            refreshVisibleCards()
            return
        }
        Task { [weak self] in
            await self?.moveToTopAndPlay(episode)
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
                // itself is silent and routes 401 to login.
                guard let signal, let window = self.owner.view?.window else { return }
                switch signal {
                case .errorMessage(let text):
                    ToastPresenter.shared.show(text, in: window, duration: 3)
                case .errorBody(let status, let body):
                    ToastPresenter.shared.show("Error \(status): \(body)", in: window, duration: 3)
                case .loginRequired:
                    break
                }
            }
        case .removeStaleRecord:
            Task { [weak self] in
                await self?.context.subtitles.remove(url: enclosureURL)
                if let window = self?.owner.view?.window {
                    ToastPresenter.shared.show(
                        AITranscriptAction.failedToastMessage, in: window, duration: 3
                    )
                }
            }
        case .toast(let message):
            if let window = owner.view?.window {
                ToastPresenter.shared.show(message, in: window, duration: 3)
            }
        case .none:
            break
        }
    }

    /// Remove (playlists.dart:182-190): K3 — removing the head also stops
    /// playback and clears the player state.
    func removeTapped(_ episode: PlaylistEpisodeRow) {
        guard let enclosureURL = episode.enclosureUrl, !enclosureURL.isEmpty else { return }
        Task { [weak self] in
            guard let self else { return }
            let repository = self.context.database.playlistRepository()
            try? await repository.removeEpisodeCascade(byEnclosureURL: enclosureURL)
            // The Dart remove cascaded into subtitle/translation/cache state.
            await self.context.subtitles.remove(url: enclosureURL)
            await self.context.translations.remove(url: enclosureURL)
            await self.context.cacheStore.remove(url: enclosureURL)
            if self.episodeSource?.index(of: episode)?.item == 0 {
                await self.clearPlaybackState()
            }
            self.onListContentChanged?()
        }
    }

    /// Dart `PlayerController.clear()` (states/player.dart:317-325): pause,
    /// empty the current episode, delete the pointer row. PlaybackService
    /// has no public full-clear yet (its private clearPlaybackState is the
    /// queue-empty path); the pointer delete + reload is the closest
    /// public-API equivalent — flagged for the player task.
    private func clearPlaybackState() async {
        context.playback.pause()
        try? await context.database.playerRepository().clear()
        await context.playback.reloadQueue()
    }

    // MARK: - Live overlays (PlayIcon / AIIcon, play_icon.dart)

    /// The play/pause strip button renders through a live
    /// `PlayPauseIconControl` overlay (loading lottie included) — the strip
    /// API only takes static images, so the blank-icon button is its tap
    /// target and accessibility anchor.
    private func installPlayOverlay(on cell: EpisodeCardCell, enclosureURL: String) {
        guard let button = Self.descendantButton(tagged: Self.playActionTag, in: cell) else { return }
        if let existing = button.subviews.compactMap({ $0 as? PlayPauseIconControl }).first {
            existing.removeFromSuperview()
        }
        let overlay = PlayPauseIconControl(size: 24)
        overlay.isUserInteractionEnabled = false
        overlay.translatesAutoresizingMaskIntoConstraints = false
        button.addSubview(overlay)
        NSLayoutConstraint.activate([
            overlay.centerXAnchor.constraint(equalTo: button.centerXAnchor),
            overlay.centerYAnchor.constraint(equalTo: button.centerYAnchor),
        ])
        button.setImage(UIImage(), for: .normal)
        button.isAccessibilityElement = true
        updatePlayOverlay(on: cell, enclosureURL: enclosureURL)
    }

    private func updatePlayOverlay(on cell: EpisodeCardCell, enclosureURL: String) {
        guard let button = Self.descendantButton(tagged: Self.playActionTag, in: cell),
              let overlay = button.subviews.compactMap({ $0 as? PlayPauseIconControl }).first else { return }
        let playback = context.playback
        overlay.update(
            snapshot: PlayPauseIconControl.Snapshot(
                enclosureURL: enclosureURL,
                currentEnclosureURL: playback.currentEpisode?.enclosureUrl,
                isPlaying: playback.isPlaying,
                isLoading: playback.isLoading
            ),
            tint: Theme.primaryBackgroundDark
        )
        button.accessibilityLabel = overlay.accessibilityLabel
    }

    /// AI four state (play_icon.dart AIIcon): sparkle / robot lottie /
    /// green check / failed bubble. The lottie overlays the strip button;
    /// the static tinted SF symbols cover the rest.
    private func applyAIDisplay(on cell: EpisodeCardCell, enclosureURL: String) {
        guard let button = Self.descendantButton(tagged: Self.aiActionTag, in: cell) else { return }
        let display = AITranscriptDisplay.display(status: context.subtitles.statuses[enclosureURL])
        switch display {
        case .processing:
            button.setImage(UIImage(), for: .normal)
            button.tintColor = Theme.primaryBackgroundDark
            // Reuse an in-flight robot: visible cards reconfigure on every
            // playback / download tick, and rebuilding the lottie restarts
            // it from frame 0 — a processing robot would effectively freeze
            // while any download progresses.
            if let robot = button.subviews.compactMap({ $0 as? LottieAnimationView }).first {
                if !robot.isAnimationPlaying { robot.play() }
            } else {
                let robot = LottieAnimationView(name: "robot_loading")
                robot.contentMode = .scaleAspectFit
                robot.loopMode = .loop
                robot.translatesAutoresizingMaskIntoConstraints = false
                robot.isUserInteractionEnabled = false
                button.addSubview(robot)
                NSLayoutConstraint.activate([
                    robot.centerXAnchor.constraint(equalTo: button.centerXAnchor),
                    robot.centerYAnchor.constraint(equalTo: button.centerYAnchor),
                    robot.heightAnchor.constraint(equalToConstant: 24),
                ])
                robot.play()
            }
        default:
            // Strip any previous lottie overlay.
            button.subviews.compactMap { $0 as? LottieAnimationView }.forEach {
                $0.stop()
                $0.removeFromSuperview()
            }
            button.setImage(display.icon, for: .normal)
            button.tintColor = display.tintColor
        }
        button.accessibilityLabel = Self.aiAccessibilityLabel(for: display)
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
    /// through custom actions anchored on the play/pause strip button
    /// (surfaced via the actions rotor), plus a details action replacing
    /// the now-element-hosting card body.
    private func installAccessibilityReorderActions(
        on cell: EpisodeCardCell, episode: PlaylistEpisodeRow
    ) {
        guard let button = Self.descendantButton(tagged: Self.playActionTag, in: cell) else { return }
        // Each action resolves the row's current index when fired — the
        // configure-time index goes stale after a drag — and no-ops at the
        // list edges (item 0 up / last down would otherwise move row 0 with
        // (0, -1) and flip the playback source).
        button.accessibilityCustomActions = [
            UIAccessibilityCustomAction(name: "Show details") { [weak self] _ in
                self?.presentDetail(episode: episode)
                return true
            },
            UIAccessibilityCustomAction(name: "Move up") { [weak self] _ in
                guard let self,
                      let url = episode.enclosureUrl,
                      let item = self.episodeSource?.visibleIndex(ofEnclosureURL: url),
                      item > 0 else { return false }
                self.reorderHandler?(item, item - 1)
                return true
            },
            UIAccessibilityCustomAction(name: "Move down") { [weak self] _ in
                guard let self,
                      let url = episode.enclosureUrl,
                      let item = self.episodeSource?.visibleIndex(ofEnclosureURL: url),
                      item < (self.episodeSource?.visibleCount ?? 0) - 1 else { return false }
                self.reorderHandler?(item, item + 1)
                return true
            },
        ]
    }

    /// Programmatic reorder entry (accessibility actions, tests). The list
    /// controller installs the implementation.
    var reorderHandler: ((Int, Int) -> Void)?

    // MARK: - Detail (cover tap → the same three actions inside Detail)

    private func presentDetail(episode: PlaylistEpisodeRow) {
        let detailEpisode = DetailViewController.Episode(
            title: episode.title ?? "",
            channelTitle: episode.channelTitle ?? "",
            pubDateMilliseconds: episode.pubDate,
            imageURL: episode.imageUrl,
            rssFeedURL: episode.rssFeedUrl ?? "",
            enclosureURL: episode.enclosureUrl ?? "",
            descriptionHTML: episode.description ?? ""
        )
        DetailViewController.present(
            from: owner.topMostPresented(),
            episode: detailEpisode,
            actions: actions(for: episode, livePlayOverlay: false),
            htmlRenderer: HTMLContentRenderer(),
            shortenURL: { [weak self] url in
                await self?.context.api.getShortURL(for: url) ?? url
            }
        )
    }

    // MARK: - Drag & drop (07 §6): 1.1x preview for system-raised drags

    /// Drag items for a drag session raised by the system reorder gesture;
    /// the preview provider carries the 1.1x lift (03 §4 proxyDecorator).
    func collectionView(
        _ collectionView: UICollectionView,
        itemsForBeginning session: UIDragSession,
        at indexPath: IndexPath
    ) -> [UIDragItem] {
        // onReorderStart (playlists.dart:136-138): collapse any open strip.
        expandCoordinator.close()
        refreshExpandedState(in: collectionView)

        let item = UIDragItem(itemProvider: NSItemProvider())
        item.localObject = indexPath
        let sourceCell = collectionView.cellForItem(at: indexPath)
        item.previewProvider = { [weak sourceCell] in
            guard let sourceCell else { return nil }
            return Self.scaledPreview(of: sourceCell, scale: 1.1)
        }
        return [item]
    }

    /// A snapshot of the cell scaled to `scale`, inside a container sized
    /// to the scaled bounds (UIDragPreview adopts the container's frame).
    private static func scaledPreview(of cell: UICollectionViewCell, scale: CGFloat) -> UIDragPreview {
        let size = cell.bounds.size
        let scaled = CGSize(width: size.width * scale, height: size.height * scale)
        let container = UIView(frame: CGRect(origin: .zero, size: scaled))
        let snapshot = cell.snapshotView(afterScreenUpdates: false) ?? UIView(frame: cell.bounds)
        snapshot.frame = CGRect(origin: .zero, size: size)
        snapshot.center = CGPoint(x: scaled.width / 2, y: scaled.height / 2)
        snapshot.transform = CGAffineTransform(scaleX: scale, y: scale)
        container.addSubview(snapshot)
        return UIDragPreview(view: container)
    }

    // MARK: - Helpers

    /// Row resolution goes through the owning list controller (the diffable
    /// data source is not the row authority).
    private func episode(at indexPath: IndexPath) -> PlaylistEpisodeRow? {
        episodeSource?.episode(at: indexPath)
    }

    private static func descendantButton(tagged tag: Int, in view: UIView) -> UIButton? {
        if let button = view as? UIButton, button.tag == tag {
            return button
        }
        for subview in view.subviews {
            if let found = descendantButton(tagged: tag, in: subview) {
                return found
            }
        }
        return nil
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
    /// The URL's position among the VISIBLE rows (non-nil enclosure URLs —
    /// the same space the diffable snapshot and reorder coordinates use).
    /// Legacy rows with a NULL enclosureUrl are invisible to the snapshot;
    /// reorder inputs must be expressed in visible-row space.
    func visibleIndex(ofEnclosureURL url: String) -> Int?
    /// Count of visible (non-nil URL) rows.
    var visibleCount: Int { get }
}
