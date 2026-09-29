import Foundation
import AnycastKit

/// RSS batch fetch abstraction over `RSSFetcher` so the import state machine
/// is testable against scripted results (the production default constructs
/// the real fetcher with the pinned K20 browser UA).
protocol PodcastFetchProviding: Sendable {
    func fetchPodcasts(
        urls: [String],
        onlyFirstEpisode: Bool,
        onBatch: (@Sendable (Int, Int, [PodcastImportData?]) -> Void)?
    ) async -> [PodcastImportData]
}

extension RSSFetcher: PodcastFetchProviding {}

/// importPodcastsByUrls + the widget-side persistence
/// (lib/utils/rss_fetcher.dart:20-31, import_export.dart:86-115/195-238,
/// share.dart:78-104): fetch each URL's first episode, persist subscriptions
/// (INSERT OR REPLACE — K13 same-title eviction) and the newest inbox episode,
/// and expose the dialog state machine idle → importing(progress) → finished.
@MainActor
final class PodcastImporter {

    // Nonisolated: pure value types crossing into the nonisolated copy
    // helpers below (default-isolation escape hatch).
    nonisolated struct Result: Equatable {
        var requestedURLCount: Int
        var importedSubscriptions: [SubscriptionRow]
        /// A database write failed: nothing was persisted, and the
        /// completion copy must not claim success (Dart had no path here —
        /// its write errors propagated up the stack).
        var writeFailed: Bool = false

        var failedURLCount: Int { requestedURLCount - importedSubscriptions.count }
        var titles: [String] { importedSubscriptions.map { $0.title ?? "" } }
        var isEmpty: Bool { importedSubscriptions.isEmpty }
    }

    nonisolated enum Phase: Equatable {
        case idle
        /// `progress` nil = indeterminate (the manual-URL flow passes no
        /// onProgress, Dart shows a plain spinner).
        case importing(progress: Double?)
        case finished(Result)
    }

    private(set) var phase: Phase = .idle {
        didSet { onPhaseChange?(phase) }
    }

    var onPhaseChange: (@MainActor (Phase) -> Void)?

    private let database: AppDatabase
    private let fetcher: any PodcastFetchProviding

    init(
        database: AppDatabase,
        fetcher: any PodcastFetchProviding =
            RSSFetcher(client: HTTPClient(), userAgent: AppConfiguration.rssUserAgent)
    ) {
        self.database = database
        self.fetcher = fetcher
    }

    /// Port of the URL pre-filter (rss_fetcher.dart:24-28).
    ///
    ///     var s = Set.from(existingSubscriptions.map((e) => e.rssFeedUrl));
    ///     s = {};
    ///     rssFeedUrls = rssFeedUrls.where((element) => !s.contains(element)).toList();
    ///
    /// The `s = {}` dead store is preserved VERBATIM (docs/migration/
    /// 00-execution-plan.md, 2026-09-23 second-review "recorded, not
/// fixed" note):
    /// the shipped app never actually excludes existing subscriptions, so
    /// every re-import re-fetches and re-writes the rows (title/rssFeedUrl
    /// UNIQUE REPLACE, K13). "Fixing" the filter would change which rows get
    /// rewritten on re-import — a data-behavior change, not a bug fix.
    static func filterExisting(urls: [String], existingSubscriptions: [SubscriptionRow]) -> [String] {
        let existing = Set(existingSubscriptions.compactMap(\.rssFeedUrl))
        _ = existing   // built, then discarded — the quirk itself
        let s: Set<String> = []
        return urls.filter { !s.contains($0) }
    }

