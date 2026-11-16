import UIKit
import AnycastKit

/// Covered Show cards with persistent, list-owned Play / Add / Details actions.
@MainActor
final class SearchEpisodeBinder {

    private unowned let owner: UIViewController
    private let context: UIContext
    private let htmlRenderer: HTMLContentRenderer
    weak var actionController: ListActionController?
    private var pendingAdds: Set<String> = []

    /// Enclosure URLs known to sit in any playlist (isInPlaylists,
    /// states/playlist.dart:63) — refreshed on appear, after adds, and when
    /// the playback queue changes.
    private var playlistMembers: Set<String> = []

    var onListContentChanged: (() -> Void)?

    init(
        owner: UIViewController,
        context: UIContext,
        htmlRenderer: HTMLContentRenderer
    ) {
        self.owner = owner
        self.context = context
        self.htmlRenderer = htmlRenderer
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
            refreshGroup()
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
        let inPlaylist = playlistMembers.contains(enclosureURL)

        let content = EpisodeCardContent(
            title: episode.title ?? "",
            channelTitle: episode.channelTitle ?? item.channel.title ?? "",
            rightText: ChannelEpisodeListBinder.rightText(for: episode),
            descriptionHTML: nil,
            imageURL: episode.imageUrl ?? item.channel.imageUrl,
            layout: .show,
            inPlaylist: inPlaylist
        )
        cell.configure(content, actions: detailActions(for: item))
        cell.onCardTap = { [weak self] in
            guard !enclosureURL.isEmpty else { return }
            self?.actionController?.toggle(id: enclosureURL)
        }
        cell.onCoverTap = { [weak self] in self?.presentDetail(item: item) }
        actionController?.reapplyGap(to: cell, id: enclosureURL)
    }

    func groupItems(for item: APIClient.EpisodeWithChannel) -> [ListActionItem] {
        let episode = item.episode
        let inPlaylist = playlistMembers.contains(episode.enclosureUrl ?? "")
        return [
            ListActionItem(id: "play", content: .icon(AppIcons.play), accessibilityLabel: "Play") { [weak self] in
                self?.playTapped(episode)
            },
            ListActionItem(id: "add", content: .icon(inPlaylist ? AppIcons.addedToList : AppIcons.addToList),
                           accessibilityLabel: inPlaylist ? "In playlist" : "Add to playlist") { [weak self] in
                self?.addTapped(item)
            },
            ListActionItem(id: "details", content: .title("Details"), accessibilityLabel: "Details") { [weak self] in
                self?.presentDetail(item: item)
            },
        ]
    }

    func refreshGroup() {
        guard let controller = actionController, let id = controller.selectedID else { return }
        ShowEpisodeActionGroup.refresh(
            controller, playback: context.playback, inPlaylist: playlistMembers.contains(id)
        )
    }

    // MARK: - Actions (discover.dart:254-288)

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

    private func addTapped(_ item: APIClient.EpisodeWithChannel) {
        let episode = item.episode
        guard let url = episode.enclosureUrl, !url.isEmpty,
              ChannelPlaylistGate.action(inPlaylist: playlistMembers.contains(url)) != .blocked,
              pendingAdds.insert(url).inserted else { return }
        Task { [weak self] in
            guard let self else { return }
            defer { pendingAdds.remove(url) }
            await insertIntoPlaylist(episode)
        }
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
        refreshGroup()
    }

    // MARK: - Detail (cover tap, card.dart:129-138)

    func presentDetail(item: APIClient.EpisodeWithChannel) {
        let episode = item.episode
        guard let enclosureURL = episode.enclosureUrl else { return }
        let detailEpisode = DetailViewController.Episode(
            title: episode.title ?? "",
            channelTitle: episode.channelTitle ?? item.channel.title ?? "",
            pubDateMilliseconds: episode.pubDate,
            durationMilliseconds: episode.duration,
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
            },
            transcript: DetailTranscriptCoordinator(
                context: context,
                episode: detailEpisode,
                prepareEpisode: { [weak self] in
                    guard let self else { return nil }
                    return await self.addToTop(episode)
                }
            )
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
                self?.addTapped(item)
            },
        ]
    }
}
