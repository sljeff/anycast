import UIKit
import AnycastKit

extension EpisodeCardAction {
    /// The add-to-playlist action's index — `EpisodeCardCell` tags its strip
    /// buttons by action index, so this locates the fly-in origin.
    static let addActionTag = 1
}

/// Shared wiring of `EpisodeCardCell` rows for the Channel and
/// ChannelSearch lists (the two card lists of channel.dart:101-193 and
/// 796-885): identical actions (play / add-to-playlist), the channel-page
/// inPlaylist guard, the fly-in-then-insert order, Detail presentation on
/// cover tap, and mutual exclusion through a `CardExpandCoordinator`.
@MainActor
final class ChannelEpisodeListBinder {

    private unowned let owner: UIViewController
    private let context: UIContext
    private let viewModel: ChannelViewModel
    private let htmlRenderer: HTMLContentRenderer
    private let expandCoordinator: CardExpandCoordinator

    /// Enclosure URLs known to sit in any playlist (isInPlaylists,
    /// states/playlist.dart) — refreshed on appear, after adds, and when the
    /// playback queue changes.
    private var playlistMembers: Set<String> = []
    private let observation = ObservationLoop()

    /// The owner's collection view (set at build time) — resolves tapped
    /// cells for the fly-in start point.
    weak var collectionView: UICollectionView?

    var onListContentChanged: (() -> Void)?

    init(
        owner: UIViewController,
        context: UIContext,
        viewModel: ChannelViewModel,
        htmlRenderer: HTMLContentRenderer,
        expandCoordinator: CardExpandCoordinator
    ) {
        self.owner = owner
        self.context = context
        self.viewModel = viewModel
        self.htmlRenderer = htmlRenderer
        self.expandCoordinator = expandCoordinator
        self.expandCoordinator.onChange = { [weak self] _ in
            self?.onListContentChanged?()
        }
    }

    func startObservingPlayback() {
        observation.track(
            read: { [weak self] in
                guard let self else { return }
                _ = self.context.playback.currentEpisode
                _ = self.context.playback.isPlaying
                _ = self.context.playback.isLoading
                _ = self.context.playback.queue.map(\.enclosureUrl)
            },
            onChange: { [weak self] in self?.refreshPlaylistMembership() }
        )
    }

    func refreshPlaylistMembership() {
        Task { [weak self] in
            guard let self else { return }
            // Rebuild the whole set on every refresh: a union-only cache
            // never notices removals made elsewhere (playlist page, search
            // page), so the icon stayed "already in playlist" and the tap
            // gate blocked re-adding for the rest of the session. One
            // batched query instead of a DB read per episode.
            let urls = viewModel.showEpisodes.compactMap(\.enclosureUrl)
            let members = (try? await context.database.playlistRepository()
                .playlistContainsURLs(urls)) ?? []
            if members != playlistMembers {
                playlistMembers = members
                onListContentChanged?()
            }
        }
    }

    // MARK: - Cell configuration

    func register(in collectionView: UICollectionView) {
        collectionView.register(EpisodeCardCell.self, forCellWithReuseIdentifier: EpisodeCardCell.reuseIdentifier)
    }

    func configure(cell: EpisodeCardCell, episode: FeedEpisodeRow, at indexPath: IndexPath, in collectionView: UICollectionView) {
        let enclosureURL = episode.enclosureUrl ?? ""
        let playing = !enclosureURL.isEmpty && context.playback.isPlayingEpisode(enclosureURL)
        let inPlaylist = playlistMembers.contains(enclosureURL)

        let content = EpisodeCardContent(
            title: episode.title ?? "",
            channelTitle: episode.channelTitle ?? viewModel.channel.title ?? "",
            rightText: Self.rightText(for: episode),
            descriptionHTML: episode.description,
            imageURL: episode.imageUrl
        )
        cell.configure(content, actions: actions(for: episode, playing: playing, inPlaylist: inPlaylist, at: indexPath))
        cell.onCardTap = { [weak self] in
            guard let self else { return }
            self.expandCoordinator.toggle(at: indexPath)
            self.refreshExpandedState(in: collectionView)
        }
        cell.onCoverTap = { [weak self] in
            self?.presentDetail(episode: episode)
        }
        if expandCoordinator.expandedIndexPath == indexPath {
            cell.setExpanded(true)
        }
    }

