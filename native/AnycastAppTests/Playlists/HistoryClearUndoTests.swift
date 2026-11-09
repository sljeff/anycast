import UIKit
import Testing
import AnycastKit
@testable import Anycast

/// History's Clear All defers the DB delete for an Undo window: beginning a
/// clear empties the list only, Undo re-reads the untouched DB, and the
/// commit (timer, early commit, or disappearance) deletes exactly once.
/// Per-item delete removes one enclosure. Real SQLite in a temporary file;
/// the controller is built over the live app context with that database
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
                channelTitle: "Channel",
                lastPlayedAt: Int64(index) * 1_000
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
        #expect(Self.visibleButtonTitles(in: fixture.controller.view).contains("Hold to Clear History"))
        fixture.controller.beginPendingClear()

        #expect(fixture.controller.episodes.isEmpty)
        #expect(fixture.controller.footerState == .undo)
        #expect(await fixture.historyCount() == 3)
        fixture.controller.view.layoutIfNeeded()
        #expect(Self.visibleLabelTexts(in: fixture.controller.view).contains("History cleared"))
        #expect(Self.visibleButtonTitles(in: fixture.controller.view).contains("Undo"))
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

    @Test("the undo window elapsing commits the delete and shows the cleared state")
    func windowElapsedCommits() async throws {
        guard let fixture = try await Self.makeFixture(undoWindow: .milliseconds(100)) else { return }
        defer { fixture.cleanUp() }

        fixture.controller.beginPendingClear()
        try await Task.sleep(for: .milliseconds(400))

        let emptied = await Self.waitUntil { await fixture.historyCount() == 0 }
        #expect(emptied)
        #expect(fixture.controller.footerState == .hidden)
        fixture.controller.view.layoutIfNeeded()
        #expect(Self.visibleLabelTexts(in: fixture.controller.view).contains("History cleared"))
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

    @Test("an empty history shows the shared empty state with a primary Explore button and no header Clear All")
    func emptyState() async throws {
        guard let context = await Self.liveUIContext() else { return }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("history-empty-\(UUID().uuidString).sqlite")
        defer { try? FileManager.default.removeItem(at: url) }
        let database = try await AppDatabase.openAt(url, localeIdentifier: "en_US")
        let controller = HistoryDialogViewController(context: context, database: database)
        controller.loadViewIfNeeded()
        controller.view.frame = CGRect(x: 0, y: 0, width: 393, height: 600)
        let shown = await Self.waitUntil {
            controller.view.layoutIfNeeded()
            return Self.visibleLabelTexts(in: controller.view).contains("Play an episode and it shows up here.")
        }
        #expect(shown)
        #expect(Self.visibleButtonTitles(in: controller.view).contains("Explore"))
        #expect(!Self.visibleButtonTitles(in: controller.view).contains("Clear All"))
        #expect(!Self.visibleButtonTitles(in: controller.view).contains("Hold to Clear History"))
        #expect(controller.footerState == .hidden)
    }

    @Test("deleting one enclosure leaves the others")
    func deleteOneRow() async throws {
        guard let fixture = try await Self.makeFixture() else { return }
        defer { fixture.cleanUp() }

        fixture.controller.deleteEpisode(url: "https://example.test/episode-2.mp3")
        #expect(fixture.controller.episodes.map(\.enclosureUrl) == [
            "https://example.test/episode-3.mp3",
            "https://example.test/episode-1.mp3",
        ])
        let settled = await Self.waitUntil { await fixture.historyCount() == 2 }
        #expect(settled)
    }

    @Test("history row title is a single truncated line on a 44 pt cover")
    func rowTitleIsOneLine() {
        let cell = HistoryRowCell(frame: .zero)
        cell.configure(HistoryEpisodeRow(title: "A very long episode title", channelTitle: "Channel"))
        #expect(cell.titleLabel.numberOfLines == 1)
        #expect(cell.titleLabel.lineBreakMode == .byTruncatingTail)
        #expect(HistoryRowCell.coverSize == 44)
    }

    @Test("day groups follow the calendar and keep newest-first order")
    func dayGroups() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let today = Int64(now.timeIntervalSince1970 * 1000)
        let yesterday = calendar.date(byAdding: .day, value: -1, to: now)!
        let earlier = calendar.date(byAdding: .day, value: -3, to: now)!
        func millis(_ date: Date) -> Int64 { Int64(date.timeIntervalSince1970 * 1000) }

        let rows = [
            HistoryEpisodeRow(title: "later today", enclosureUrl: "https://example.test/t2.mp3", lastPlayedAt: today),
            HistoryEpisodeRow(title: "earlier today", enclosureUrl: "https://example.test/t1.mp3", lastPlayedAt: today - 3_600_000),
            HistoryEpisodeRow(title: "yesterday", enclosureUrl: "https://example.test/y.mp3", lastPlayedAt: millis(yesterday)),
            HistoryEpisodeRow(title: "old", enclosureUrl: "https://example.test/e.mp3", lastPlayedAt: millis(earlier)),
            HistoryEpisodeRow(title: "unknown", enclosureUrl: "https://example.test/u.mp3", lastPlayedAt: nil),
        ]
        let grouped = HistoryDayGrouping.grouped(rows, now: now, calendar: calendar)
        #expect(grouped.map(\.section) == [.today, .yesterday, .earlier])
        #expect(grouped[0].rows.map(\.title) == ["later today", "earlier today"])
        #expect(grouped[1].rows.map(\.title) == ["yesterday"])
        #expect(grouped[2].rows.map(\.title) == ["old", "unknown"])
    }

    @Test("row meta puts the relative time first, then the show")
    func rowSubtitle() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let twoHoursAgo = Int64(now.timeIntervalSince1970 * 1000) - 2 * 3_600_000
        #expect(
            HistoryPresentation.subtitle(channel: "Night Kitchen", lastPlayedAt: twoHoursAgo, now: now)
                == "2h ago · Night Kitchen"
        )
        #expect(HistoryPresentation.subtitle(channel: nil, lastPlayedAt: twoHoursAgo, now: now) == "2h ago")
    }

    @Test("a row with no play time shows just the show and no date")
    func nullTimeSubtitle() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let subtitle = HistoryPresentation.subtitle(channel: "Night Kitchen", lastPlayedAt: nil, now: now)
        #expect(subtitle == "Night Kitchen")
        for fragment in ["1969", "1970", "ago", "·"] {
            #expect(!subtitle.contains(fragment))
        }
        #expect(HistoryPresentation.subtitle(channel: nil, lastPlayedAt: nil, now: now).isEmpty)
    }

    @Test("VoiceOver label includes the relative time only when present")
    func accessibilityLabel() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let twoHoursAgo = Int64(now.timeIntervalSince1970 * 1000) - 2 * 3_600_000
        #expect(
            HistoryPresentation.accessibilityLabel(
                title: "Episode", channel: "Show", lastPlayedAt: twoHoursAgo, now: now
            ) == "Episode, Show, 2h ago"
        )
        #expect(
            HistoryPresentation.accessibilityLabel(
                title: "Episode", channel: "Show", lastPlayedAt: nil, now: now
            ) == "Episode, Show"
        )
        let cell = HistoryRowCell(frame: .zero)
        cell.configure(
            HistoryEpisodeRow(title: "Episode", channelTitle: "Show", lastPlayedAt: twoHoursAgo), now: now
        )
        #expect(cell.accessibilityLabel == "Episode, Show, 2h ago")
    }

    // MARK: - Helpers

    private static func visibleLabelTexts(in view: UIView) -> [String] {
        guard !view.isHidden, view.alpha > 0 else { return [] }
        var texts: [String] = []
        if let label = view as? UILabel, let text = label.text, !text.isEmpty {
            texts.append(text)
        }
        for subview in view.subviews {
            texts.append(contentsOf: visibleLabelTexts(in: subview))
        }
        return texts
    }

    private static func visibleButtonTitles(in view: UIView) -> [String] {
        guard !view.isHidden, view.alpha > 0 else { return [] }
        var titles: [String] = []
        if let button = view as? UIButton {
            let title = button.configuration?.title ?? button.currentTitle ?? ""
            if !title.isEmpty { titles.append(title) }
        }
        for subview in view.subviews {
            titles.append(contentsOf: visibleButtonTitles(in: subview))
        }
        return titles
    }

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
