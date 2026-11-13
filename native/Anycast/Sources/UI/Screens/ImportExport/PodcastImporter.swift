import Foundation
import AnycastKit

/// RSS batch fetch abstraction over `RSSFetcher` so the import is testable
/// against scripted results (the production default constructs the real
/// fetcher with the pinned K20 browser UA).
protocol PodcastFetchProviding: Sendable {
    func fetchPodcasts(
        urls: [String],
        onlyFirstEpisode: Bool,
        onBatch: (@Sendable (Int, Int, [PodcastImportData?]) -> Void)?
    ) async -> [PodcastImportData]
}

extension RSSFetcher: PodcastFetchProviding {}

// MARK: - Plan (the confirm step)

/// What an import would do, before anything is fetched: the shows to bring
/// in, and how many in the file are already followed. Shows are matched by
/// feed address, so a followed show is skipped instead of re-fetched and
/// rewritten.
nonisolated struct ImportPlan: Equatable {
    var entries: [OPMLParser.Entry]
    var alreadyFollowed: Int

    /// Every show in the file is already followed (and the file had shows).
    var isAllFollowed: Bool { entries.isEmpty && alreadyFollowed > 0 }

    /// The file held no feed address at all.
    var isEmptyFile: Bool { entries.isEmpty && alreadyFollowed == 0 }

    static func make(entries: [OPMLParser.Entry], followedURLs: [String]) -> ImportPlan {
        let followed = Set(followedURLs.map(feedKey))
        var seen = Set<String>()
        var fresh: [OPMLParser.Entry] = []
        var skipped = 0
        for entry in entries {
            let key = feedKey(entry.xmlURL)
            // The same address twice in one file counts once.
            guard seen.insert(key).inserted else { continue }
            if followed.contains(key) {
                skipped += 1
            } else {
                fresh.append(entry)
            }
        }
        return ImportPlan(entries: fresh, alreadyFollowed: skipped)
    }

    /// Identity of a feed address: host and path without the scheme, the case
    /// of the host, a trailing slash or a fragment. Stored values are never
    /// rewritten with this; it only decides whether two addresses are the
    /// same feed.
    static func feedKey(_ url: String) -> String {
        let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let components = URLComponents(string: trimmed), let host = components.host else {
            return trimmed.lowercased()
        }
        var path = components.percentEncodedPath
        while path.count > 1, path.hasSuffix("/") { path.removeLast() }
        if path == "/" { path = "" }
        let port = components.port.map { ":\($0)" } ?? ""
        let query = components.percentEncodedQuery.map { "?\($0)" } ?? ""
        return host.lowercased() + port + path + query
    }

    /// Whether the address can be fetched at all.
    static func isWebAddress(_ url: String) -> Bool {
        let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let components = URLComponents(string: trimmed),
              let scheme = components.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let host = components.host, !host.isEmpty
        else { return false }
        return true
    }
}

// MARK: - Outcome

/// Why one show did not come in. The fetcher reports only "no feed came
/// back", so apart from an address that is not a web address, every failure
/// reads the same.
nonisolated enum ImportFailureReason: Equatable {
    case invalidAddress
    case unreachable

    var text: String {
        switch self {
        case .invalidAddress: return "Not a web address"
        case .unreachable: return "Couldn\u{2019}t be reached"
        }
    }
}

nonisolated struct ImportFailure: Equatable {
    var entry: OPMLParser.Entry
    var reason: ImportFailureReason
}

nonisolated struct ImportOutcome: Equatable {
    /// Shows now followed because of this run.
    var imported: [SubscriptionRow] = []
    var failures: [ImportFailure] = []
    /// A database write failed: nothing was persisted.
    var writeFailed = false
    /// The run was cancelled before the write: nothing was persisted.
    var cancelled = false
    /// Episodes this run added to the Inbox.
    var addedEpisodeCount = 0

    var failedEntries: [OPMLParser.Entry] { failures.map(\.entry) }
}

// MARK: - Importer

/// Fetch every address (8 at a time, 10 s each, 2 attempts: the fetcher's
/// own limits), then write once. Nothing touches the database until every
/// fetch has finished, so cancelling before that point imports nothing.
/// Both writes (the newest episode of each show, then the subscriptions) are
/// single transactions; a failure means nothing was persisted.
@MainActor
final class PodcastImporter {

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

    /// Splits `entries` into shows to import and shows already followed.
    /// An unreadable subscription list counts as "none followed": nothing is
    /// skipped, nothing is lost.
    func plan(entries: [OPMLParser.Entry]) async -> ImportPlan {
        let existing = (try? await database.subscriptionRepository().listAll()) ?? []
        return ImportPlan.make(entries: entries, followedURLs: existing.compactMap(\.rssFeedUrl))
    }