    /// One import run. `reportsProgress` distinguishes the two Dart flows:
    /// OPML/share imports feed the progress ring (onProgress → value/total),
    /// the manual-URL import shows an indeterminate spinner (no onProgress).
    func importByURLs(_ urls: [String], reportsProgress: Bool) async {
        phase = .importing(progress: reportsProgress ? 0 : nil)

        let existing = (try? await database.subscriptionRepository().listAll()) ?? []
        let fetchList = Self.filterExisting(urls: urls, existingSubscriptions: existing)

        let fetched = await fetcher.fetchPodcasts(
            urls: fetchList,
            onlyFirstEpisode: true
        ) { [weak self] batchStart, total, _ in
            guard reportsProgress, total > 0 else { return }
            let value = Double(batchStart) / Double(total)
            Task { @MainActor in
                self?.updateProgressIfImporting(value)
            }
        }

        // Widget post-processing parity: first episodes of non-empty feeds,
        // FeedEpisodeController.addMany BEFORE SubscriptionController.addMany
        // (import_export.dart:96-103, share.dart:86-92). Both writes are
        // single transactions — a failure means nothing was persisted, and
        // the result must say so instead of reporting the fetched rows as
        // imported.
        let firstEpisodes = fetched
            .filter { !$0.feedEpisodes.isEmpty }
            .map { $0.feedEpisodes[0] }
        var episodesWritten = true
        if !firstEpisodes.isEmpty {
            episodesWritten = (try? await database.feedRepository().insertMany(firstEpisodes)) != nil
        }
        var subscriptionsWritten = true
        if !fetched.isEmpty {
            subscriptionsWritten = (try? await database.subscriptionRepository()
                .addMany(fetched.map(\.subscription))) != nil
        }

        guard episodesWritten, subscriptionsWritten else {
            phase = .finished(Result(
                requestedURLCount: fetchList.count,
                importedSubscriptions: [],
                writeFailed: true
            ))
            return
        }
        if !fetched.isEmpty {
            // The resident Subscriptions page reloads (Obx equivalent).
            NotificationCenter.default.post(
                name: SubscriptionsPageViewController.subscriptionsDidChange,
                object: nil
            )
        }

        phase = .finished(Result(
            requestedURLCount: fetchList.count,
            importedSubscriptions: fetched.map(\.subscription)
        ))
    }

    private func updateProgressIfImporting(_ value: Double) {
        guard case .importing = phase else { return }
        phase = .importing(progress: min(max(value, 0), 1))
    }
}

/// Snackbar text parity (import_export.dart:106-115/234-237, share.dart:98-104):
/// OPML/share imports join every title and truncate at 50 UTF-16 code units
/// (Dart `String.length`/`substring` count UTF-16 — the port slices the same
/// units, lone surrogates included); the manual-URL flow shows the single
/// first title untruncated.
nonisolated enum ImportResultText {

    /// "Import <titles> successfully" — the joined, 50-unit-truncated form.
    static func batchFlow(titles: [String]) -> String {
        var joined = titles.joined(separator: ", ")
        if joined.utf16.count > 50 {
            joined = String(decoding: Array(joined.utf16.prefix(50)), as: UTF16.self) + "..."
        }
        return "Import \(joined) successfully"
    }

    /// "Import <title> successfully" — manual URL import of the first result
    /// (Dart force-unwrapped the title; an imported feed with nil title is
    /// the K4 tolerance and renders empty).
    static func manualURLFlow(title: String?) -> String {
        "Import \(title ?? "") successfully"
    }
}

/// Dialog copy constants (03 §2.15).
nonisolated enum ImportCopy {
    static let invalidFeedURLTitle = "Error"
    static let invalidFeedURLMessage = "Invalid RSS Feed URL"
    static let okButton = "OK"
    /// Unparsable picked OPML — Dart left the progress dialog hanging (K4
    /// crash family); the port closes the overlay and surfaces the shipped
    /// "no valid links" copy instead.
    static let unparsableOPMLMessage = "Oh no! Seems like there is no valid links in the file."
    /// Database write failed during import — nothing was persisted, so the
    /// success toast must not fire (no Dart counterpart: its write errors
    /// propagated up the stack).
    static let importWriteFailedMessage = "Couldn't save the imported feeds. Please try again."
    /// Export could not read the subscriptions (or write the OPML file) —
    /// sharing an empty or stale file would look like a valid backup.
    static let exportWriteFailedMessage = "Couldn't save your subscriptions file. Please try again."

    /// The manual-URL flow alerts when the import returned nothing
    /// (import_export.dart:196-226).
    static func needsInvalidFeedAlert(_ result: PodcastImporter.Result) -> Bool {
        result.isEmpty
    }
}
