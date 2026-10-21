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

    // MARK: - Fly-in origin (swipe displacement)

    /// The full leading swipe displaces the row toward the trailing edge,
    /// and on device BOTH the cell and its layout attributes report the
    /// displaced position at action time — the ball visibly launched from
    /// the screen's right edge across two fix attempts. The origin's X
    /// must therefore never come from the item: it is the collection
    /// view's horizontal center BY CONSTRUCTION, with only the row's Y
    /// taken from the item (list swipes translate horizontally only).
    /// The hosted layout (`DisplacingFlowLayout`) shifts every item's
    /// attributes horizontally to simulate the device behavior, and the
    /// live cell is transformed on top of it; the list is scrolled to a
    /// non-zero offset so the collectionView→window conversion is
    /// load-bearing. Also pins `perform`'s decision at its own entry: the
    /// Detail sheet (nil action path) never flies, and a list action
    /// whose row already left the list drops the flight.
    @Test("Fly-in origin X is the collection's center regardless of swipe displacement")
    func flyInOriginIgnoresSwipeDisplacement() throws {
        // Never shown or made key: layout and coordinate conversion are pure
        // geometry, and parallel live-shell suites own the key window.
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 402, height: 874))
        let host = UIViewController()
        window.rootViewController = host

        let layout = DisplacingFlowLayout()
        layout.itemSize = CGSize(width: 402, height: 112)
        layout.minimumLineSpacing = 12
        let collectionView = UICollectionView(
            frame: CGRect(x: 0, y: 0, width: 402, height: 874), collectionViewLayout: layout
        )
        // Enough rows that a contentOffset actually sticks.
        let dataSource = SimpleCollectionDataSource(count: 10)
        collectionView.dataSource = dataSource
        collectionView.register(
            UICollectionViewCell.self, forCellWithReuseIdentifier: "cell"
        )
        host.view.addSubview(collectionView)
        window.layoutIfNeeded()
        collectionView.layoutIfNeeded()
        // Scroll the list: from here on, collection coordinates and window
        // coordinates differ by a real offset.
        collectionView.contentOffset = CGPoint(x: 0, y: 120)
        collectionView.layoutIfNeeded()

        let path = IndexPath(item: 1, section: 0)
        guard let attributes = collectionView.layoutAttributesForItem(at: path),
              let cell = collectionView.cellForItem(at: path) else {
            Issue.record("hosted list did not materialize its cells"); return
        }
        let collectionCenterX = collectionView.convert(collectionView.bounds, to: window).midX
        // The displacing layout must actually be displacing: the item's
        // attributes sit far from the full-width row's resting center.
        #expect(abs(attributes.frame.midX - collectionCenterX) > 200,
                "displacing layout setup is degenerate (attributes midX \(attributes.frame.midX), center \(collectionCenterX))")
        // The row's Y in window coordinates (the displacing layout only
        // shifts X, matching a horizontal swipe).
        let rowMidY = collectionView.convert(CGPoint(x: 0, y: attributes.frame.midY), to: window).y
        #expect(collectionView.contentOffset.y > 0,
                "contentOffset did not stick (\(collectionView.contentOffset)) — the conversion probe is vacuous")

        // The displacing layout displaces BOTH layers — the cells' frames
        // come from the same shifted attributes — so neither the queried
        // attributes nor the live cell marks the row's X.
        let displacedCellCenter = cell.convert(
            CGPoint(x: cell.bounds.midX, y: cell.bounds.midY), to: window
        )
        #expect(abs(displacedCellCenter.x - collectionCenterX) > 200,
                "displacement setup is degenerate (displaced cell \(displacedCellCenter.x), center \(collectionCenterX))")

        let origin = InboxPageViewController.flyInOrigin(
            in: collectionView, at: path, window: window
        )
        #expect(origin != nil, "fly-in origin resolved to nil for a visible item")
        guard let origin else { return }
        #expect(abs(origin.x - collectionCenterX) < 0.5 && abs(origin.y - rowMidY) < 0.5,
                "fly-in origin \(origin) is not (collection center X \(collectionCenterX), row Y \(rowMidY))")

        // perform()'s own decision (resolvedFlyInStart): the Detail sheet
        // passes a nil action path and must NEVER fly — even though the
        // episode is still resolvable in the list behind the sheet (the
        // regression this pins: a Detail add ran the whole ball flight
        // over the dismissing sheet).
        #expect(InboxPageViewController.resolvedFlyInStart(
            actionPath: nil, identityPath: path, in: collectionView, window: window
        ) == nil, "a Detail-sheet action (nil action path) resolved a fly-in start")
        // A list action whose row already left the list (nil identity path
        // — trim/refresh raced the menu) drops the flight instead of
        // resolving a stale, possibly out-of-range path.
        #expect(InboxPageViewController.resolvedFlyInStart(
            actionPath: path, identityPath: nil, in: collectionView, window: window
        ) == nil, "a vanished row (nil identity path) resolved a fly-in start")
        // The healthy list path resolves to the same displacement-proof point.
        let resolved = InboxPageViewController.resolvedFlyInStart(
            actionPath: path, identityPath: path, in: collectionView, window: window
        )
        #expect(resolved != nil
                && abs(resolved!.x - collectionCenterX) < 0.5
                && abs(resolved!.y - rowMidY) < 0.5,
                "the list-path resolution \(String(describing: resolved)) is not (collection center X \(collectionCenterX), row Y \(rowMidY))")
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

/// Flow layout whose item attributes are shifted horizontally — the hosted
/// stand-in for the device behavior where a full swipe displaces BOTH the
/// cell and its layout attributes toward the trailing edge. The shift must
/// live in `layoutAttributesForElements` too: `UICollectionView`'s public
/// single-item query reads its internal attributes cache, which is filled
/// from the elements pass — an `layoutAttributesForItem`-only override is
/// invisible to that query (verified empirically). Every attribute is
/// copied before mutation; flow layout hands out cached instances.
@MainActor
private final class DisplacingFlowLayout: UICollectionViewFlowLayout {

    private static func displaced(
        _ attributes: UICollectionViewLayoutAttributes
    ) -> UICollectionViewLayoutAttributes {
        attributes.frame.origin.x += 300
        return attributes
    }

    private static func displacedCopy(
        of attributes: UICollectionViewLayoutAttributes
    ) -> UICollectionViewLayoutAttributes {
        guard let copy = attributes.copy() as? UICollectionViewLayoutAttributes else {
            return attributes
        }
        return displaced(copy)
    }

    override func layoutAttributesForElements(in rect: CGRect) -> [UICollectionViewLayoutAttributes]? {
        super.layoutAttributesForElements(in: rect)?.map(Self.displacedCopy)
    }

    override func layoutAttributesForItem(at indexPath: IndexPath) -> UICollectionViewLayoutAttributes? {
        super.layoutAttributesForItem(at: indexPath).map(Self.displacedCopy)
    }
}
