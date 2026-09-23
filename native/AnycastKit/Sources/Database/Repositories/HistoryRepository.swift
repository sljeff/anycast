import Foundation
import GRDB

// MARK: - History (historyEpisode)

public struct HistoryRepository: Sendable {
    let database: AppDatabase
    init(database: AppDatabase) { self.database = database }

    /// "Latest" = ORDER BY id DESC — NOT pubDate (K12).
    @concurrent
    public func listAll() async throws -> [HistoryEpisodeRow] {
        try await database.queue.read { db in
            try HistoryEpisodeRow.fetchAll(db, sql: "SELECT * FROM historyEpisode ORDER BY id DESC")
        }
    }

    /// Re-inserting keeps the id the caller carries: the Dart line passed
    /// `HistoryEpisodeModel.fromMap(playlistEpisode.toMap())`, so the
    /// history row's id IS the playlist row's id, and a resume re-insert
    /// (delete + INSERT with the explicit id) leaves both the id and the
    /// row's place in the id-DESC ordering unchanged (K30, corrected
    /// 2026-09-23; sqflite-verified). A nil id autoincrements, mirroring
    /// Dart's toMap omitting a null id. Both statements run in one
    /// transaction (08 §1.2 — same final state, no crash window).
    @concurrent
    public func insert(_ episode: HistoryEpisodeRow) async throws {
        try await database.queue.write { db in
            try db.execute(
                sql: "DELETE FROM historyEpisode WHERE enclosureUrl = ?",
                arguments: [episode.enclosureUrl]
            )
            var copy = episode
            try copy.insert(db, onConflict: .replace)
        }
    }

    @concurrent
    public func deleteMany(_ urls: [String]) async throws {
        try await database.queue.write { db in
            try deleteByEnclosureUrls(db, table: "historyEpisode", urls: urls)
        }
    }

    @discardableResult
    @concurrent
    public func trim(keeping max: Int64) async throws -> [String] {
        try await database.queue.write { db in
            let rows = try HistoryEpisodeRow.fetchAll(
                db, sql: "SELECT * FROM historyEpisode ORDER BY id DESC"
            )
            guard rows.count > max else { return [] }
            let removed = rows.dropFirst(Int(max)).compactMap(\.enclosureUrl)
            try deleteByEnclosureUrls(db, table: "historyEpisode", urls: removed)
            return removed
        }
    }
}
