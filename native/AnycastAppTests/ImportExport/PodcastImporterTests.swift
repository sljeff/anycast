import Foundation
import Testing
import AnycastKit
@testable import Anycast

/// PodcastImporter parity (lib/utils/rss_fetcher.dart:20-31 +
/// import_export.dart / share.dart widget-side persistence): the `s = {}`
/// dead filter verbatim, the idle → importing(progress) → finished state
/// machine with TempResult batch semantics, partial-failure result text,
/// and the real-SQLite re-import behavior the dead filter implies.
@MainActor
struct PodcastImporterTests {

    // MARK: - Fixtures

    /// Scripted stand-in for RSSFetcher: one array per 8-URL batch (nil =
    /// failed source, skipped), reporting the batch START index like
    /// TempResult does.
    private struct FakeFetcher: PodcastFetchProviding {
        var batches: [[PodcastImportData?]]

        nonisolated func fetchPodcasts(
            urls: [String],
            onlyFirstEpisode: Bool,
            onBatch: (@Sendable (Int, Int, [PodcastImportData?]) -> Void)?
        ) async -> [PodcastImportData] {
            var collected: [PodcastImportData] = []
            var start = 0
            for chunk in batches {
                onBatch?(start, urls.count, chunk)
                start += chunk.count
                for case let podcast? in chunk {
                    collected.append(podcast)
                }
            }
            return collected
        }
    }

