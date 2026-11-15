import Foundation
import Testing
import AnycastKit
@testable import Anycast

/// Inbox Remove defers its DB delete for the Undo window: the displayed
/// list drops the pending row while the stored row stays until the commit.
/// Real SQLite in a temporary file.
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

    private static func displayed(_ rows: [FeedEpisodeRow], excluding pending: String?) -> [String] {
        InboxCategoryFilter.displayed(
            episodes: rows, selected: nil, categoriesByFeed: [:], excluding: pending
        ).compactMap(\.enclosureUrl)
    }

    @Test("a pure remove leaves the stored row until the commit")
    func rowSurvivesUntilCommit() async throws {
        let fixture = try await Self.makeFixture()
        defer { fixture.cleanUp() }
        let repository = fixture.database.feedRepository()
        let target = Self.urls[1]
        let removal = PendingRemoval(window: .seconds(60), center: NotificationCenter())

        removal.begin(target) { try? await repository.removeByEnclosureUrls([target]) }
        #expect(await fixture.storedURLs().contains(target))

        await removal.commitNow()
        #expect(await fixture.storedURLs() == [Self.urls[2], Self.urls[0]])
    }

    @Test("the displayed list excludes the pending URL after a reload")
    func displayedExcludesPending() async throws {
        let fixture = try await Self.makeFixture()
        defer { fixture.cleanUp() }
        let rows = try await fixture.database.feedRepository().listAll()

        #expect(Self.displayed(rows, excluding: Self.urls[1]) == [Self.urls[2], Self.urls[0]])
        #expect(Self.displayed(rows, excluding: nil).count == 3)
    }

    @Test("undo restores the row at its original index without a DB write")
    func undoRestoresPosition() async throws {
        let fixture = try await Self.makeFixture()
        defer { fixture.cleanUp() }
        let repository = fixture.database.feedRepository()
        let target = Self.urls[1]
        let removal = PendingRemoval(window: .milliseconds(80), center: NotificationCenter())
        removal.begin(target) { try? await repository.removeByEnclosureUrls([target]) }

        #expect(removal.undo())
        try await Task.sleep(for: .milliseconds(250))

        let rows = try await repository.listAll()
        #expect(Self.displayed(rows, excluding: nil) == [Self.urls[2], Self.urls[1], Self.urls[0]])
    }

    @Test("only a pure remove is deferred; Play and Add keep their immediate removal")
    func onlyPureRemoveDefers() {
        func steps(_ action: InboxEpisodeAction) -> [InboxActionStep] {
            InboxActionPlanner.steps(
                for: action, currentPlaylistId: nil, currentEnclosureURL: nil,
                episodeEnclosureURL: Self.urls[0]
            )
        }
        #expect(InboxPageViewController.defersRemoval(steps(.remove)))
        #expect(!InboxPageViewController.defersRemoval(steps(.play)))
        #expect(!InboxPageViewController.defersRemoval(steps(.addToPlaylist)))
    }
}
