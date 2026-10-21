import UIKit
import Testing
import AnycastKit
@testable import Anycast

/// History's Clear All defers the DB delete for an Undo window: beginning a
/// clear empties the list only, Undo re-reads the untouched DB, and the
/// commit (timer, early commit, or disappearance) deletes exactly once.
/// Real SQLite in a temporary file; the controller is built over the live
/// app context (like the sibling screen tests) with the temporary database
/// injected, so the app's own history is never touched.
@MainActor
struct HistoryClearUndoTests {

    private struct Fixture {
        let controller: HistoryDialogViewController
        let database: AppDatabase
        let databaseURL: URL

        func historyCount() async -> Int {
            ((try? await database.historyRepository().listAll()) ?? []).count
        }

        func cleanUp() {
            try? FileManager.default.removeItem(at: databaseURL)
        }
    }

    /// nil when the app host never produced a `UIContext` (non-hosted run).
    private static func makeFixture(undoWindow: Duration = .seconds(60)) async throws -> Fixture? {
        guard let context = await liveUIContext() else { return nil }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("history-clear-\(UUID().uuidString).sqlite")
        let database = try await AppDatabase.openAt(url, localeIdentifier: "en_US")
        for index in 1...3 {
            try await database.historyRepository().insert(HistoryEpisodeRow(
                title: "Episode \(index)",
                enclosureUrl: "https://example.test/episode-\(index).mp3",
                imageUrl: nil,
                channelTitle: "Channel"
            ))
        }
        let controller = HistoryDialogViewController(
            context: context, database: database, undoWindow: undoWindow
        )
        controller.loadViewIfNeeded()
        let fixture = Fixture(controller: controller, database: database, databaseURL: url)
        let loaded = await waitUntil { controller.episodes.count == 3 }
        try #require(loaded, "the initial reload never delivered the seeded rows")
        return fixture
    }

    @Test("begin pending clear empties the list and leaves the DB alone")
    func beginKeepsDatabase() async throws {
        guard let fixture = try await Self.makeFixture() else { return }
        defer { fixture.cleanUp() }

        #expect(fixture.controller.footerState == .hold)
        fixture.controller.beginPendingClear()

        #expect(fixture.controller.episodes.isEmpty)
        #expect(fixture.controller.footerState == .undo)
        #expect(await fixture.historyCount() == 3)
    }

    @Test("undo restores the rows from the DB and returns to the hold button")
    func undoRestores() async throws {
        guard let fixture = try await Self.makeFixture() else { return }
        defer { fixture.cleanUp() }

        fixture.controller.beginPendingClear()
        await fixture.controller.undoPendingClear()

        #expect(fixture.controller.episodes.count == 3)
        #expect(fixture.controller.footerState == .hold)
        #expect(await fixture.historyCount() == 3)
    }

    @Test("the undo window elapsing commits the delete")
    func windowElapsedCommits() async throws {
        guard let fixture = try await Self.makeFixture(undoWindow: .milliseconds(100)) else { return }
        defer { fixture.cleanUp() }

        fixture.controller.beginPendingClear()
        try await Task.sleep(for: .milliseconds(400))

        let emptied = await Self.waitUntil { await fixture.historyCount() == 0 }
        #expect(emptied)
        #expect(fixture.controller.footerState == .hidden)
    }

    @Test("early commit deletes once; a second commit is a no-op")
    func earlyCommitIsIdempotent() async throws {
        guard let fixture = try await Self.makeFixture() else { return }
        defer { fixture.cleanUp() }

        fixture.controller.beginPendingClear()
        fixture.controller.commitPendingClear()
        #expect(!fixture.controller.hasPendingClear)

        let emptied = await Self.waitUntil { await fixture.historyCount() == 0 }
        #expect(emptied)
        #expect(fixture.controller.footerState == .hidden)

        fixture.controller.commitPendingClear()
        #expect(fixture.controller.footerState == .hidden)
        #expect(await fixture.historyCount() == 0)
    }

    @Test("history row title is a single truncated line")
    func rowTitleIsOneLine() {
        let cell = HistoryRowCell(frame: .zero)
        cell.configure(HistoryEpisodeRow(title: "A very long episode title", channelTitle: "Channel"))
        #expect(cell.titleLabel.numberOfLines == 1)
    }

    // MARK: - Helpers

    private static func waitUntil(
        timeout: Duration = .seconds(5),
        _ condition: @MainActor () async -> Bool
    ) async -> Bool {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if await condition() { return true }
            try? await Task.sleep(for: .milliseconds(25))
        }
        return await condition()
    }

    private static func liveUIContext() async -> UIContext? {
        for _ in 0..<40 {
            if let context = (UIApplication.shared.delegate as? AppDelegate)?.environment.uiContext {
                return context
            }
            try? await Task.sleep(for: .milliseconds(500))
        }
        return nil
    }
}
