import UIKit
import Foundation
import Testing
import AnycastKit
@testable import Anycast

/// Inbox card action ordering (feeds.dart:84-131, 05 §6.3 P0 "Inbox three buttons"):
/// play = insert-top → play → leave inbox; add = insert (durable FIRST — a
/// kill in the removal/fly window must leave the episode in the playlist)
/// → row leaves the inbox (animated collapse) → fly-in 600 ms; remove =
/// leave inbox. The Dart flow ran the fly-in before everything else
/// (feeds.dart:104-128); the native port reorders so the row visually
/// "becomes a ball and jumps into the playlist" instead of lingering
/// through the whole animation.
@MainActor
struct FeedsInboxActionTests {

    private let playlistURL = "https://example.com/feed.mp3"
    private let playingURL = "https://example.com/playing.mp3"

    // MARK: - Play

    @Test("Play: insert at top, play, then leave the inbox")
    func playOrder() {
        let steps = InboxActionPlanner.steps(
            for: .play,
            currentPlaylistId: 1,
            currentEnclosureURL: playingURL,
            episodeEnclosureURL: playlistURL
        )
        #expect(steps == [
            .insertIntoPlaylist(0),
            .playInsertedEpisode,
            .removeFromInbox,
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
        #expect(steps == [.insertIntoPlaylist(0), .playInsertedEpisode, .removeFromInbox])
    }

    // MARK: - Add to playlist

    @Test("Add: insert commits first, then the row animates away, then the fly-in")
    func addInsertsThenRemovesThenFlies() {
        let steps = InboxActionPlanner.steps(
            for: .addToPlaylist,
            currentPlaylistId: nil,
            currentEnclosureURL: nil,
            episodeEnclosureURL: playlistURL
        )
        #expect(steps == [
            .insertIntoPlaylist(0),
            .removeFromInbox,
            .flyInAnimation,
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
            .insertIntoPlaylist(1),
            .reloadPlaybackQueue,
            .removeFromInbox,
            .flyInAnimation,
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
            .skipInsertCurrentlyPlaying,
            .removeFromInbox,
            .flyInAnimation,
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
            .insertIntoPlaylist(0),
            .removeFromInbox,
            .flyInAnimation,
        ])
    }

    @Test("Kill-window safety: whenever the add inserts, the insert precedes the inbox removal")
    func addInsertAlwaysPrecedesInboxRemoval() {
        // Every variant that performs an insert must commit it before the
        // row leaves the inbox — a process kill inside the removal/fly
        // animation window then leaves the episode safely in the playlist
        // instead of lost from both tables.
        let variants: [(Int64?, String?)] = [
            (nil, nil),                       // nothing playing
            (1, playingURL),                  // default playlist, other episode
            (1, playlistURL),                 // currently playing (skip branch)
            (2, playingURL),                  // other playlist current
        ]
        for (playlistId, playing) in variants {
            let steps = InboxActionPlanner.steps(
                for: .addToPlaylist,
                currentPlaylistId: playlistId,
                currentEnclosureURL: playing,
                episodeEnclosureURL: playlistURL
            )
            let insertIndex = steps.firstIndex {
                if case .insertIntoPlaylist = $0 { return true }
                return false
            }
            let removeIndex = steps.firstIndex(of: .removeFromInbox)
            #expect(removeIndex != nil, "add must always leave the inbox (\(steps))")
            if let insertIndex, let removeIndex {
                #expect(insertIndex < removeIndex,
                        "insert must precede the inbox removal (\(steps))")
            }
            // The visual sequence is unaffected: removal immediately
            // precedes the fly-in in every variant.
            if let removeIndex {
                #expect(steps.count > removeIndex + 1 && steps[removeIndex + 1] == .flyInAnimation,
                        "removal must be followed by the fly-in (\(steps))")
            }
        }
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

    @Test("Fly-in starts at the Add circle in window coordinates; Detail and vanished rows never fly")
    func flyInOriginUsesAddCircle() throws {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 402, height: 874))
        let host = UIViewController()
        window.rootViewController = host
        let layout = UICollectionViewFlowLayout()
        layout.itemSize = CGSize(width: 370, height: 112)
        layout.minimumLineSpacing = 12
        let collection = UICollectionView(frame: window.bounds, collectionViewLayout: layout)
        let source = SimpleCollectionDataSource(count: 10)
        collection.dataSource = source
        collection.register(UICollectionViewCell.self, forCellWithReuseIdentifier: "cell")
        host.view.addSubview(collection)
        window.layoutIfNeeded()
        collection.layoutIfNeeded()
        collection.contentOffset.y = 120
        let group = ListActionGroupView(items: [
            ListActionItem(id: "play", content: .icon(AppIcons.play), accessibilityLabel: "Play", handler: {}),
            ListActionItem(id: "add", content: .icon(AppIcons.addToList), accessibilityLabel: "Add", handler: {}),
            ListActionItem(id: "remove", content: .icon(AppIcons.remove), accessibilityLabel: "Remove", handler: {}),
            ListActionItem(id: "details", content: .title("Details"), accessibilityLabel: "Details", handler: {}),
        ])
        group.frame = CGRect(x: 16, y: 300, width: 370, height: 56)
        collection.addSubview(group)
        group.layoutIfNeeded()
        let add = try #require(group.button(for: "add"))
        let expected = add.convert(CGPoint(x: add.bounds.midX, y: add.bounds.midY), to: window)
        let path = IndexPath(item: 1, section: 0)
        let origin = try #require(InboxPageViewController.resolvedFlyInStart(
            actionPath: path, identityPath: path, in: collection, window: window, addCircle: add
        ))
        #expect(abs(origin.x - expected.x) <= 0.5 && abs(origin.y - expected.y) <= 0.5)
        #expect(abs(origin.x - window.bounds.midX) > 20, "circle origin must not fall back to row center")
        #expect(collection.contentOffset.y > 0, "coordinate conversion must include scrolling")
        #expect(InboxPageViewController.resolvedFlyInStart(
            actionPath: nil, identityPath: path, in: collection, window: window, addCircle: add
        ) == nil)
        #expect(InboxPageViewController.resolvedFlyInStart(
            actionPath: path, identityPath: nil, in: collection, window: window, addCircle: add
        ) == nil)
        // A context-menu/VoiceOver action without an open group retains the
        // existing row-origin flight; only Detail suppresses it completely.
        #expect(InboxPageViewController.resolvedFlyInStart(
            actionPath: path, identityPath: path, in: collection, window: window
        ) != nil)
    }
}

/// Minimal host for the fly-in origin test: plain fixed-size cells.
@MainActor
private final class SimpleCollectionDataSource: NSObject, UICollectionViewDataSource {

    private let count: Int

    init(count: Int) { self.count = count }

    func collectionView(
        _ collectionView: UICollectionView, numberOfItemsInSection section: Int
    ) -> Int { count }

    func collectionView(
        _ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath
    ) -> UICollectionViewCell {
        collectionView.dequeueReusableCell(withReuseIdentifier: "cell", for: indexPath)
    }
}
