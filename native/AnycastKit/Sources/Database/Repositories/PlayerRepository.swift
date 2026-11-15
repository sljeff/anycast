import Foundation
import GRDB

// MARK: - Player pointer

public struct PlayerRepository: Sendable {
    let database: AppDatabase
    init(database: AppDatabase) { self.database = database }

    /// K31: a missing row is the value "no playback state", never an error
    /// (the old `maps[0]` crash is fixed by contract).
    @concurrent
    public func loadPointer() async throws -> PlayerPointer? {
        try await database.queue.read { db in
            let row = try PlayerRow.fetchOne(db, sql: "SELECT * FROM player WHERE id = 1")
            return row.map { PlayerPointer(currentPlaylistId: $0.currentPlaylistId) }
        }
    }

    /// `INSERT OR REPLACE` on row id=1 (player.dart:44-46).
    @concurrent
    public func updatePointer(currentPlaylistId: Int64?) async throws {
        try await database.queue.write { db in
            try db.execute(
                sql: "INSERT OR REPLACE INTO player (id, currentPlaylistId) VALUES (1, ?)",
                arguments: [currentPlaylistId]
            )
        }
    }

    /// `clear()` deletes the row; it is re-created idempotently at next open.
    @concurrent
    public func clear() async throws {
        try await database.queue.write { db in
            try db.execute(sql: "DELETE FROM player WHERE id = 1")
        }
    }
}
