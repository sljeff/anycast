import Foundation
import UIKit
import Testing
import AnycastKit
@testable import Anycast

/// The import: matching followed shows by feed address, one write at the
/// end (so Cancel imports nothing), failures kept per show, and the copy of
/// every stage of the sheet.
@MainActor
@Suite(.serialized)
struct PodcastImporterTests {

    // MARK: - Fixtures

    /// Scripted stand-in for RSSFetcher: answers per address, in batches of
    /// 8 like the real one, and reports each batch.
    final class FakeFetcher: PodcastFetchProviding, @unchecked Sendable {
        private let lock = NSLock()
        private var feeds: [String: PodcastImportData]
        private func locked<T>(_ body: () -> T) -> T { lock.withLock(body) }
        /// How long the fetch takes; a cancelled caller wakes early.
        var delay: UInt64 = 0
        private(set) var requested: [[String]] = []

        init(feeds: [PodcastImportData]) {
            self.feeds = Dictionary(uniqueKeysWithValues: feeds.compactMap { feed in
                feed.subscription.rssFeedUrl.map { ($0, feed) }
            })
        }

        func serve(_ feed: PodcastImportData) {
            locked { if let url = feed.subscription.rssFeedUrl { feeds[url] = feed } }
        }

        func fetchPodcasts(
            urls: [String],
            onlyFirstEpisode: Bool,
            onBatch: (@Sendable (Int, Int, [PodcastImportData?]) -> Void)?
        ) async -> [PodcastImportData] {
            locked { requested.append(urls) }
            if delay > 0 { try? await Task.sleep(nanoseconds: delay) }
            var collected: [PodcastImportData] = []
            var start = 0
            while start < urls.count {
                let chunk = Array(urls[start..<min(start + 8, urls.count)])
                let results = locked { chunk.map { feeds[$0] } }
                onBatch?(start, urls.count, results)
                collected.append(contentsOf: results.compactMap { $0 })
                start += chunk.count
            }
            return collected
        }
    }

    private func makeDatabase() async throws -> (AppDatabase, URL) {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("import-\(UUID().uuidString).sqlite")
        let database = try await AppDatabase.openAt(url, localeIdentifier: "en_US")
        return (database, url)
    }

    private func podcast(url: String, title: String, enclosure: String? = nil) -> PodcastImportData {
        var subscription = SubscriptionRow(rssFeedUrl: url, title: title, description: "d")
        subscription.lastUpdated = 1_700_000_000_000
        var episode: FeedEpisodeRow?
        if let enclosure {
            var row = FeedEpisodeRow()
            row.enclosureUrl = enclosure
            row.pubDate = 1_700_000_000_000
            row.rssFeedUrl = url
            row.channelTitle = title
            episode = row
        }
        return PodcastImportData(subscription: subscription, feedEpisodes: episode.map { [$0] } ?? [])
    }

    private func entry(_ title: String, _ url: String) -> OPMLParser.Entry {
        OPMLParser.Entry(title: title, xmlURL: url)
    }

    // MARK: - Plan: already followed, matched by feed address

    @Test("A show already followed is skipped, matched by feed address")
    func planSkipsFollowed() {
        let plan = ImportPlan.make(
            entries: [entry("A", "https://a.example/f"), entry("B", "https://b.example/f")],
            followedURLs: ["https://a.example/f"]
        )
        #expect(plan.entries == [entry("B", "https://b.example/f")])
        #expect(plan.alreadyFollowed == 1)
        #expect(!plan.isAllFollowed)
    }

    @Test("Same feed written differently still counts as followed")
    func planMatchesEquivalentAddresses() {
        let plan = ImportPlan.make(
            entries: [
                entry("A", "HTTP://Feeds.Example.com/show/"),
                entry("B", "https://b.example/f?x=1"),
                entry("C", "https://c.example/f"),
            ],
            followedURLs: ["https://feeds.example.com/show", "https://b.example/f"]
        )
        // Trailing slash, host case and scheme do not matter; a different
        // query string is a different feed.
        #expect(plan.alreadyFollowed == 1)
        #expect(plan.entries.map(\.title) == ["B", "C"])
    }

