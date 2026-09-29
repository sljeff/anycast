import UIKit
import AnycastKit

/// SearchPage episode-list wiring (discover.dart:234-291): the Card rows
/// with the two strip actions — play (pause-when-playing) and
/// add-to-playlist with the SearchPage-specific UNGUARDED semantics
/// (SearchPageAddButton): the icon reflects membership, the tap always
/// flies the indicator in and then inserts/moves via addToPlaylist.
@MainActor
final class SearchEpisodeBinder {

    private unowned let owner: UIViewController
    private let context: UIContext
    private let htmlRenderer: HTMLContentRenderer
    private let expandCoordinator: CardExpandCoordinator

    /// Enclosure URLs known to sit in any playlist (isInPlaylists,
    /// states/playlist.dart:63) — refreshed on appear, after adds, and when
    /// the playback queue changes.
    private var playlistMembers: Set<String> = []

    weak var collectionView: UICollectionView?
    var onListContentChanged: (() -> Void)?

    init(
        owner: UIViewController,
        context: UIContext,
        htmlRenderer: HTMLContentRenderer,
        expandCoordinator: CardExpandCoordinator
    ) {
        self.owner = owner
        self.context = context
        self.htmlRenderer = htmlRenderer
        self.expandCoordinator = expandCoordinator
        self.expandCoordinator.onChange = { [weak self] _ in
            self?.onListContentChanged?()
        }
    }

    /// The page observes playback and calls this with the CURRENT episode
    /// list whenever the playing episode or queue changes.
    func refreshPlaylistMembership(episodes: [APIClient.EpisodeWithChannel]) {
        Task { [weak self] in
            guard let self else { return }
            // Full rebuild, not a union — see
            // ChannelEpisodeListBinder.refreshPlaylistMembership. One
            // batched query instead of a DB read per episode.
            let urls = episodes.compactMap { $0.episode.enclosureUrl }
            let members = (try? await self.context.database.playlistRepository()
                .playlistContainsURLs(urls)) ?? []
            if members != playlistMembers {
                playlistMembers = members
                onListContentChanged?()
            }
        }
    }

    // MARK: - Cell configuration

    func register(in collectionView: UICollectionView) {
        collectionView.register(
            EpisodeCardCell.self, forCellWithReuseIdentifier: EpisodeCardCell.reuseIdentifier
        )
    }

