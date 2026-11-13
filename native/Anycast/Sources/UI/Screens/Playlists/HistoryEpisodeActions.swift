import UIKit
import AnycastKit

/// What a history row can do, shared by the History sheet and the Library's
/// Recently played: open Detail with Play / Remove, play, and prepare the
/// episode for its transcript.
@MainActor
enum HistoryEpisodeActions {

    /// Opens Detail for `episode` from `presenter`. Play replays it and then
    /// calls `didPlay`; Remove calls `remove` with the enclosure URL.
    static func presentDetail(
        _ episode: HistoryEpisodeRow,
        from presenter: UIViewController,
        context: UIContext,
        didPlay: @escaping () async -> Void,
        remove: @escaping (String) -> Void
    ) {
        let detailEpisode = DetailViewController.Episode(
            title: episode.title ?? "",
            channelTitle: episode.channelTitle ?? "",
            pubDateMilliseconds: episode.pubDate,
            durationMilliseconds: episode.duration,
            imageURL: episode.imageUrl,
            rssFeedURL: episode.rssFeedUrl ?? "",
            enclosureURL: episode.enclosureUrl ?? "",
            descriptionHTML: episode.description ?? ""
        )
        DetailViewController.present(
            from: presenter,
            episode: detailEpisode,
            actions: [
                EpisodeCardAction(
                    icon: AppIcons.play,
                    accessibilityLabel: "Play"
                ) {
                    Task {
                        await play(episode, context: context)
                        await didPlay()
                    }
                },
                EpisodeCardAction(
                    icon: AppIcons.remove,
                    accessibilityLabel: "Remove"
                ) {
                    guard let url = episode.enclosureUrl else { return }
                    remove(url)
                },
            ],
            htmlRenderer: HTMLContentRenderer(),
            shortenURL: { url in
                await context.api.getShortURL(for: url) ?? url
            },
            transcript: DetailTranscriptCoordinator(
                context: context,
                episode: detailEpisode,
                prepareEpisode: {
                    await prepareTranscriptEpisode(episode, context: context)
                }
            )
        )
    }

    /// Same insert as play, without starting audio.
    static func prepareTranscriptEpisode(
        _ episode: HistoryEpisodeRow, context: UIContext
    ) async -> PlaylistEpisodeRow? {
        guard let enclosureURL = episode.enclosureUrl, !enclosureURL.isEmpty else { return nil }
        return await queueHead(for: episode, context: context)
    }

    static func play(_ episode: HistoryEpisodeRow, context: UIContext) async {
        guard let row = await queueHead(for: episode, context: context) else { return }
        await context.playback.playByEpisode(row)
    }

    /// Puts `episode` at the head of the default playlist and returns the
    /// stored row (it keeps the saved progress).
    private static func queueHead(for episode: HistoryEpisodeRow, context: UIContext) async -> PlaylistEpisodeRow? {
        let playlistId = ChannelPlaylistLogic.defaultPlaylistID
        var row = PlaylistEpisodeRow(
            title: episode.title,
            description: episode.description,
            duration: episode.duration,
            enclosureUrl: episode.enclosureUrl,
            pubDate: episode.pubDate,
            imageUrl: episode.imageUrl,
            channelTitle: episode.channelTitle,
            rssFeedUrl: episode.rssFeedUrl,
            playlistId: playlistId
        )
        let repository = context.database.playlistRepository()
        try? await repository.insertOrUpdateByIndex(row, playlistId: playlistId, index: 0)
        if let stored = try? await repository.episode(byEnclosureURL: episode.enclosureUrl ?? "") {
            row = stored
        }
        return row
    }
}

/// Replays a kept moment: the episode starts at the moment's position, the
/// same seek a transcript line's "Play from here" makes.
@MainActor
enum MomentPlayback {

    static func play(_ moment: Moment, context: UIContext) async {
        let position = Int64(max(0, moment.startMilliseconds))
        // Already the current episode: just move within it.
        if context.playback.currentEpisode?.enclosureUrl == moment.enclosureURL {
            await context.playback.seek(position)
            return
        }
        let playlistId = ChannelPlaylistLogic.defaultPlaylistID
        var row = PlaylistEpisodeRow(
            title: moment.episodeTitle,
            enclosureUrl: moment.enclosureURL,
            imageUrl: moment.artworkURL,
            channelTitle: moment.showTitle,
            rssFeedUrl: moment.rssFeedURL,
            playlistId: playlistId
        )
        let repository = context.database.playlistRepository()
        try? await repository.insertOrUpdateByIndex(row, playlistId: playlistId, index: 0)
        if let stored = try? await repository.episode(byEnclosureURL: moment.enclosureURL) {
            row = stored
        }
        row.playedDuration = position
        await context.playback.playByEpisode(row)
    }
}