    /// `onProgress(finished, answered)`: how many addresses have answered,
    /// and the indices into `entries` that just did, with whether a feed
    /// came back. Called on the main actor, batch by batch.
    func run(
        _ entries: [OPMLParser.Entry],
        onProgress: (@MainActor (_ finished: Int, _ answered: [(index: Int, ok: Bool)]) -> Void)? = nil
    ) async -> ImportOutcome {
        var outcome = ImportOutcome()

        // Addresses that cannot be fetched fail without a request.
        var fetchable: [(index: Int, entry: OPMLParser.Entry)] = []
        var invalidIndices: [Int] = []
        for (index, entry) in entries.enumerated() {
            if ImportPlan.isWebAddress(entry.xmlURL) {
                fetchable.append((index, entry))
            } else {
                invalidIndices.append(index)
                outcome.failures.append(ImportFailure(entry: entry, reason: .invalidAddress))
            }
        }
        let invalid = invalidIndices.count
        if invalid > 0 {
            onProgress?(invalid, invalidIndices.map { ($0, false) })
        }

        let urls = fetchable.map(\.entry.xmlURL)
        let indices = fetchable.map(\.index)
        let fetched = await fetcher.fetchPodcasts(urls: urls, onlyFirstEpisode: true) { batchStart, _, results in
            let answered = results.enumerated().map { offset, result in
                (index: indices[batchStart + offset], ok: result != nil)
            }
            let finished = invalid + batchStart + results.count
            Task { @MainActor in onProgress?(finished, answered) }
        }

        // Cancelled while fetching: the fetch results are dropped, and the
        // database has not been touched.
        guard !Task.isCancelled else {
            outcome.cancelled = true
            outcome.failures = []
            return outcome
        }

        let byURL = Dictionary(
            fetched.compactMap { data in data.subscription.rssFeedUrl.map { ($0, data) } },
            uniquingKeysWith: { first, _ in first }
        )
        var imported: [PodcastImportData] = []
        for (_, entry) in fetchable {
            if let data = byURL[entry.xmlURL] {
                imported.append(data)
            } else {
                outcome.failures.append(ImportFailure(entry: entry, reason: .unreachable))
            }
        }

        // Episodes first, then subscriptions (the order the show page's
        // Follow uses), each one transaction.
        let firstEpisodes = imported.compactMap(\.feedEpisodes.first)
        var written = true
        if !firstEpisodes.isEmpty {
            written = (try? await database.feedRepository().insertMany(firstEpisodes)) != nil
        }
        if written, !imported.isEmpty {
            written = (try? await database.subscriptionRepository()
                .addMany(imported.map(\.subscription))) != nil
        }
        guard written else {
            outcome.writeFailed = true
            return outcome
        }

        outcome.imported = imported.map(\.subscription)
        outcome.addedEpisodeCount = firstEpisodes.count
        if !imported.isEmpty {
            // The shows shelf reloads.
            NotificationCenter.default.post(name: ShowsShelfLayout.subscriptionsDidChange, object: nil)
        }
        return outcome
    }
}

// MARK: - Inbox trim hold

/// The Inbox trims episodes over its limit every 60 s. An import adds one
/// episode per show, so the trim waits while an import runs and until the
/// person has seen the result and tapped Done.
@MainActor
enum InboxTrimHold {
    private(set) static var holders = 0

    static var isHeld: Bool { holders > 0 }

    static func acquire() { holders += 1 }

    static func release() { holders = max(0, holders - 1) }
}

// MARK: - Copy

/// Every string of the import sheet and the export row, in one place.
nonisolated enum ImportCopy {

    static func shows(_ count: Int) -> String { count == 1 ? "1 show" : "\(count) shows" }

    // Confirm
    static func confirmTitle(count: Int) -> String { "Import \(shows(count))" }
    static let noFeedsTitle = "No podcast feeds in this file."
    static func allFollowedTitle(total: Int) -> String {
        total == 1 ? "You already follow this show." : "You already follow all \(total)."
    }
    static func confirmSubtitle(filename: String?, alreadyFollowed: Int) -> String {
        var parts: [String] = []
        if let filename, !filename.isEmpty { parts.append("From \(filename)") }
        if alreadyFollowed > 0 { parts.append("\(alreadyFollowed) already followed") }
        return parts.joined(separator: " \u{00B7} ")
    }
    static func confirmButton(count: Int) -> String { "Import \(shows(count))" }
    static let chooseAnotherFile = "Choose another file"
    static let chooseFile = "Choose a file"
    static let done = "Done"
    static let cancel = "Cancel"

    // Progress
    static func progressCount(finished: Int, total: Int) -> String { "\(finished) of \(total)" }

    // Result
    static func resultTitle(imported: Int) -> String {
        imported == 0 ? "No shows imported" : "\(shows(imported)) imported"
    }
    static func failedSummary(count: Int) -> String { "\(count) couldn\u{2019}t be reached" }
    static func retryButton(count: Int) -> String { "Try \(count) again" }
    static let writeFailedTitle = "Couldn\u{2019}t save. Nothing was imported."

    /// The Inbox-limit line; nil when nothing will leave the Inbox.
    static func inboxLimitNote(inboxCount: Int, limit: Int) -> String? {
        let removed = inboxCount - limit
        guard removed > 0 else { return nil }
        let older = removed == 1 ? "1 older one" : "\(removed) older ones"
        return "Your Inbox keeps the latest \(limit) episodes, so \(older) will leave it. "
            + "The shows stay in Library."
    }

    // Export
    static let exportFileName = "Anycast Subscriptions.opml"
    static let exportFailed = "Couldn\u{2019}t create the file. Try again."
    static let exportEmpty = "No shows yet"
    static let exportFooter =
        "Export covers the shows you follow. Playlist, history and transcripts stay on this iPhone."
}
