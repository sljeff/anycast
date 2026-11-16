import UIKit
import Testing
import AnycastKit
@testable import Anycast

/// Merged Remove + Undo on the real Playlist wiring: one capsule updated in
/// place, rows leaving at tap time, the playing episode stopping with the
/// next one loaded paused, and Undo restoring order, progress and the paused
/// current episode.
@Suite(.serialized)
@MainActor
struct PlaylistBatchRemoveTests {

    private typealias Host = PlaylistActionGroupTests.Host

    private static func descendants(_ view: UIView) -> [UIView] {
        view.subviews.flatMap { [$0] + descendants($0) }
    }

    private static func capsules(in window: UIWindow) -> [UIView] {
        descendants(window).filter { $0.accessibilityIdentifier == "playlist-removal-capsule" }
    }

    private static func capsuleText(in window: UIWindow) -> String? {
        capsules(in: window).first.flatMap { descendants($0).compactMap { ($0 as? UILabel)?.text }.first }
    }

    private static func undoButton(in window: UIWindow) -> UIControl? {
        descendants(window).first { $0.accessibilityIdentifier == "playlist-removal-undo" } as? UIControl
    }

    private static func waitUntil(_ condition: () async -> Bool) async {
        for _ in 0..<300 {
            if await condition() { return }
            try? await Task.sleep(for: .milliseconds(20))
        }
    }

    private static func storedURLs(_ host: Host) async -> [String] {
        ((try? await host.context.database.playlistRepository().listEpisodes(playlistId: 1)) ?? [])
            .compactMap(\.enclosureUrl)
    }

    @Test("rapid removes show one capsule that counts up in place; Undo restores every row in order")
    func mergedCapsuleAndUndo() async throws {
        let host = try await Host.make(count: 12)
        defer { host.close() }
        let original = (0..<12).map(host.url)
        try host.cell(2).onCardTap?()
        try await host.settle()
        host.group.button(for: "remove")?.sendActions(for: .touchUpInside)
        #expect(Self.capsuleText(in: host.window) == "Removed")
        let calls = host.list.snapshotApplyCount
        for _ in 0..<2 {
            host.group.button(for: "remove")?.sendActions(for: .touchUpInside)
        }
        #expect(host.list.snapshotApplyCount == calls + 2, "each removal applies one snapshot")
        #expect(Self.capsules(in: host.window).count == 1, "the capsule is updated, not re-presented")
        #expect(Self.capsuleText(in: host.window) == "Removed 3 episodes")
        #expect(host.list.visibleCount == 9)
        // Nothing was deleted yet.
        #expect(await Self.storedURLs(host) == original)

        Self.undoButton(in: host.window)?.sendActions(for: .touchUpInside)
        await Self.waitUntil { host.list.visibleCount == 12 }
        #expect(host.list.episodes.compactMap(\.enclosureUrl) == original)
        #expect(await Self.storedURLs(host) == original)
        #expect(Self.capsules(in: host.window).isEmpty)
    }

    @Test("removing 3 rows including the playing head: one capsule, the next episode loads paused, Undo restores order, progress and the paused head")
    func playingHeadBatch() async throws {
        let host = try await Host.make(count: 12)
        defer { host.close() }
        let original = (0..<12).map(host.url)
        let repository = host.context.database.playlistRepository()
        let playback = host.context.playback
        try await repository.updatePlayedDuration(42_000, byEnclosureURL: host.url(0))
        let head = try #require(try await repository.episode(byEnclosureURL: host.url(0)))
        await playback.setByEpisode(head)
        await playback.reloadQueue()
        #expect(playback.currentEpisode?.enclosureUrl == host.url(0))
        let rows = host.list.episodes

        host.list.binder.removeTapped(rows[3])
        host.list.binder.removeTapped(rows[5])
        host.list.binder.removeTapped(rows[0])
        // UI first: the cards are gone before any write finished.
        #expect(host.list.visibleCount == 9)
        #expect(Self.capsules(in: host.window).count == 1)
        #expect(Self.capsuleText(in: host.window) == "Removed 3 episodes")

        await host.list.binder.settleEagerRemovals()
        let remaining = original.filter { ![host.url(0), host.url(3), host.url(5)].contains($0) }
        #expect(await Self.storedURLs(host) == remaining)
        // Stop and load the next episode, paused.
        #expect(playback.currentEpisode?.enclosureUrl == host.url(1))
        #expect(playback.queueEnclosureURLs.first == host.url(1))
        #expect(playback.isPlaying == false)
        // The player's own change does not commit the batch.
        try await Task.sleep(for: .milliseconds(300))
        #expect(Self.capsuleText(in: host.window) == "Removed 3 episodes")

        Self.undoButton(in: host.window)?.sendActions(for: .touchUpInside)
        await Self.waitUntil { await Self.storedURLs(host) == original && playback.currentEpisode?.enclosureUrl == host.url(0) }
        #expect(await Self.storedURLs(host) == original)
        #expect(playback.currentEpisode?.enclosureUrl == host.url(0))
        #expect(playback.queueEnclosureURLs == original)
        #expect(playback.positionData.positionMilliseconds == 42_000)
        #expect(playback.isPlaying == false)
        let restored = try await repository.episode(byEnclosureURL: host.url(0))
        #expect(restored?.playedDuration == 42_000)
        await Self.waitUntil { host.list.visibleCount == 12 }
        #expect(host.list.episodes.compactMap(\.enclosureUrl) == original)
    }

