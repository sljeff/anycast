import Foundation
import GRDB

// MARK: - History (historyEpisode)

public struct HistoryRepository: Sendable {
    let database: AppDatabase
    init(database: AppDatabase) { self.database = database }

    /// Latest play first. `id` is only a tie-break: it is the history row's
    /// own rowid, not a playlist id and not a timestamp.
    @concurrent
    public func listAll() async throws -> [HistoryEpisodeRow] {
        try await database.queue.read { db in
            try HistoryEpisodeRow.fetchAll(
                db,
                sql: "SELECT * FROM historyEpisode ORDER BY lastPlayedAt DESC, id DESC"
            )
        }
    }

    @concurrent
    public func count() async throws -> Int {
        try await database.queue.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM historyEpisode") ?? 0
        }
    }

    /// Upsert by `enclosureUrl`. A caller-supplied `id` is ignored so a
    /// playlist rowid can never REPLACE a different history row. Re-listening
    /// bumps `lastPlayedAt` (or `episode.lastPlayedAt` when a test pins it)
    /// and keeps the existing history primary key.
    @concurrent
    public func insert(_ episode: HistoryEpisodeRow) async throws {
        guard let enclosureUrl = episode.enclosureUrl, !enclosureUrl.isEmpty else { return }
        let playedAt = episode.lastPlayedAt
            ?? Int64(Date().timeIntervalSince1970 * 1000)
        try await database.queue.write { db in
            try db.execute(
                sql: """
                INSERT INTO historyEpisode (
                  title, description, duration, enclosureUrl, pubDate, imageUrl,
                  channelTitle, rssFeedUrl, lastPlayedAt
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(enclosureUrl) DO UPDATE SET
                  title = excluded.title,
                  description = excluded.description,
                  duration = excluded.duration,
                  pubDate = excluded.pubDate,
                  imageUrl = excluded.imageUrl,
                  channelTitle = excluded.channelTitle,
                  rssFeedUrl = excluded.rssFeedUrl,
                  lastPlayedAt = excluded.lastPlayedAt
                """,
                arguments: [
                    episode.title,
                    episode.description,
                    episode.duration,
                    enclosureUrl,
                    episode.pubDate,
                    episode.imageUrl,
                    episode.channelTitle,
                    episode.rssFeedUrl,
                    playedAt,
                ]
            )
        }
    }

    @concurrent
    public func deleteMany(_ urls: [String]) async throws {
        try await database.queue.write { db in
            try deleteByEnclosureUrls(db, table: "historyEpisode", urls: urls)
        }
    }

    /// Drops the oldest plays past `max`, ordered by `lastPlayedAt`.
    @discardableResult
    @concurrent
    public func trim(keeping max: Int64) async throws -> [String] {
        try await database.queue.write { db in
            let rows = try HistoryEpisodeRow.fetchAll(
                db,
                sql: "SELECT * FROM historyEpisode ORDER BY lastPlayedAt DESC, id DESC"
            )
            guard rows.count > max else { return [] }
            let removed = rows.dropFirst(Int(max)).compactMap(\.enclosureUrl)
            try deleteByEnclosureUrls(db, table: "historyEpisode", urls: removed)
            return removed
        }
    }
}