    @Test("The same address twice in one file counts once; all followed; empty file")
    func planEdgeCases() {
        let twice = ImportPlan.make(
            entries: [entry("A", "https://a.example/f"), entry("A again", "https://a.example/f")],
            followedURLs: []
        )
        #expect(twice.entries.count == 1)
        #expect(twice.alreadyFollowed == 0)

        let all = ImportPlan.make(entries: [entry("A", "https://a.example/f")], followedURLs: ["https://a.example/f"])
        #expect(all.isAllFollowed)
        #expect(!all.isEmptyFile)

        let empty = ImportPlan.make(entries: [], followedURLs: ["https://a.example/f"])
        #expect(empty.isEmptyFile)
        #expect(!empty.isAllFollowed)
    }

    @Test("plan(entries:) reads the followed shows from the real database")
    func planUsesDatabase() async throws {
        let (database, databaseURL) = try await makeDatabase()
        defer { try? FileManager.default.removeItem(at: databaseURL) }
        try await database.subscriptionRepository()
            .addMany([SubscriptionRow(rssFeedUrl: "https://a.example/f", title: "A")])
        let importer = PodcastImporter(database: database, fetcher: FakeFetcher(feeds: []))

        let plan = await importer.plan(entries: [entry("A", "https://a.example/f"), entry("B", "https://b.example/f")])

        #expect(plan.alreadyFollowed == 1)
        #expect(plan.entries.map(\.title) == ["B"])
    }

    @Test("Only web addresses can be fetched")
    func webAddresses() {
        #expect(ImportPlan.isWebAddress("https://a.example/f"))
        #expect(ImportPlan.isWebAddress("http://a.example"))
        #expect(!ImportPlan.isWebAddress("ftp://a.example/f"))
        #expect(!ImportPlan.isWebAddress("not a url"))
        #expect(!ImportPlan.isWebAddress("https://"))
    }

    // MARK: - Run

    @Test("Run writes the first episodes and the subscriptions once, and says what failed")
    func runWritesAndReportsFailures() async throws {
        let (database, databaseURL) = try await makeDatabase()
        defer { try? FileManager.default.removeItem(at: databaseURL) }
        let a = podcast(url: "https://a.example/f", title: "A", enclosure: "enc-a")
        let c = podcast(url: "https://c.example/f", title: "C")
        let importer = PodcastImporter(database: database, fetcher: FakeFetcher(feeds: [a, c]))

        let outcome = await importer.run([
            entry("A", "https://a.example/f"),
            entry("Dead", "https://b.example/f"),
            entry("C", "https://c.example/f"),
            entry("Broken", "not a url"),
        ])

        #expect(outcome.imported.map(\.title) == ["A", "C"])
        #expect(outcome.failures.map(\.entry.title).sorted() == ["Broken", "Dead"])
        #expect(outcome.failures.first { $0.entry.title == "Dead" }?.reason == .unreachable)
        #expect(outcome.failures.first { $0.entry.title == "Broken" }?.reason == .invalidAddress)
        #expect(outcome.addedEpisodeCount == 1)
        #expect(!outcome.writeFailed && !outcome.cancelled)
        let stored = try await database.subscriptionRepository().listAll()
        #expect(Set(stored.compactMap(\.rssFeedUrl)) == ["https://a.example/f", "https://c.example/f"])
        #expect(try await database.feedRepository().count() == 1)
    }

