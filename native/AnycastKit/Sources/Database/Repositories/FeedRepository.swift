import Foundation
import GRDB

// MARK: - Inbox (feedEpisode)

public struct FeedRepository: Sendable {
    let database: AppDatabase
    init(database: AppDatabase) { self.database = database }

    /// ORDER BY pubDate DESC (feed_episode.dart:55).
    @concurrent
    public func listAll() async throws -> [FeedEpisodeRow] {
        try await database.queue.read { db in
            try FeedEpisodeRow.fetchAll(db, sql: "SELECT * FROM feedEpisode ORDER BY pubDate DESC")
        }
    }

    /// The inbox rows of one show, newest first. Read-only: the Channel page
    /// shows these while its network fetch runs.
    @concurrent
    public func list(byRSSFeedURL rssFeedURL: String) async throws -> [FeedEpisodeRow] {
        try await database.queue.read { db in
            try FeedEpisodeRow.fetchAll(
                db,
                sql: "SELECT * FROM feedEpisode WHERE rssFeedUrl = ? ORDER BY pubDate DESC",
                arguments: [rssFeedURL]
            )
        }
    }

    /// Batch INSERT OR REPLACE keyed on the enclosureUrl unique constraint
    /// (feed_episode.dart:79-87); one transaction, like the sqflite batch.
    @concurrent
    public func insertMany(_ episodes: [FeedEpisodeRow]) async throws {
        try await database.queue.write { db in
            for episode in episodes {
                try episode.insert(db, onConflict: .replace)
            }
        }
    }

    @concurrent
    public func removeByEnclosureUrls(_ urls: [String]) async throws {
        try await database.queue.write { db in
            try deleteByEnclosureUrls(db, table: "feedEpisode", urls: urls)
        }
    }

    /// 60s trim: keep the newest `max` rows in list order (pubDate DESC),
    /// delete the rest (states/feed_episode.dart:134-148). Returns the
    /// removed enclosureUrls.
    @discardableResult
    @concurrent
    public func trim(keeping max: Int64) async throws -> [String] {
        try await database.queue.write { db in
            let rows = try FeedEpisodeRow.fetchAll(
                db, sql: "SELECT * FROM feedEpisode ORDER BY pubDate DESC"
            )
            guard rows.count > max else { return [] }
            let removed = rows.dropFirst(Int(max)).compactMap(\.enclosureUrl)
            try deleteByEnclosureUrls(db, table: "feedEpisode", urls: removed)
            return removed
        }
    }
}
