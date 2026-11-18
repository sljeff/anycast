import Foundation
import Testing
import AnycastKit
@testable import Anycast

/// Playlist Remove defers its DB delete for the Undo window (or, for a row
/// the player may reach, deletes at once and re-inserts on Undo); removals
/// merge into one batch. Real SQLite in a temporary file.
@MainActor
struct PlaylistRemovalUndoTests {

    private struct Fixture {
        let database: AppDatabase
        let url: URL

        func storedURLs() async -> [String] {
            let rows = (try? await database.playlistRepository().listEpisodes(playlistId: 1)) ?? []
            return rows.compactMap(\.enclosureUrl)
        }

        func cleanUp() { try? FileManager.default.removeItem(at: url) }
    }

    private static let urls = (1...4).map { "https://example.test/queue-\($0).mp3" }

    private static func makeFixture() async throws -> Fixture {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("playlist-removal-\(UUID().uuidString).sqlite")
        let database = try await AppDatabase.openAt(url, localeIdentifier: "en_US")
        for (index, enclosure) in urls.enumerated() {
            let row = PlaylistEpisodeRow(
                title: "Episode \(index + 1)", enclosureUrl: enclosure,
                playlistId: 1, playedDuration: Int64(index + 1) * 10_000
            )
            try await database.playlistRepository().insertOrUpdateByIndex(row, playlistId: 1, index: index)
        }
        return Fixture(database: database, url: url)
    }

    private enum Kind { case remove }

    @Test("deferred removes merge; the rows stay stored until the one commit, which deletes once")
    func rowsSurviveUntilCommit() async throws {
        let fixture = try await Self.makeFixture()
        defer { fixture.cleanUp() }
        let repository = fixture.database.playlistRepository()
        let targets = [Self.urls[2], Self.urls[3]]
        let batch = PendingBatch<Kind, String>(window: .seconds(60), center: NotificationCenter())
        var commits = 0

        for target in targets {
            batch.add(target, kind: .remove) { urls in
                commits += 1
                for url in urls { try? await repository.removeEpisode(byEnclosureURL: url) }
            }
        }
        let stored = (try await repository.listEpisodes(playlistId: 1))
        #expect(stored.compactMap(\.enclosureUrl) == Self.urls)
        #expect(PlaylistRemovalLogic.displayed(stored, excluding: Set(targets)).compactMap(\.enclosureUrl)
            == [Self.urls[0], Self.urls[1]])

