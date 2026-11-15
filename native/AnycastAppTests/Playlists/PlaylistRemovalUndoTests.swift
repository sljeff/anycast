import Foundation
import Testing
import AnycastKit
@testable import Anycast

/// Playlist Remove defers its DB delete for the Undo window (or, for a row
/// the player may reach, deletes at once and re-inserts on Undo). Real SQLite
/// in a temporary file.
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

    @Test("a deferred remove leaves the stored row until the commit, which deletes once")
    func rowSurvivesUntilCommit() async throws {
        let fixture = try await Self.makeFixture()
        defer { fixture.cleanUp() }
        let repository = fixture.database.playlistRepository()
        let target = Self.urls[2]
        let removal = PendingRemoval(window: .seconds(60), center: NotificationCenter())
        var commits = 0

        removal.begin(target) {
            commits += 1
            try? await repository.removeEpisode(byEnclosureURL: target)
        }
        let stored = (try await repository.listEpisodes(playlistId: 1))
        #expect(stored.compactMap(\.enclosureUrl) == Self.urls)
        #expect(PlaylistRemovalLogic.displayed(stored, excluding: target).compactMap(\.enclosureUrl)
            == [Self.urls[0], Self.urls[1], Self.urls[3]])

        await removal.commitNow()
        await removal.commitNow()
        #expect(commits == 1)
        #expect(await fixture.storedURLs() == [Self.urls[0], Self.urls[1], Self.urls[3]])
    }

    @Test("undoing a deferred remove writes nothing and keeps the row's index")
    func undoKeepsIndex() async throws {
        let fixture = try await Self.makeFixture()
        defer { fixture.cleanUp() }
        let repository = fixture.database.playlistRepository()
        let target = Self.urls[2]
        let removal = PendingRemoval(window: .milliseconds(80), center: NotificationCenter())
        removal.begin(target) { try? await repository.removeEpisode(byEnclosureURL: target) }

        #expect(removal.undo())
        try await Task.sleep(for: .milliseconds(250))
        #expect(await fixture.storedURLs() == Self.urls)
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

        await PlaylistRemovalLogic.reinsert(snapshot.row, at: snapshot.index, playlistId: 1, repository: repository)
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
        await PlaylistRemovalLogic.reinsert(snapshot.row, at: snapshot.index, playlistId: 1, repository: repository)
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

    @Test("a change of the playing episode commits a pending removal")
    func trackChangeCommits() {
        let commit = PlaylistRemovalLogic.shouldCommitOnTrackChange
        #expect(commit("a", "x", "y"))
        #expect(commit("a", "x", nil))
        #expect(!commit("a", "x", "x"))
        #expect(!commit(nil, "x", "y"))
    }
}