    /// Re-applies the strip state after any reconfigure (configure resets
    /// the strip) and animates the item height with it.
    func refreshExpandedState(in collectionView: UICollectionView) {
        CardExpandAnimator.refresh(
            expandedPath: expandCoordinator.expandedIndexPath,
            in: collectionView
        )
    }

    /// Card right text: "{duration} • {relative datetime}"
    /// (card.dart:50-51); nil pubDate degrades to 0 instead of the Dart
    /// `pubDate!` crash (K4 family).
    nonisolated static func rightText(for episode: FeedEpisodeRow) -> String {
        let duration = TimeFormats.formatDuration(episode.duration ?? 0)
        let date = TimeFormats.formatDatetime(
            episode.pubDate ?? 0,
            nowEpochMilliseconds: Int64(Date().timeIntervalSince1970 * 1000)
        )
        return "\(duration) • \(date)"
    }

    // MARK: - Actions (channel.dart:137-186 / 831-880)

    private func actions(
        for episode: FeedEpisodeRow,
        playing: Bool,
        inPlaylist: Bool,
        at indexPath: IndexPath
    ) -> [EpisodeCardAction] {
        [
            EpisodeCardAction(
                icon: playing ? AppIcons.pause : AppIcons.play,
                accessibilityLabel: playing ? "Pause" : "Play"
            ) { [weak self] in
                self?.playTapped(episode)
            },
            EpisodeCardAction(
                icon: inPlaylist ? AppIcons.addedToList : AppIcons.addToList,
                accessibilityLabel: inPlaylist ? "Already in playlist" : "Add to playlist"
            ) { [weak self] in
                self?.addTapped(episode, at: indexPath)
            },
        ]
    }

    private func playTapped(_ episode: FeedEpisodeRow) {
        guard let enclosureURL = episode.enclosureUrl, !enclosureURL.isEmpty else { return }
        if context.playback.isPlayingEpisode(enclosureURL) {
            context.playback.pause()
            onListContentChanged?()
            return
        }
        Task { [weak self] in
            guard let row = await self?.addToTop(episode) else { return }
            await self?.context.playback.playByEpisode(row)
        }
    }

    /// addToTop(1, ep) then playByEpisode (channel.dart:143-149). Also the
    /// "Latest Episode" path (channel.dart:506-512).
    func addToTop(_ episode: FeedEpisodeRow) async -> PlaylistEpisodeRow? {
        guard let enclosureURL = episode.enclosureUrl else { return nil }
        let row = ChannelPlaylistLogic.playlistRow(from: episode, playlistId: ChannelPlaylistLogic.defaultPlaylistID)
        let repository = context.database.playlistRepository()
        try? await repository.insertOrUpdateByIndex(
            row, playlistId: ChannelPlaylistLogic.defaultPlaylistID, index: 0
        )
        if let stored = try? await repository.episode(byEnclosureURL: enclosureURL) {
            return stored
        }
        return row
    }

    private func addTapped(_ episode: FeedEpisodeRow, at indexPath: IndexPath) {
        guard let enclosureURL = episode.enclosureUrl, !enclosureURL.isEmpty else { return }
        // Channel + ChannelSearch are the ONLY card lists with this guard
        // (channel.dart:152-155 / 831-834, 03 §2.6 correction).
        guard ChannelPlaylistGate.action(inPlaylist: playlistMembers.contains(enclosureURL)) == .flyInAndInsert else {
            return
        }
        // Fly-in first (600 ms), insert on completion — channel.dart:160-183.
        let insert: () -> Void = { [weak self] in
            Task { await self?.insertIntoPlaylist(episode) }
        }
        guard let window = owner.view?.window else {
            insert()
            return
        }
        let start = plusButtonCenter(at: indexPath, in: window)
        context.flyInAnimator.fly(from: start, in: window, completion: insert)
    }