        await batch.commitNow()
        await batch.commitNow()
        #expect(commits == 1)
        #expect(await fixture.storedURLs() == [Self.urls[0], Self.urls[1]])
    }

    @Test("undoing deferred removes writes nothing and keeps every index")
    func undoKeepsIndex() async throws {
        let fixture = try await Self.makeFixture()
        defer { fixture.cleanUp() }
        let repository = fixture.database.playlistRepository()
        let batch = PendingBatch<Kind, String>(window: .milliseconds(80), center: NotificationCenter())
        for target in [Self.urls[2], Self.urls[1]] {
            batch.add(target, kind: .remove) { urls in
                for url in urls { try? await repository.removeEpisode(byEnclosureURL: url) }
            }
        }

        #expect(batch.undo()?.items == [Self.urls[1], Self.urls[2]])
        try await Task.sleep(for: .milliseconds(250))
        #expect(await fixture.storedURLs() == Self.urls)
    }

    @Test("eager rows deleted in order come back in reverse: the head and a mid row restore the exact queue")
    func eagerBatchUndoRestoresOrder() async throws {
        let fixture = try await Self.makeFixture()
        defer { fixture.cleanUp() }
        let repository = fixture.database.playlistRepository()
        var snapshots: [(row: PlaylistEpisodeRow, index: Int)] = []
        // Delete order: a mid row, then the head, then the new head.
        for url in [Self.urls[2], Self.urls[0], Self.urls[1]] {
            snapshots.append(try #require(await PlaylistRemovalLogic.snapshot(
                url: url, playlistId: 1, repository: repository
            )))
            try await repository.removeEpisode(byEnclosureURL: url)
        }
        #expect(await fixture.storedURLs() == [Self.urls[3]])

        for snapshot in snapshots.reversed() {
            try await PlaylistRemovalLogic.reinsert(snapshot.row, at: snapshot.index, playlistId: 1, repository: repository)
        }
        let rows = try await repository.listEpisodes(playlistId: 1)
        #expect(rows.compactMap(\.enclosureUrl) == Self.urls)
        #expect(rows.map(\.playedDuration) == [10_000, 20_000, 30_000, 40_000])
    }

    @Test("undoing an eager remove re-inserts the row at its index with its columns")
    func eagerUndoReinserts() async throws {
        let fixture = try await Self.makeFixture()
        defer { fixture.cleanUp() }
        let repository = fixture.database.playlistRepository()
        let target = Self.urls[0]

        let snapshot = try #require(await PlaylistRemovalLogic.snapshot(
            url: target, playlistId: 1, repository: repository
        ))
        #expect(snapshot.index == 0)
        try await repository.removeEpisode(byEnclosureURL: target)
        #expect(await fixture.storedURLs() == Array(Self.urls.dropFirst()))

        try await PlaylistRemovalLogic.reinsert(snapshot.row, at: snapshot.index, playlistId: 1, repository: repository)
        let rows = try await repository.listEpisodes(playlistId: 1)
        #expect(rows.compactMap(\.enclosureUrl) == Self.urls)
        #expect(rows[0].playedDuration == 10_000)
        #expect(rows[0].title == "Episode 1")
    }

    @Test("a mid-queue eager row is re-inserted in the middle")
    func eagerUndoMiddle() async throws {
        let fixture = try await Self.makeFixture()
        defer { fixture.cleanUp() }
        let repository = fixture.database.playlistRepository()
        let snapshot = try #require(await PlaylistRemovalLogic.snapshot(
            url: Self.urls[1], playlistId: 1, repository: repository
        ))
        try await repository.removeEpisode(byEnclosureURL: Self.urls[1])
        try await PlaylistRemovalLogic.reinsert(snapshot.row, at: snapshot.index, playlistId: 1, repository: repository)
        #expect(await fixture.storedURLs() == Self.urls)
    }

    @Test("playing and next-in-queue rows are removed eagerly, later rows deferred")
    func eagerDecision() {
        let queue = Self.urls
        func eager(_ url: String, current: Bool = false, playing: Int64? = 1) -> Bool {
            PlaylistRemovalLogic.isEager(
                url: url, wasCurrent: current, playlistId: 1, playingPlaylistId: playing, queueURLs: queue
            )
        }
        #expect(eager(queue[0], current: true))
        #expect(eager(queue[1]))
        #expect(!eager(queue[2]))
        #expect(!eager(queue[1], playing: nil))
        #expect(!eager(queue[1], playing: 2))
    }

    @Test("a change of the playing episode commits pending deferred removals")
    func trackChangeCommits() {
        let commit = PlaylistRemovalLogic.shouldCommitOnTrackChange
        #expect(commit(["a"], "x", "y"))
        #expect(commit(["a", "b"], "x", nil))
        #expect(!commit(["a"], "x", "x"))
        #expect(!commit([], "x", "y"))
    }

    // MARK: - Restore targets while playback moved

    @Test("the restore target keeps index 0 only when playback never moved")
    func restoreTargetIndexRule() {
        #expect(PlaylistRemovalLogic.restoreTargetIndex(storedIndex: 0, playbackMoved: false) == 0)
        #expect(PlaylistRemovalLogic.restoreTargetIndex(storedIndex: 2, playbackMoved: false) == 2)
        #expect(PlaylistRemovalLogic.restoreTargetIndex(storedIndex: 0, playbackMoved: true) == 1)
        #expect(PlaylistRemovalLogic.restoreTargetIndex(storedIndex: 2, playbackMoved: true) == 2)
    }

    /// The two-heads scenario: queue [A, B, C], A playing. Remove A (B
    /// takes over), remove B (C takes over), then play C from the mini
    /// player. Undo restores A and B behind the playing C, keeping their
    /// original relative order — C stays the queue head, so a head
    /// completion still finds `currentEpisode == queue.first`.
    @Test("undo after two head removals keeps the playing episode at the head")
    func undoKeepsPlayingHead() async throws {
        let fixture = try await Self.makeFixture()
        defer { fixture.cleanUp() }
        let repository = fixture.database.playlistRepository()

        // Remove A, then B, snapshotting each right before its delete
        // (both store index 0 — the eager-removal convention).
        var snapshots: [(row: PlaylistEpisodeRow, index: Int)] = []
        for url in [Self.urls[0], Self.urls[1]] {
            snapshots.append(try #require(await PlaylistRemovalLogic.snapshot(
                url: url, playlistId: 1, repository: repository
            )))
            try await repository.removeEpisode(byEnclosureURL: url)
        }
        #expect(await fixture.storedURLs() == [Self.urls[2], Self.urls[3]])

        // Playback moved (C is playing): the binder re-inserts newest
        // first, each at the restore target.
        let playbackMoved = true
        for snapshot in snapshots.reversed() {
            let target = PlaylistRemovalLogic.restoreTargetIndex(
                storedIndex: snapshot.index, playbackMoved: playbackMoved
            )
            try await PlaylistRemovalLogic.reinsert(
                snapshot.row, at: target, playlistId: 1, repository: repository
            )
        }
        let rows = try await repository.listEpisodes(playlistId: 1)
        #expect(rows.compactMap(\.enclosureUrl) == [Self.urls[2], Self.urls[0], Self.urls[1], Self.urls[3]])
    }
}