    @Test("Progress reports how many have answered, row by row")
    func runReportsProgress() async throws {
        let (database, databaseURL) = try await makeDatabase()
        defer { try? FileManager.default.removeItem(at: databaseURL) }
        let urls = (0..<10).map { "https://u\($0).example/f" }
        let importer = PodcastImporter(
            database: database,
            fetcher: FakeFetcher(feeds: [podcast(url: urls[0], title: "Zero"), podcast(url: urls[9], title: "Nine")])
        )
        var finished: [Int] = []
        var answered: [Int: Bool] = [:]
        _ = await importer.run(urls.map { entry($0, $0) }) { count, rows in
            finished.append(count)
            for row in rows { answered[row.index] = row.ok }
        }
        // The progress callbacks hop to the main actor; let them land.
        try await Task.sleep(for: .milliseconds(100))

        #expect(finished.sorted() == [8, 10])
        #expect(answered.count == 10)
        #expect(answered[0] == true && answered[9] == true && answered[5] == false)
    }

    @Test("Cancel before the write imports nothing")
    func cancelWritesNothing() async throws {
        let (database, databaseURL) = try await makeDatabase()
        defer { try? FileManager.default.removeItem(at: databaseURL) }
        let a = podcast(url: "https://a.example/f", title: "A", enclosure: "enc-a")
        let fetcher = FakeFetcher(feeds: [a])
        fetcher.delay = 5_000_000_000
        let importer = PodcastImporter(database: database, fetcher: fetcher)

        let task = Task { await importer.run([self.entry("A", "https://a.example/f")]) }
        try await Task.sleep(for: .milliseconds(100))
        task.cancel()
        let outcome = await task.value

        #expect(outcome.cancelled)
        #expect(outcome.imported.isEmpty)
        #expect(try await database.subscriptionRepository().listAll().isEmpty)
        #expect(try await database.feedRepository().count() == 0)
    }

    // MARK: - The sheet: stages, retry of the failed only, Inbox hold

    private func waitForStage(_ stage: ImportSheetViewController.Stage, in sheet: ImportSheetViewController) async {
        for _ in 0..<100 where sheet.stage != stage {
            try? await Task.sleep(for: .milliseconds(50))
        }
    }

    private func button(_ identifier: String, in view: UIView) -> UIButton? {
        if let button = view as? UIButton, button.accessibilityIdentifier == identifier { return button }
        for subview in view.subviews {
            if let found = button(identifier, in: subview) { return found }
        }
        return nil
    }

    private func label(_ identifier: String, in view: UIView) -> UILabel? {
        if let label = view as? UILabel, label.accessibilityIdentifier == identifier { return label }
        for subview in view.subviews {
            if let found = label(identifier, in: subview) { return found }
        }
        return nil
    }

    private func makeSheet(
        database: AppDatabase,
        fetcher: FakeFetcher,
        entries: [OPMLParser.Entry],
        alreadyFollowed: Int = 0,
        inboxCount: Int = 0,
        limit: Int = 100
    ) -> ImportSheetViewController {
        let sheet = ImportSheetViewController(
            context: nil,
            importer: PodcastImporter(database: database, fetcher: fetcher),
            plan: ImportPlan(entries: entries, alreadyFollowed: alreadyFollowed),
            filename: "Overcast.opml",
            inboxLimit: { limit },
            inboxCount: { inboxCount }
        )
        sheet.loadViewIfNeeded()
        sheet.view.frame = CGRect(x: 0, y: 0, width: 402, height: 700)
        sheet.view.layoutIfNeeded()
        return sheet
    }

