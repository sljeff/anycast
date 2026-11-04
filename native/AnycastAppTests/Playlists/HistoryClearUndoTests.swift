import UIKit
import Testing
import AnycastKit
@testable import Anycast

/// History Clear All deletes on confirm (no undo window). Per-item delete
/// removes one enclosure. Real SQLite in a temporary file; the controller
/// is built over the live app context with that database injected.
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
    private static func makeFixture() async throws -> Fixture? {
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
        let controller = HistoryDialogViewController(context: context, database: database)
        controller.loadViewIfNeeded()
        let fixture = Fixture(controller: controller, database: database, databaseURL: url)
        let loaded = await waitUntil { controller.episodes.count == 3 }
        try #require(loaded, "the initial reload never delivered the seeded rows")
        return fixture
    }

    @Test("confirmed clear deletes every history row and shows the one-line empty state")
    func confirmClearDeletes() async throws {
        guard let fixture = try await Self.makeFixture() else { return }
        defer { fixture.cleanUp() }

        #expect(Self.visibleButtonTitles(in: fixture.controller.view).contains("Clear All"))
        fixture.controller.commitClearAll()

        #expect(fixture.controller.episodes.isEmpty)
        let emptied = await Self.waitUntil { await fixture.historyCount() == 0 }
        #expect(emptied)
        fixture.controller.view.layoutIfNeeded()
        #expect(!Self.visibleButtonTitles(in: fixture.controller.view).contains("Clear All"))
        #expect(Self.visibleButtonTitles(in: fixture.controller.view).contains("Explore"))
        #expect(Self.visibleLabelTexts(in: fixture.controller.view).contains("Play an episode and it shows up here."))
        #expect(!Self.visibleLabelTexts(in: fixture.controller.view).contains("No history"))
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

    @Test("history row title may wrap")
    func rowTitleMayWrap() {
        let cell = HistoryRowCell(frame: .zero)
        cell.configure(HistoryEpisodeRow(title: "A very long episode title", channelTitle: "Channel"))
        #expect(cell.titleLabel.numberOfLines == 0)
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

    @Test("row subtitle is the show and a relative play time")
    func rowSubtitle() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let twoHoursAgo = Int64(now.timeIntervalSince1970 * 1000) - 2 * 3_600_000
        #expect(
            HistoryPresentation.subtitle(channel: "Night Kitchen", lastPlayedAt: twoHoursAgo, now: now)
                == "Night Kitchen · 2h ago"
        )
        #expect(HistoryPresentation.subtitle(channel: "Night Kitchen", lastPlayedAt: nil, now: now) == "Night Kitchen")
        #expect(HistoryPresentation.subtitle(channel: nil, lastPlayedAt: twoHoursAgo, now: now) == "2h ago")
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