    func configure(
        cell: EpisodeCardCell,
        item: APIClient.EpisodeWithChannel,
        at indexPath: IndexPath,
        in collectionView: UICollectionView
    ) {
        let episode = item.episode
        let enclosureURL = episode.enclosureUrl ?? ""
        let playing = !enclosureURL.isEmpty && context.playback.isPlayingEpisode(enclosureURL)
        let inPlaylist = playlistMembers.contains(enclosureURL)

        let content = EpisodeCardContent(
            title: episode.title ?? "",
            channelTitle: episode.channelTitle ?? item.channel.title ?? "",
            rightText: ChannelEpisodeListBinder.rightText(for: episode),
            descriptionHTML: episode.description,
            imageURL: episode.imageUrl
        )
        cell.configure(
            content,
            actions: actions(for: item, playing: playing, inPlaylist: inPlaylist, at: indexPath)
        )
        cell.onCardTap = { [weak self] in
            guard let self else { return }
            self.expandCoordinator.toggle(at: indexPath)
            self.refreshExpandedState(in: collectionView)
        }
        cell.onCoverTap = { [weak self] in
            self?.presentDetail(item: item)
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

    // MARK: - Actions (discover.dart:254-288)

    private func actions(
        for item: APIClient.EpisodeWithChannel,
        playing: Bool,
        inPlaylist: Bool,
        at indexPath: IndexPath
    ) -> [EpisodeCardAction] {
        [
            EpisodeCardAction(
                icon: playing ? AppIcons.pause : AppIcons.play,
                accessibilityLabel: playing ? "Pause" : "Play"
            ) { [weak self] in
                self?.playTapped(item.episode)
            },
            EpisodeCardAction(
                icon: SearchPageAddButton.icon(inPlaylist: inPlaylist) == .added
                    ? AppIcons.addedToList
                    : AppIcons.addToList,
                accessibilityLabel: inPlaylist
                    ? "Move to playlist top" : "Add to playlist"
            ) { [weak self] in
                self?.addTapped(item, at: indexPath)
            },
        ]
    }

    /// Play: pause when this episode is playing, otherwise
    /// addToTop(1, ep).then(playByEpisode) (discover.dart:263-274).
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

    /// addToTop(1, ep) (states/feed_episode.dart:102-108).
    private func addToTop(_ episode: FeedEpisodeRow) async -> PlaylistEpisodeRow? {
        guard episode.enclosureUrl != nil else { return nil }
        let row = ChannelPlaylistLogic.playlistRow(
            from: episode, playlistId: ChannelPlaylistLogic.defaultPlaylistID
        )
        let repository = context.database.playlistRepository()
        try? await repository.insertOrUpdateByIndex(
            row, playlistId: ChannelPlaylistLogic.defaultPlaylistID, index: 0
        )
        if let enclosureURL = episode.enclosureUrl,
           let stored = try? await repository.episode(byEnclosureURL: enclosureURL) {
            return stored
        }
        return row
    }

    /// Add: UNGATED — even an in-playlist episode taps through (no
    /// `if (inPlaylist) return` guard on this page, 03 §2.6 correction),
    /// the fly-in runs FIRST (discover.dart:283-293 — the 4th trigger
    /// point, 03 §4), and the insert moves an existing row toward the top.
    func addTapped(_ item: APIClient.EpisodeWithChannel, at indexPath: IndexPath?) {
        guard let enclosureURL = item.episode.enclosureUrl, !enclosureURL.isEmpty else { return }
        let insert: () -> Void = { [weak self] in
            Task { await self?.insertIntoPlaylist(item.episode) }
        }
        guard let window = owner.view?.window else {
            insert()
            return
        }
        let start = plusButtonCenter(at: indexPath, in: window)
        context.flyInAnimator.fly(from: start, in: window, completion: insert)
    }

    /// addToPlaylist(1, ep) (states/feed_episode.dart:80-100): the index
    /// rule sends the row to the top (or slot 1 under the playing head),
    /// and `insertOrUpdateByIndex` MOVES an existing row there — the K14
    /// move semantics the unguarded tap relies on.
    private func insertIntoPlaylist(_ episode: FeedEpisodeRow) async {
        guard let enclosureURL = episode.enclosureUrl else { return }
        let row = ChannelPlaylistLogic.playlistRow(
            from: episode, playlistId: ChannelPlaylistLogic.defaultPlaylistID
        )
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
    private func plusButtonCenter(at indexPath: IndexPath?, in window: UIWindow) -> CGPoint {
        guard let collectionView,
              let indexPath,
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

    func presentDetail(item: APIClient.EpisodeWithChannel) {
        let episode = item.episode
        guard let enclosureURL = episode.enclosureUrl else { return }
        let detailEpisode = DetailViewController.Episode(
            title: episode.title ?? "",
            channelTitle: episode.channelTitle ?? item.channel.title ?? "",
            pubDateMilliseconds: episode.pubDate,
            imageURL: episode.imageUrl,
            rssFeedURL: episode.rssFeedUrl ?? item.channel.rssFeedUrl ?? "",
            enclosureURL: enclosureURL,
            descriptionHTML: episode.description ?? ""
        )
        // The same card actions render inside Detail (card.dart:115); the
        // Detail sheet is not one of the four fly-in trigger points, so its
        // add action inserts directly (the Channel precedent).
        DetailViewController.present(
            from: owner,
            episode: detailEpisode,
            actions: detailActions(for: item),
            htmlRenderer: htmlRenderer,
            openChannel: { [weak self] reference in
                guard let self else { return }
                // Detail stays open; the channel stacks on top (03 §10.1).
                let seed = SubscriptionRow(
                    rssFeedUrl: reference.rssFeedURL,
                    title: reference.title
                )
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

    private func detailActions(for item: APIClient.EpisodeWithChannel) -> [EpisodeCardAction] {
        [
            EpisodeCardAction(
                icon: AppIcons.play,
                accessibilityLabel: "Play"
            ) { [weak self] in
                self?.playTapped(item.episode)
            },
            EpisodeCardAction(
                icon: AppIcons.addToList,
                accessibilityLabel: "Add to playlist"
            ) { [weak self] in
                // Ungated like the list button (this page has no guard).
                Task { await self?.insertIntoPlaylist(item.episode) }
            },
        ]
    }
}