    @Test("Confirm stage copy, then a partial failure; Try again retries only the failed show")
    func sheetStagesAndRetry() async throws {
        let (database, databaseURL) = try await makeDatabase()
        defer { try? FileManager.default.removeItem(at: databaseURL) }
        let a = podcast(url: "https://a.example/f", title: "A", enclosure: "enc-a")
        let b = podcast(url: "https://b.example/f", title: "B", enclosure: "enc-b")
        let fetcher = FakeFetcher(feeds: [a])
        let sheet = makeSheet(
            database: database, fetcher: fetcher,
            entries: [entry("A", "https://a.example/f"), entry("B", "https://b.example/f")],
            alreadyFollowed: 3, inboxCount: 105, limit: 100
        )

        #expect(label("import-title", in: sheet.view)?.text == "Import 2 shows")
        #expect(label("import-subtitle", in: sheet.view)?.text == "From Overcast.opml \u{00B7} 3 already followed")
        let primary = try #require(button("import-primary", in: sheet.view))
        #expect(primary.configuration?.title == "Import 2 shows")

        primary.sendActions(for: .touchUpInside)
        #expect(InboxTrimHold.isHeld, "the Inbox trim waits while an import runs")
        await waitForStage(.result, in: sheet)

        #expect(sheet.stage == .result)
        #expect(label("import-title", in: sheet.view)?.text == "1 show imported")
        #expect(label("import-subtitle", in: sheet.view)?.text == "1 couldn\u{2019}t be reached")
        #expect(label("import-note", in: sheet.view)?.text ==
            "Your Inbox keeps the latest 100 episodes, so 5 older ones will leave it. The shows stay in Library.")
        #expect(InboxTrimHold.isHeld, "and keeps waiting until Done")
        #expect(button("import-secondary", in: sheet.view)?.configuration?.title == "Try 1 again")

        // B comes back online; only B is asked for again.
        fetcher.serve(b)
        button("import-secondary", in: sheet.view)?.sendActions(for: .touchUpInside)
        await waitForStage(.result, in: sheet)
        #expect(fetcher.requested.last == ["https://b.example/f"])
        #expect(label("import-title", in: sheet.view)?.text == "2 shows imported")
        #expect(button("import-secondary", in: sheet.view)?.isHidden == true)

