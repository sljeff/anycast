import Foundation
import Testing
import AnycastKit
@testable import Anycast

/// Inbox Remove defers its DB delete for the Undo window: the displayed
/// list drops the pending rows while the stored rows stay until the commit.
/// An Add is durable at once; Undo moves its rows back. Real SQLite in a
/// temporary file.
@MainActor
struct InboxRemovalUndoTests {

    private struct Fixture {
        let database: AppDatabase
        let url: URL

        func storedURLs() async -> [String] {
            ((try? await database.feedRepository().listAll()) ?? []).compactMap(\.enclosureUrl)
        }

        func cleanUp() { try? FileManager.default.removeItem(at: url) }
    }

    private static let urls = (1...3).map { "https://example.test/inbox-\($0).mp3" }

    private static func makeFixture() async throws -> Fixture {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("inbox-removal-\(UUID().uuidString).sqlite")
        let database = try await AppDatabase.openAt(url, localeIdentifier: "en_US")
        // Newest first: inbox-3, inbox-2, inbox-1.
        let rows = urls.enumerated().map { index, enclosure in
            FeedEpisodeRow(
                title: "Episode \(index + 1)", enclosureUrl: enclosure,
                pubDate: Int64(index + 1) * 1_000, rssFeedUrl: "https://example.test/feed"
            )
        }
        try await database.feedRepository().insertMany(rows)
        return Fixture(database: database, url: url)
    }

    private static func displayed(_ rows: [FeedEpisodeRow], excluding hidden: Set<String>) -> [String] {
        InboxCategoryFilter.displayed(
            episodes: rows, selected: nil, categoriesByFeed: [:], excluding: hidden
        ).compactMap(\.enclosureUrl)
    }

    @Test("merged removes leave the stored rows until the commit, which deletes them together")
    func rowsSurviveUntilCommit() async throws {
        let fixture = try await Self.makeFixture()
        defer { fixture.cleanUp() }
        let repository = fixture.database.feedRepository()
        let batch = PendingBatch<InboxBatchKind, InboxBatchItem>(window: .seconds(60), center: NotificationCenter())
        var commits = 0

        for target in [Self.urls[1], Self.urls[0]] {
            batch.add(InboxBatchItem(url: target), kind: .remove) { items in
                commits += 1
                try? await repository.removeByEnclosureUrls(items.map(\.url))
            }
        }
        #expect(await fixture.storedURLs().contains(Self.urls[1]))

        await batch.commitNow()
        #expect(commits == 1)
        #expect(await fixture.storedURLs() == [Self.urls[2]])
    }

    @Test("the displayed list excludes every pending URL after a reload")
    func displayedExcludesPending() async throws {
        let fixture = try await Self.makeFixture()
        defer { fixture.cleanUp() }
        let rows = try await fixture.database.feedRepository().listAll()

        #expect(Self.displayed(rows, excluding: [Self.urls[1], Self.urls[2]]) == [Self.urls[0]])
        #expect(Self.displayed(rows, excluding: []).count == 3)
    }

    @Test("undo of removes restores the rows at their original index without a DB write")
    func undoRestoresPosition() async throws {
        let fixture = try await Self.makeFixture()
        defer { fixture.cleanUp() }
        let repository = fixture.database.feedRepository()
        let batch = PendingBatch<InboxBatchKind, InboxBatchItem>(window: .milliseconds(80), center: NotificationCenter())
        for target in [Self.urls[1], Self.urls[2]] {
            batch.add(InboxBatchItem(url: target), kind: .remove) { items in
                try? await repository.removeByEnclosureUrls(items.map(\.url))
            }
        }

        #expect(batch.undo()?.items.map(\.url) == [Self.urls[2], Self.urls[1]])
        try await Task.sleep(for: .milliseconds(250))

        let rows = try await repository.listAll()
        #expect(Self.displayed(rows, excluding: []) == [Self.urls[2], Self.urls[1], Self.urls[0]])
    }

