import UIKit
import AnycastKit

/// Covered Show cards with persistent, list-owned Play / Add / Details actions.
@MainActor
final class ChannelEpisodeListBinder {

    private unowned let owner: UIViewController
    private let context: UIContext
    private let viewModel: ChannelViewModel
    private let htmlRenderer: HTMLContentRenderer
    weak var actionController: ListActionController?
    private var pendingAdds: Set<String> = []

    /// Enclosure URLs known to sit in any playlist (isInPlaylists,
    /// states/playlist.dart) — refreshed on appear, after adds, and when the
    /// playback queue changes.
    private var playlistMembers: Set<String> = []
    private let observation = ObservationLoop()

    var onListContentChanged: (() -> Void)?

    init(
        owner: UIViewController,
        context: UIContext,
        viewModel: ChannelViewModel,
        htmlRenderer: HTMLContentRenderer
    ) {
        self.owner = owner
        self.context = context
        self.viewModel = viewModel
        self.htmlRenderer = htmlRenderer
    }

    func startObservingPlayback() {
        observation.track(
            read: { [weak self] in
                guard let self else { return }
                _ = self.context.playback.currentEpisodeContent
                _ = self.context.playback.isPlaying
                _ = self.context.playback.isLoading
                _ = self.context.playback.queueEnclosureURLs
            },
            onChange: { [weak self] in
                self?.refreshGroup()
                self?.refreshPlaylistMembership()
            }
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
            refreshGroup()
        }
    }

    /// The row's long-press menu: Play / Pause, then Add to playlist (or a
    /// disabled "In playlist" — the channel-page inPlaylist guard).
    func menu(for episode: FeedEpisodeRow) -> UIMenu {
        let enclosureURL = episode.enclosureUrl ?? ""
        let playing = !enclosureURL.isEmpty && context.playback.isPlayingEpisode(enclosureURL)
        let inPlaylist = playlistMembers.contains(enclosureURL)
        let play = UIAction(
            title: playing ? "Pause" : "Play",
            image: playing ? AppIcons.pause : AppIcons.play
        ) { [weak self] _ in self?.playTapped(episode) }
        let add = inPlaylist
            ? UIAction(title: "In playlist", image: AppIcons.addedToList, attributes: .disabled) { _ in }
            : UIAction(title: "Add to playlist", image: AppIcons.addToList) { [weak self] _ in
                self?.addTapped(episode)
            }
        return UIMenu(children: [play, add])
    }

    // MARK: - Cell configuration

    func register(in collectionView: UICollectionView) {
        collectionView.register(EpisodeCardCell.self, forCellWithReuseIdentifier: EpisodeCardCell.reuseIdentifier)
    }

    /// `actionID` is the row's list-action identity — nil for a duplicate
    /// enclosure URL, whose row then toggles nothing and carries no gap.
    func configure(
        cell: EpisodeCardCell,
        episode: FeedEpisodeRow,
        actionID: String?,
        at indexPath: IndexPath,
        in collectionView: UICollectionView
    ) {
        let enclosureURL = episode.enclosureUrl ?? ""
        let inPlaylist = playlistMembers.contains(enclosureURL)

        let content = EpisodeCardContent(
            title: episode.title ?? "",
            channelTitle: episode.channelTitle ?? viewModel.channel.title ?? "",
            rightText: Self.rightText(for: episode),
            descriptionHTML: nil,
            imageURL: episode.imageUrl ?? viewModel.channel.imageUrl,
            showsChannel: false,
            layout: .show,
            inPlaylist: inPlaylist
        )
        cell.configure(content, actions: detailActions(for: episode))
        cell.onCardTap = { [weak self] in
            guard let actionID else { return }
            self?.actionController?.toggle(id: actionID)
        }
        cell.onCoverTap = { [weak self] in self?.presentDetail(episode: episode) }
        actionController?.reapplyGap(to: cell, id: actionID ?? "")
    }

    func groupItems(for episode: FeedEpisodeRow) -> [ListActionItem] {
        let inPlaylist = playlistMembers.contains(episode.enclosureUrl ?? "")
        return [
            ListActionItem(id: "play", content: .icon(AppIcons.play), accessibilityLabel: "Play") { [weak self] in
                self?.playTapped(episode)
            },
            ListActionItem(id: "add", content: .icon(inPlaylist ? AppIcons.addedToList : AppIcons.addToList),
                           accessibilityLabel: inPlaylist ? "In playlist" : "Add to playlist") { [weak self] in
                self?.addTapped(episode)
            },
            ListActionItem(id: "details", content: .title("Details"), accessibilityLabel: "Details") { [weak self] in
                self?.presentDetail(episode: episode)
            },
        ]
    }

    func refreshGroup() {
        guard let controller = actionController, let id = controller.selectedID else { return }
        ShowEpisodeActionGroup.refresh(
            controller, playback: context.playback, inPlaylist: playlistMembers.contains(id)
        )
    }

    /// Card right text: "{relative date} · {duration}" (shared episode
    /// meta); a nil pubDate omits the date instead of the Dart `pubDate!`
    /// crash (K4 family).
    nonisolated static func rightText(for episode: FeedEpisodeRow) -> String {
        RelativeTimeFormatter.dateAndDuration(
            pubDateMilliseconds: episode.pubDate, durationMilliseconds: episode.duration
        )
    }

    // MARK: - Actions (channel.dart:137-186 / 831-880)

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

    private func addTapped(_ episode: FeedEpisodeRow) {
        
        guard let url = episode.enclosureUrl, !url.isEmpty,
              ChannelPlaylistGate.action(inPlaylist: playlistMembers.contains(url)) != .blocked,
              pendingAdds.insert(url).inserted else { return }
        Task { [weak self] in
            guard let self else { return }
            defer { pendingAdds.remove(url) }
            await insertIntoPlaylist(episode)
        }
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
        refreshGroup()
    }

    // MARK: - Detail (cover tap, card.dart:129-138)

    func presentDetail(episode: FeedEpisodeRow) {
        guard let enclosureURL = episode.enclosureUrl else { return }
        let detailEpisode = DetailViewController.Episode(
            title: episode.title ?? "",
            channelTitle: episode.channelTitle ?? viewModel.channel.title ?? "",
            pubDateMilliseconds: episode.pubDate,
            durationMilliseconds: episode.duration,
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
                self?.addTapped(episode)
            },
        ]
    }
}