    private func makeDatabase() async throws -> (AppDatabase, URL) {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("t9-import-\(UUID().uuidString).sqlite")
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

    // MARK: - The dead filter (rss_fetcher.dart:24-28, preserved verbatim)

    @Test("Dead filter: existing subscription URLs are NOT filtered out")
    func deadFilterPassesExistingURLs() {
        let existing = [SubscriptionRow(rssFeedUrl: "https://a.example/f", title: "A")]
        let urls = ["https://a.example/f", "https://b.example/f"]
        // `s = {};` — the set is discarded; nothing is ever excluded.
        #expect(PodcastImporter.filterExisting(urls: urls, existingSubscriptions: existing) == urls)
        #expect(PodcastImporter.filterExisting(urls: [], existingSubscriptions: existing) == [])
    }

    @Test("Re-import re-fetches and rewrites the row (INSERT OR REPLACE rotates the id)")
    func reImportRewritesRow() async throws {
        let (database, databaseURL) = try await makeDatabase()
        defer { try? FileManager.default.removeItem(at: databaseURL) }
        let a = podcast(url: "https://a.example/f", title: "A", enclosure: "enc-a")
        let b = podcast(url: "https://b.example/f", title: "B", enclosure: "enc-b")

        var importer = PodcastImporter(database: database, fetcher: FakeFetcher(batches: [[a, b]]))
        await importer.importByURLs(["https://a.example/f", "https://b.example/f"], reportsProgress: true)

        var rows = try await database.subscriptionRepository().listAll()
        #expect(rows.count == 2)
        let idBefore = rows.first { $0.title == "A" }?.id

        // Same URL re-imported: the dead filter lets it through, the fresh
        // row REPLACEs on rssFeedUrl/title and the rowid rotates (the shipped
        // quirk the M1 note pins — this is why the filter stays broken).
        importer = PodcastImporter(database: database, fetcher: FakeFetcher(batches: [[a]]))
        await importer.importByURLs(["https://a.example/f"], reportsProgress: true)

        rows = try await database.subscriptionRepository().listAll()
        #expect(rows.count == 2)   // B untouched
        let rewritten = rows.first { $0.title == "A" }
        #expect(rewritten?.rssFeedUrl == "https://a.example/f")
        #expect(rewritten?.id != idBefore)   // REPLACE → new rowid
    }

    @Test("Failed re-import leaves the stored row (and its id) untouched")
    func failedReImportKeepsRow() async throws {
        let (database, databaseURL) = try await makeDatabase()
        defer { try? FileManager.default.removeItem(at: databaseURL) }
        let a = podcast(url: "https://a.example/f", title: "A")

        var importer = PodcastImporter(database: database, fetcher: FakeFetcher(batches: [[a]]))
        await importer.importByURLs(["https://a.example/f"], reportsProgress: true)
        var rows = try await database.subscriptionRepository().listAll()
        let idBefore = rows.first?.id
        #expect(rows.count == 1)

        // The re-fetch fails (network error / unparsable feed → nil): the
        // engine writes nothing, so ids do not change.
        importer = PodcastImporter(database: database, fetcher: FakeFetcher(batches: [[nil]]))
        await importer.importByURLs(["https://a.example/f"], reportsProgress: true)

        rows = try await database.subscriptionRepository().listAll()
        #expect(rows.count == 1)
        #expect(rows.first?.id == idBefore)
    }

    // MARK: - State machine + progress (TempResult semantics)

    @Test("OPML flow: idle → importing(0) → importing(batchStart/total) → finished")
    func progressPhases() async throws {
        let (database, databaseURL) = try await makeDatabase()
        defer { try? FileManager.default.removeItem(at: databaseURL) }
        let a = podcast(url: "https://a.example/f", title: "A")
        let c = podcast(url: "https://c.example/f", title: "C")

        let importer = PodcastImporter(
            database: database,
            fetcher: FakeFetcher(batches: [[a, nil, c, nil, nil, nil, nil, nil], [nil, nil]])
        )
        var phases: [PodcastImporter.Phase] = []
        importer.onPhaseChange = { phases.append($0) }

        await importer.importByURLs((0..<10).map { "https://u\($0).example/f" }, reportsProgress: true)

        // TempResult sends the batch START index: 0 for the first 8-URL
        // batch, 8 for the second — so the ring lags one batch behind.
        #expect(phases == [
            .importing(progress: 0),
            .importing(progress: 0.0),
            .importing(progress: 0.8),
            .finished(PodcastImporter.Result(
                requestedURLCount: 10,
                importedSubscriptions: [a.subscription, c.subscription]
            )),
        ])
        #expect(importer.phase == phases.last)
    }

    @Test("Manual-URL flow: indeterminate importing, no progress ticks")
    func indeterminatePhases() async throws {
        let (database, databaseURL) = try await makeDatabase()
        defer { try? FileManager.default.removeItem(at: databaseURL) }
        let a = podcast(url: "https://a.example/f", title: "A")

        let importer = PodcastImporter(database: database, fetcher: FakeFetcher(batches: [[a]]))
        var phases: [PodcastImporter.Phase] = []
        importer.onPhaseChange = { phases.append($0) }

        await importer.importByURLs(["https://a.example/f"], reportsProgress: false)

        #expect(phases == [
            .importing(progress: nil),
            .finished(PodcastImporter.Result(
                requestedURLCount: 1,
                importedSubscriptions: [a.subscription]
            )),
        ])
    }

    @Test("Empty import (picker cancelled path / empty OPML): straight to finished")
    func emptyImport() async throws {
        let (database, databaseURL) = try await makeDatabase()
        defer { try? FileManager.default.removeItem(at: databaseURL) }
        let importer = PodcastImporter(database: database, fetcher: FakeFetcher(batches: []))
        await importer.importByURLs([], reportsProgress: true)

        guard case .finished(let result) = importer.phase else {
            Issue.record("expected finished")
            return
        }
        #expect(result.isEmpty)
        #expect(ImportCopy.needsInvalidFeedAlert(result))
    }

    // MARK: - Persistence parity (import_export.dart:96-103)

    @Test("First episodes of non-empty feeds land in the inbox table")
    func persistsFirstEpisodes() async throws {
        let (database, databaseURL) = try await makeDatabase()
        defer { try? FileManager.default.removeItem(at: databaseURL) }
        let withEpisodes = podcast(url: "https://a.example/f", title: "A", enclosure: "enc-a")
        let withoutEpisodes = podcast(url: "https://b.example/f", title: "B")

        let importer = PodcastImporter(database: database, fetcher: FakeFetcher(batches: [[withEpisodes, withoutEpisodes]]))
        await importer.importByURLs(["https://a.example/f", "https://b.example/f"], reportsProgress: true)

        let episodes = try await database.feedRepository().listAll()
        #expect(episodes.map(\.enclosureUrl) == ["enc-a"])
        let subscriptions = try await database.subscriptionRepository().listAll()
        #expect(subscriptions.map(\.title) == ["A", "B"])
    }

    // MARK: - Result text parity

    @Test("Batch flow text: joined titles, ', ' separator")
    func batchText() {
        #expect(ImportResultText.batchFlow(titles: ["A", "C"]) == "Import A, C successfully")
    }

    @Test("Batch flow text: all-failed import still toasts (Dart has no emptiness check)")
    func batchTextEmpty() {
        #expect(ImportResultText.batchFlow(titles: []) == "Import  successfully")
    }

    @Test("Batch flow text: >50 UTF-16 code units truncate to 50 + '...'")
    func batchTextTruncation() {
        let titles = [String(repeating: "a", count: 30), String(repeating: "b", count: 30)]
        // joined = 30 a's + ", " + 30 b's = 62 UTF-16 units → the first 50
        // (= 30 a's + ", " + 18 b's) survive, then "...".
        let joined = titles.joined(separator: ", ")
        let truncated = String(decoding: Array(joined.utf16.prefix(50)), as: UTF16.self)
        #expect(ImportResultText.batchFlow(titles: titles) == "Import \(truncated)... successfully")
        // A short join stays whole.
        #expect(
            ImportResultText.batchFlow(titles: ["short", "list"])
                == "Import short, list successfully"
        )
    }

    @Test("Manual flow text: single title, untruncated; nil title tolerated (K4)")
    func manualText() {
        #expect(ImportResultText.manualURLFlow(title: "Some Podcast") == "Import Some Podcast successfully")
        #expect(ImportResultText.manualURLFlow(title: nil) == "Import  successfully")
        let long = String(repeating: "x", count: 80)
        #expect(ImportResultText.manualURLFlow(title: long) == "Import \(long) successfully")
    }

    @Test("Invalid-URL alert copy (import_export.dart:198-225)")
    func invalidURLCopy() {
        #expect(ImportCopy.invalidFeedURLTitle == "Error")
        #expect(ImportCopy.invalidFeedURLMessage == "Invalid RSS Feed URL")
        #expect(ImportCopy.okButton == "OK")
        let empty = PodcastImporter.Result(requestedURLCount: 1, importedSubscriptions: [])
        let filled = PodcastImporter.Result(
            requestedURLCount: 1,
            importedSubscriptions: [SubscriptionRow(rssFeedUrl: "u", title: "T")]
        )
        #expect(ImportCopy.needsInvalidFeedAlert(empty))
        #expect(!ImportCopy.needsInvalidFeedAlert(filled))
    }

    @Test("Partial failure counts: requested vs imported vs failed")
    func partialFailureCounts() async throws {
        let (database, databaseURL) = try await makeDatabase()
        defer { try? FileManager.default.removeItem(at: databaseURL) }
        let a = podcast(url: "https://a.example/f", title: "A")
        let c = podcast(url: "https://c.example/f", title: "C")
        let importer = PodcastImporter(database: database, fetcher: FakeFetcher(batches: [[a, nil, c]]))
        await importer.importByURLs(["a", "b", "c"], reportsProgress: false)

        guard case .finished(let result) = importer.phase else {
            Issue.record("expected finished")
            return
        }
        #expect(result.requestedURLCount == 3)
        #expect(result.failedURLCount == 1)
        #expect(result.titles == ["A", "C"])
    }
}