    /// What an Add does durably, for the fixture: the playlist insert, then the
    /// inbox delete. Returns the batch item the screen would record.
    private static func add(
        _ url: String, fixture: Fixture, playlistIndex: Int
    ) async throws -> InboxBatchItem {
        let feed = fixture.database.feedRepository()
        let playlist = fixture.database.playlistRepository()
        let feedRow = try #require(try await feed.listAll().first { $0.enclosureUrl == url })
        try await playlist.insertOrUpdateByIndex(
            ChannelPlaylistLogic.playlistRow(from: feedRow, playlistId: 1), playlistId: 1, index: playlistIndex
        )
        let created = try await playlist.episode(byEnclosureURL: url)
        try await feed.removeByEnclosureUrls([url])
        return InboxBatchItem(url: url, feedRow: feedRow, createdPlaylistRow: created)
    }

    @Test("rapid Add x3 then Undo restores every content column and empties the playlist")
    func undoMergedAdds() async throws {
        let fixture = try await Self.makeFixture()
        defer { fixture.cleanUp() }
        let feed = fixture.database.feedRepository()
        let playlist = fixture.database.playlistRepository()
        let before = try await feed.listAll()
        let batch = PendingBatch<InboxBatchKind, InboxBatchItem>(window: .seconds(60), center: NotificationCenter())

        for (index, url) in Self.urls.reversed().enumerated() {
            let item = try await Self.add(url, fixture: fixture, playlistIndex: index)
            batch.add(item, kind: .add) { _ in }
        }
        #expect(try await feed.listAll().isEmpty)
        #expect(try await playlist.listEpisodes(playlistId: 1).count == 3)
        #expect(InboxBatchLogic.message(kind: .add, count: batch.count) == "Added 3 to Playlist")

        let undone = try #require(batch.undo())
        try await InboxBatchLogic.undoAdd(
            undone.items, currentEnclosureURL: nil, feedRepository: feed, playlistRepository: playlist
        )
        // Every content column survives; the row ids are DELIBERATELY not
        // preserved (a restored id could collide with one a refresh
        // recycled — covered by the window tests below).
        let after = try await feed.listAll()
        #expect(after.map(\.enclosureUrl) == before.map(\.enclosureUrl))
        #expect(after.map(\.title) == before.map(\.title))
        #expect(after.map(\.pubDate) == before.map(\.pubDate))
        #expect(try await playlist.listEpisodes(playlistId: 1).isEmpty)
    }

