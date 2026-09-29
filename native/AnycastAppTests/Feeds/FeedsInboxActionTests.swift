import Foundation
import Testing
import AnycastKit
@testable import Anycast

/// Inbox card action ordering (feeds.dart:84-131, 05 §6.3 P0 "Inbox three buttons"):
/// play = insert-top → leave inbox → play; add = fly-in 600 ms FIRST →
/// insert (addToPlaylist slot rules) → leave inbox; remove = leave inbox.
@MainActor
struct FeedsInboxActionTests {

    private let playlistURL = "https://example.com/feed.mp3"
    private let playingURL = "https://example.com/playing.mp3"

    // MARK: - Play

    @Test("Play: insert at top, leave inbox, then play")
    func playOrder() {
        let steps = InboxActionPlanner.steps(
            for: .play,
            currentPlaylistId: 1,
            currentEnclosureURL: playingURL,
            episodeEnclosureURL: playlistURL
        )
        #expect(steps == [
            .insertIntoPlaylist(0),
            .removeFromInbox,
            .playInsertedEpisode,
        ])
    }

    @Test("Play keeps its order even with nothing playing anywhere")
    func playOrderNoPlayback() {
        let steps = InboxActionPlanner.steps(
            for: .play,
            currentPlaylistId: nil,
            currentEnclosureURL: nil,
            episodeEnclosureURL: playlistURL
        )
        #expect(steps == [.insertIntoPlaylist(0), .removeFromInbox, .playInsertedEpisode])
    }

    // MARK: - Add to playlist

    @Test("Add: fly-in animation precedes the insert (600 ms, then commit)")
    func addFlyInFirst() {
        let steps = InboxActionPlanner.steps(
            for: .addToPlaylist,
            currentPlaylistId: nil,
            currentEnclosureURL: nil,
            episodeEnclosureURL: playlistURL
        )
        #expect(steps.first == .flyInAnimation)
        #expect(steps == [
            .flyInAnimation,
            .insertIntoPlaylist(0),
            .removeFromInbox,
        ])
    }

    @Test("Add while the default playlist plays a DIFFERENT episode inserts below the queue head")
    func addBelowQueueHead() {
        let steps = InboxActionPlanner.steps(
            for: .addToPlaylist,
            currentPlaylistId: 1,
            currentEnclosureURL: playingURL,
            episodeEnclosureURL: playlistURL
        )
        #expect(steps == [
            .flyInAnimation,
            .insertIntoPlaylist(1),
            .reloadPlaybackQueue,
            .removeFromInbox,
        ])
    }

    @Test("Add of the CURRENTLY PLAYING episode is a no-op insert but still leaves the inbox")
    func addCurrentlyPlaying() {
        let steps = InboxActionPlanner.steps(
            for: .addToPlaylist,
            currentPlaylistId: 1,
            currentEnclosureURL: playlistURL,
            episodeEnclosureURL: playlistURL
        )
        #expect(steps == [
            .flyInAnimation,
            .skipInsertCurrentlyPlaying,
            .removeFromInbox,
        ])
    }

    @Test("Add while ANOTHER playlist plays: top insert, no queue reload")
    func addOtherPlaylistCurrent() {
        let steps = InboxActionPlanner.steps(
            for: .addToPlaylist,
            currentPlaylistId: 2,
            currentEnclosureURL: playingURL,
            episodeEnclosureURL: playlistURL
        )
        #expect(steps == [
            .flyInAnimation,
            .insertIntoPlaylist(0),
            .removeFromInbox,
        ])
    }

    // MARK: - Remove

    @Test("Remove only leaves the inbox")
    func removeOnly() {
        let steps = InboxActionPlanner.steps(
            for: .remove,
            currentPlaylistId: 1,
            currentEnclosureURL: playingURL,
            episodeEnclosureURL: playlistURL
        )
        #expect(steps == [.removeFromInbox])
    }

    // MARK: - Slot rules parity (addToPlaylist, feed_episode.dart:87-100)

    @Test("Insert slot rules match addToPlaylistIndex")
    func slotRules() {
        // Default playlist current + this episode playing → nil.
        #expect(ChannelPlaylistLogic.addToPlaylistIndex(
            currentPlaylistId: 1, targetPlaylistId: 1,
            currentEnclosureURL: playlistURL, episodeEnclosureURL: playlistURL
        ) == nil)
        // Default playlist current + different episode → 1.
        #expect(ChannelPlaylistLogic.addToPlaylistIndex(
            currentPlaylistId: 1, targetPlaylistId: 1,
            currentEnclosureURL: playingURL, episodeEnclosureURL: playlistURL
        ) == 1)
        // No current playlist → 0.
        #expect(ChannelPlaylistLogic.addToPlaylistIndex(
            currentPlaylistId: nil, targetPlaylistId: 1,
            currentEnclosureURL: nil, episodeEnclosureURL: playlistURL
        ) == 0)
        // Other playlist current → 0.
        #expect(ChannelPlaylistLogic.addToPlaylistIndex(
            currentPlaylistId: 2, targetPlaylistId: 1,
            currentEnclosureURL: playingURL, episodeEnclosureURL: playlistURL
        ) == 0)
        // Empty current enclosure URL degrades to slot 1 (no current episode).
        #expect(ChannelPlaylistLogic.addToPlaylistIndex(
            currentPlaylistId: 1, targetPlaylistId: 1,
            currentEnclosureURL: "", episodeEnclosureURL: playlistURL
        ) == 1)
    }

    // MARK: - feed2playlist field parity

    @Test("feed2playlist copies every episode field and resets progress")
    func playlistRowMapping() {
        let episode = FeedEpisodeRow(
            title: "T", description: "D", duration: 1234,
            enclosureUrl: playlistURL, pubDate: 5678,
            imageUrl: "img", channelTitle: "C", rssFeedUrl: "rss"
        )
        let row = ChannelPlaylistLogic.playlistRow(from: episode, playlistId: 1)
        #expect(row.title == "T")
        #expect(row.description == "D")
        #expect(row.duration == 1234)
        #expect(row.enclosureUrl == playlistURL)
        #expect(row.pubDate == 5678)
        #expect(row.imageUrl == "img")
        #expect(row.channelTitle == "C")
        #expect(row.rssFeedUrl == "rss")
        #expect(row.playlistId == 1)
        #expect(row.playedDuration == 0)
    }
}