    /// addToPlaylist(1, ep) (states/feed_episode.dart:80-105).
    private func insertIntoPlaylist(_ episode: FeedEpisodeRow) async {
        guard let enclosureURL = episode.enclosureUrl else { return }
        let row = ChannelPlaylistLogic.playlistRow(from: episode, playlistId: ChannelPlaylistLogic.defaultPlaylistID)
        let repository = context.database.playlistRepository()
        let index = ChannelPlaylistLogic.addToPlaylistIndex(
            currentPlaylistId: context.playback.currentPlaylistId,
            targetPlaylistId: ChannelPlaylistLogic.defaultPlaylistID,
            currentEnclosureURL: context.playback.currentEpisode?.enclosureUrl,
            episodeEnclosureURL: enclosureURL
        )
        if let index {
            do {
                try await repository.insertOrUpdateByIndex(
                    row, playlistId: ChannelPlaylistLogic.defaultPlaylistID, index: index
                )
                playlistMembers.insert(enclosureURL)
            } catch {
                // A failed write must not flip the icon to the added
                // variant — keep the pre-tap membership so the add can be
                // retried.
            }
        } else {
            // nil index = the episode already is the playing queue head —
            // a member without another write.
            playlistMembers.insert(enclosureURL)
        }
        if context.playback.currentPlaylistId == ChannelPlaylistLogic.defaultPlaylistID {
            await context.playback.reloadQueue()
        }
        onListContentChanged?()
    }

    /// The fly-in origin is the tapped plus button (epBtnKey in Dart); the
    /// cell tags its action buttons by action index, so the second action's
    /// button is reachable without touching the shared component.
    private func plusButtonCenter(at indexPath: IndexPath, in window: UIWindow) -> CGPoint {
        guard let collectionView,
              let cell = collectionView.cellForItem(at: indexPath) as? EpisodeCardCell else {
            return window.center
        }
        if let button = Self.descendant(tagged: EpisodeCardAction.addActionTag, in: cell) {
            return button.convert(CGPoint(x: button.bounds.midX, y: button.bounds.midY), to: window)
        }
        // Fallback: the right action button's strip position.
        return cell.convert(
            CGPoint(x: cell.bounds.width - 44, y: cell.bounds.height - 28),
            to: window
        )
    }

    private static func descendant(tagged tag: Int, in view: UIView) -> UIButton? {
        if let button = view as? UIButton, button.tag == tag {
            return button
        }
        for subview in view.subviews {
            if let found = descendant(tagged: tag, in: subview) {
                return found
            }
        }
        return nil
    }

    // MARK: - Detail (cover tap, card.dart:129-138)

    func presentDetail(episode: FeedEpisodeRow) {
        guard let enclosureURL = episode.enclosureUrl else { return }
        let detailEpisode = DetailViewController.Episode(
            title: episode.title ?? "",
            channelTitle: episode.channelTitle ?? viewModel.channel.title ?? "",
            pubDateMilliseconds: episode.pubDate,
            imageURL: episode.imageUrl,
            rssFeedURL: viewModel.rssFeedURL,
            enclosureURL: enclosureURL,
            descriptionHTML: episode.description ?? ""
        )
        // The same card actions render inside Detail (card.dart:115).
        DetailViewController.present(
            from: owner,
            episode: detailEpisode,
            actions: detailActions(for: episode),
            htmlRenderer: htmlRenderer,
            openChannel: { [weak self] reference in
                guard let self else { return }
                // Detail stays open; the channel stacks on top (03 §10.1).
                let seed = SubscriptionRow(rssFeedUrl: reference.rssFeedURL, title: reference.title)
                ChannelViewController.present(
                    from: self.owner.topMostPresented(),
                    context: self.context,
                    rssFeedURL: reference.rssFeedURL,
                    seed: seed
                )
            },
            shortenURL: { [weak self] url in
                await self?.context.api.getShortURL(for: url) ?? url
            }
        )
    }

    private func detailActions(for episode: FeedEpisodeRow) -> [EpisodeCardAction] {
        [
            EpisodeCardAction(
                icon: AppIcons.play,
                accessibilityLabel: "Play"
            ) { [weak self] in
                self?.playTapped(episode)
            },
            EpisodeCardAction(
                icon: AppIcons.addToList,
                accessibilityLabel: "Add to playlist"
            ) { [weak self] in
                guard let enclosureURL = episode.enclosureUrl, !enclosureURL.isEmpty else { return }
                guard ChannelPlaylistGate.action(inPlaylist: false) == .flyInAndInsert else { return }
                Task { await self?.insertIntoPlaylist(episode) }
            },
        ]
    }
}