    @Test("undoing an Add leaves a playlist row it did not create, and the one now playing")
    func undoAddSparesOtherPlaylistRows() async throws {
        let fixture = try await Self.makeFixture()
        defer { fixture.cleanUp() }
        let feed = fixture.database.feedRepository()
        let playlist = fixture.database.playlistRepository()
        let created = try await Self.add(Self.urls[0], fixture: fixture, playlistIndex: 0)
        let playing = try await Self.add(Self.urls[1], fixture: fixture, playlistIndex: 1)
        // An Add that created nothing (the episode was already queued).
        let feedRow = try #require(try await feed.listAll().first { $0.enclosureUrl == Self.urls[2] })
        let noRow = InboxBatchItem(url: Self.urls[2], feedRow: feedRow, createdPlaylistRow: nil)
        try await playlist.insertOrUpdateByIndex(
            ChannelPlaylistLogic.playlistRow(from: feedRow, playlistId: 1), playlistId: 1, index: 2
        )
        try await feed.removeByEnclosureUrls([Self.urls[2]])

        try await InboxBatchLogic.undoAdd(
            [noRow, playing, created], currentEnclosureURL: Self.urls[1],
            feedRepository: feed, playlistRepository: playlist
        )
        #expect(try await playlist.listEpisodes(playlistId: 1).compactMap(\.enclosureUrl)
            == [Self.urls[1], Self.urls[2]])
        #expect(try await feed.listAll().count == 3)
    }

    // MARK: - Undo vs rows that arrived inside the window

    /// `feedEpisode.id` is not AUTOINCREMENT: after the Add deleted the
    /// highest id, a refresh inside the undo window reuses that id. Undo
    /// must not REPLACE on it — the new row would vanish.
    @Test("undo of an Add never deletes a row that recycled the deleted id")
    func undoAddKeepsRecycledIdRow() async throws {
        let fixture = try await Self.makeFixture()
        defer { fixture.cleanUp() }
        let feed = fixture.database.feedRepository()
        let playlist = fixture.database.playlistRepository()

        // Add the row carrying the HIGHEST id (urls[2] was inserted last).
        let item = try await Self.add(Self.urls[2], fixture: fixture, playlistIndex: 0)
        // A refresh lands a brand-new episode inside the window; SQLite
        // assigns it the recycled id.
        try await feed.insertMany([
            FeedEpisodeRow(
                title: "Fresh episode", enclosureUrl: "https://example.test/fresh.mp3",
                pubDate: 9_999, rssFeedUrl: "https://example.test/feed"
            )
        ])
        let fresh = try #require(try await feed.listAll().first { $0.title == "Fresh episode" })
        #expect(item.feedRow?.id != nil)
        #expect(fresh.id == item.feedRow?.id, "the new row recycled the deleted id")

        try await InboxBatchLogic.undoAdd(
            [item], currentEnclosureURL: nil, feedRepository: feed, playlistRepository: playlist
        )

        let after = try await feed.listAll()
        #expect(after.count == 4, "both the restored row and the recycled-id row survive")
        #expect(after.contains { $0.title == "Fresh episode" })
        #expect(after.contains { $0.enclosureUrl == Self.urls[2] })
    }

    /// A refresh can re-land the SAME url with newer data inside the undo
    /// window; Undo keeps that row as-is instead of overwriting it with
    /// the stale copy the Add took out.
    @Test("undo of an Add keeps a same-URL row a refresh re-landed in the window")
    func undoAddKeepsRefreshedSameURLRow() async throws {
        let fixture = try await Self.makeFixture()
        defer { fixture.cleanUp() }
        let feed = fixture.database.feedRepository()
        let playlist = fixture.database.playlistRepository()

        let item = try await Self.add(Self.urls[0], fixture: fixture, playlistIndex: 0)
        // The refresh's copy: same url, newer title.
        try await feed.insertMany([
            FeedEpisodeRow(
                title: "Refreshed title", enclosureUrl: Self.urls[0],
                pubDate: 9_999, rssFeedUrl: "https://example.test/feed"
            )
        ])

        try await InboxBatchLogic.undoAdd(
            [item], currentEnclosureURL: nil, feedRepository: feed, playlistRepository: playlist
        )

        let after = try await feed.listAll()
        #expect(after.count == 3, "no duplicate and no replacement")
        #expect(try await feed.listAll().first { $0.enclosureUrl == Self.urls[0] }?.title == "Refreshed title")
        #expect(try await playlist.listEpisodes(playlistId: 1).isEmpty)
    }

    @Test("the capsule text counts a merged batch")
    func batchMessages() {
        #expect(InboxBatchLogic.message(kind: .remove, count: 1) == "Removed")
        #expect(InboxBatchLogic.message(kind: .remove, count: 3) == "Removed 3 episodes")
        #expect(InboxBatchLogic.message(kind: .add, count: 1) == "Added to Playlist")
        #expect(InboxBatchLogic.message(kind: .add, count: 3) == "Added 3 to Playlist")
    }

    @Test("Add then Remove commits the Add batch at once; Remove then Add commits the Remove")
    func kindSwitchCommits() async throws {
        let batch = PendingBatch<InboxBatchKind, InboxBatchItem>(window: .seconds(60), center: NotificationCenter())
        var commits: [[String]] = []
        batch.add(InboxBatchItem(url: "a"), kind: .add) { commits.append($0.map(\.url)) }
        batch.add(InboxBatchItem(url: "b"), kind: .remove) { commits.append($0.map(\.url)) }
        try await Task.sleep(for: .milliseconds(60))
        #expect(commits == [["a"]])
        batch.add(InboxBatchItem(url: "c"), kind: .add) { commits.append($0.map(\.url)) }
        try await Task.sleep(for: .milliseconds(60))
        #expect(commits == [["a"], ["b"]])
        #expect(batch.undo()?.items.map(\.url) == ["c"])
    }
}