        var done = false
        sheet.onDone = { done = true }
        button("import-primary", in: sheet.view)?.sendActions(for: .touchUpInside)
        #expect(done)
        #expect(!InboxTrimHold.isHeld, "Done lets the Inbox trim again")
        let stored = try await database.subscriptionRepository().listAll()
        #expect(stored.count == 2)
    }

    @Test("Every show failed: No shows imported, nothing written")
    func sheetAllFailed() async throws {
        let (database, databaseURL) = try await makeDatabase()
        defer { try? FileManager.default.removeItem(at: databaseURL) }
        let sheet = makeSheet(
            database: database, fetcher: FakeFetcher(feeds: []),
            entries: [entry("A", "https://a.example/f"), entry("B", "https://b.example/f")]
        )
        button("import-primary", in: sheet.view)?.sendActions(for: .touchUpInside)
        await waitForStage(.result, in: sheet)

        #expect(label("import-title", in: sheet.view)?.text == "No shows imported")
        #expect(label("import-subtitle", in: sheet.view)?.text == "2 couldn\u{2019}t be reached")
        #expect(label("import-note", in: sheet.view)?.isHidden == true)
        #expect(button("import-secondary", in: sheet.view)?.configuration?.title == "Try 2 again")
        #expect(try await database.subscriptionRepository().listAll().isEmpty)
        button("import-primary", in: sheet.view)?.sendActions(for: .touchUpInside)
        #expect(!InboxTrimHold.isHeld)
    }

    @Test("Cancel in the sheet returns to Confirm and writes nothing")
    func sheetCancel() async throws {
        let (database, databaseURL) = try await makeDatabase()
        defer { try? FileManager.default.removeItem(at: databaseURL) }
        let a = podcast(url: "https://a.example/f", title: "A", enclosure: "enc-a")
        let fetcher = FakeFetcher(feeds: [a])
        fetcher.delay = 5_000_000_000
        let sheet = makeSheet(database: database, fetcher: fetcher, entries: [entry("A", "https://a.example/f")])

        button("import-primary", in: sheet.view)?.sendActions(for: .touchUpInside)
        try await Task.sleep(for: .milliseconds(150))
        #expect(sheet.stage == .progress)
        button("import-cancel", in: sheet.view)?.sendActions(for: .touchUpInside)
        await waitForStage(.confirm, in: sheet)

        #expect(sheet.stage == .confirm)
        #expect(!InboxTrimHold.isHeld, "a cancelled import does not hold the Inbox")
        #expect(label("import-title", in: sheet.view)?.text == "Import 1 show")
        #expect(try await database.subscriptionRepository().listAll().isEmpty)
        #expect(try await database.feedRepository().count() == 0)
    }

    @Test("A file with no feeds, and a file whose shows are all followed")
    func sheetEmptyAndAllFollowed() async throws {
        let (database, databaseURL) = try await makeDatabase()
        defer { try? FileManager.default.removeItem(at: databaseURL) }
        let empty = makeSheet(database: database, fetcher: FakeFetcher(feeds: []), entries: [])
        #expect(label("import-title", in: empty.view)?.text == "No podcast feeds in this file.")
        #expect(button("import-primary", in: empty.view)?.configuration?.title == "Choose another file")
        #expect(button("import-secondary", in: empty.view)?.isHidden == true)

        let followed = makeSheet(database: database, fetcher: FakeFetcher(feeds: []), entries: [], alreadyFollowed: 52)
        #expect(label("import-title", in: followed.view)?.text == "You already follow all 52.")
        #expect(button("import-primary", in: followed.view)?.configuration?.title == "Done")
    }

    // MARK: - Copy

    @Test("Copy of every stage")
    func copy() {
        #expect(ImportCopy.confirmTitle(count: 52) == "Import 52 shows")
        #expect(ImportCopy.confirmTitle(count: 1) == "Import 1 show")
        #expect(ImportCopy.confirmSubtitle(filename: "Overcast.opml", alreadyFollowed: 8)
            == "From Overcast.opml \u{00B7} 8 already followed")
        #expect(ImportCopy.confirmSubtitle(filename: "Overcast.opml", alreadyFollowed: 0) == "From Overcast.opml")
        #expect(ImportCopy.confirmSubtitle(filename: nil, alreadyFollowed: 2) == "2 already followed")
        #expect(ImportCopy.progressCount(finished: 23, total: 52) == "23 of 52")
        #expect(ImportCopy.resultTitle(imported: 49) == "49 shows imported")
        #expect(ImportCopy.resultTitle(imported: 1) == "1 show imported")
        #expect(ImportCopy.resultTitle(imported: 0) == "No shows imported")
        #expect(ImportCopy.failedSummary(count: 3) == "3 couldn\u{2019}t be reached")
        #expect(ImportCopy.retryButton(count: 3) == "Try 3 again")
        #expect(ImportCopy.writeFailedTitle == "Couldn\u{2019}t save. Nothing was imported.")
        #expect(ImportCopy.allFollowedTitle(total: 52) == "You already follow all 52.")
        #expect(ImportCopy.noFeedsTitle == "No podcast feeds in this file.")
    }

    @Test("Inbox-limit line: how many older episodes leave, omitted when none do")
    func inboxLimitNote() {
        #expect(ImportCopy.inboxLimitNote(inboxCount: 112, limit: 100)
            == "Your Inbox keeps the latest 100 episodes, so 12 older ones will leave it. The shows stay in Library.")
        #expect(ImportCopy.inboxLimitNote(inboxCount: 101, limit: 100)
            == "Your Inbox keeps the latest 100 episodes, so 1 older one will leave it. The shows stay in Library.")
        #expect(ImportCopy.inboxLimitNote(inboxCount: 100, limit: 100) == nil)
        #expect(ImportCopy.inboxLimitNote(inboxCount: 12, limit: 100) == nil)
    }

    @Test("Export copy")
    func exportCopy() {
        #expect(ImportCopy.exportFileName == "Anycast Subscriptions.opml")
        #expect(ImportCopy.exportFailed == "Couldn\u{2019}t create the file. Try again.")
        #expect(ImportCopy.exportEmpty == "No shows yet")
        #expect(ImportCopy.exportFooter
            == "Export covers the shows you follow. Playlist, history and transcripts stay on this iPhone.")
    }
}