    @Test("head, then the next two fillers in quick succession: the player ends on the fourth episode, paused, and Undo restores the head")
    func headThenFillers() async throws {
        let host = try await Host.make(count: 12)
        defer { host.close() }
        let original = (0..<12).map(host.url)
        let repository = host.context.database.playlistRepository()
        let playback = host.context.playback
        try await repository.updatePlayedDuration(42_000, byEnclosureURL: host.url(0))
        let head = try #require(try await repository.episode(byEnclosureURL: host.url(0)))
        await playback.setByEpisode(head)
        await playback.reloadQueue()
        let rows = host.list.episodes

        host.list.binder.removeTapped(rows[0])
        host.list.binder.removeTapped(rows[1])
        host.list.binder.removeTapped(rows[2])
        await host.list.binder.settleEagerRemovals()

        #expect(await Self.storedURLs(host) == Array(original.dropFirst(3)))
        #expect(playback.currentEpisode?.enclosureUrl == host.url(3))
        #expect(playback.queueEnclosureURLs.first == host.url(3))
        #expect(playback.isPlaying == false)
        #expect(!host.list.binder.hiddenEpisodeURLs.contains(host.url(3)))
        try await Task.sleep(for: .milliseconds(300))
        #expect(Self.capsuleText(in: host.window) == "Removed 3 episodes")

        Self.undoButton(in: host.window)?.sendActions(for: .touchUpInside)
        await Self.waitUntil { await Self.storedURLs(host) == original && playback.currentEpisode?.enclosureUrl == host.url(0) }
        #expect(await Self.storedURLs(host) == original)
        #expect(playback.currentEpisode?.enclosureUrl == host.url(0))
        #expect(playback.queueEnclosureURLs == original)
        #expect(playback.positionData.positionMilliseconds == 42_000)
        #expect(playback.isPlaying == false)
        await Self.waitUntil { host.list.visibleCount == 12 }
        #expect(host.list.episodes.compactMap(\.enclosureUrl) == original)
    }

    @Test("removing the open current head via its own group, then Undo: the card returns to the list")
    func openHeadRemoveThenUndoShowsCard() async throws {
        let host = try await Host.make(count: 12)
        defer { host.close() }
        let original = (0..<12).map(host.url)
        let repository = host.context.database.playlistRepository()
        let playback = host.context.playback
        let head = try #require(try await repository.episode(byEnclosureURL: host.url(0)))
        await playback.setByEpisode(head)
        await playback.reloadQueue()
        try host.cell(0).onCardTap?()
        try await host.settle()
        host.group.button(for: "remove")?.sendActions(for: .touchUpInside)
        await Self.waitUntil { playback.currentEpisode?.enclosureUrl == host.url(1) }
        await host.list.binder.settleEagerRemovals()
        #expect(host.list.visibleCount == 11)
        try await Task.sleep(for: .milliseconds(300))
        #expect(host.list.visibleCount == 11)

        Self.undoButton(in: host.window)?.sendActions(for: .touchUpInside)
        await Self.waitUntil { host.list.visibleCount == 12 }
        try await Task.sleep(for: .milliseconds(500))
        #expect(await Self.storedURLs(host) == original)
        #expect(playback.currentEpisode?.enclosureUrl == host.url(0))
        #expect(host.list.binder.hiddenEpisodeURLs.isEmpty)
        #expect(host.list.episodes.compactMap(\.enclosureUrl) == original)
        // The restored card must be on screen, not parked above the viewport.
        let cv = try #require(host.list.edgeScrollView as? UICollectionView)
        cv.layoutIfNeeded()
        let frame = try #require(cv.layoutAttributesForItem(at: IndexPath(item: 0, section: 0))?.frame)
        let visibleTop = cv.contentOffset.y + cv.adjustedContentInset.top
        #expect(frame.minY >= visibleTop - 1, "restored head card is scrolled out above the viewport: minY \(frame.minY) top \(visibleTop) offset \(cv.contentOffset.y) inset \(cv.adjustedContentInset.top)")
    }

    @Test("a committed batch deletes the deferred rows once and drops the capsule")
    func commitDeletesDeferred() async throws {
        let host = try await Host.make(count: 8)
        defer { host.close() }
        let rows = host.list.episodes
        host.list.binder.removeTapped(rows[4])
        host.list.binder.removeTapped(rows[6])
        #expect(await Self.storedURLs(host).count == 8)

        await host.list.binder.commitPendingRemoval()
        #expect(await Self.storedURLs(host) == (0..<8).filter { $0 != 4 && $0 != 6 }.map(host.url))
        await Self.waitUntil { Self.capsules(in: host.window).isEmpty }
        #expect(Self.capsules(in: host.window).isEmpty)
    }
}
