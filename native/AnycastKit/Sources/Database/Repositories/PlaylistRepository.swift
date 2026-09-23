import Foundation
import GRDB

// MARK: - Playlist + queue episodes

public struct PlaylistRepository: Sendable {
    let database: AppDatabase
    init(database: AppDatabase) { self.database = database }

    @concurrent
    public func listPlaylists() async throws -> [PlaylistRow] {
        try await database.queue.read { db in
            try PlaylistRow.fetchAll(db, sql: "SELECT * FROM playlist ORDER BY position ASC")
        }
    }

    /// The playback queue: ORDER BY position ASC. episodes[0] is the current
    /// track (K3).
    @concurrent
    public func listEpisodes(playlistId: Int64) async throws -> [PlaylistEpisodeRow] {
        try await database.queue.read { db in
            try PlaylistEpisodeRow.fetchAll(
                db, sql: "SELECT * FROM playlistEpisode WHERE playlistId = ? ORDER BY position ASC",
                arguments: [playlistId]
            )
        }
    }

    @concurrent
    public func episode(byEnclosureURL url: String) async throws -> PlaylistEpisodeRow? {
        try await database.queue.read { db in
            try PlaylistEpisodeRow.fetchOne(
                db, sql: "SELECT * FROM playlistEpisode WHERE enclosureUrl = ?", arguments: [url]
            )
        }
    }

    /// Add-or-move at `index` (the data-layer half of
    /// `insertOrUpdateByIndex`, states/playlist_episode.dart `add`/`move`).
    ///
    /// - New episode: the G1/G2 golden insert algorithm.
    /// - Existing episode: K26-fixed move semantics — neighbors from the
    ///   post-move list, so a downward move persists instead of silently
    ///   reverting after restart.
    @concurrent
    public func insertOrUpdateByIndex(
        _ episode: PlaylistEpisodeRow,
        playlistId: Int64,
        index: Int
    ) async throws {
        try await database.queue.write { db in
            guard let enclosureUrl = episode.enclosureUrl else { return }

            let ordered = try PlaylistEpisodeRow.fetchAll(
                db,
                sql: "SELECT * FROM playlistEpisode WHERE playlistId = ? ORDER BY position ASC",
                arguments: [playlistId]
            )
            // Index-aligned with `ordered` — a NULL-position row stays in
            // place as nil ("no neighbor on that side"), exactly how Dart
            // reads `episodes[i].position`.
            let positions = ordered.map(\.position)

            if let existingIndex = ordered.firstIndex(where: { $0.enclosureUrl == enclosureUrl }) {
                // Move (K26): index is the target slot in the post-move list
                // where the item still occupies its old slot — exactly the
                // `move(from:to:)` convention.
                let result = PlaylistPositioning.movePosition(
                    from: existingIndex, to: index, orderedPositions: positions
                )
                var moved = ordered[existingIndex]
                moved.position = result.position
                moved.playlistId = playlistId
                try moved.update(db)
                if result.needsReorder {
                    try renumber(db: db, playlistId: playlistId)
                }
            } else {
                // K14: the UNIQUE(enclosureUrl) constraint is table-global,
                // so dedup must be too — the same episode added from another
                // playlist MOVES here (K14 ruling: 跨列表 = 移动到新列表).
                // The shipped Dart looked the row up table-wide via
                // getByEnclosureUrl and updated it (keeping the old
                // playlistId); a plain INSERT here would throw on the
                // constraint instead.
                let existingRow = try PlaylistEpisodeRow.fetchOne(
                    db,
                    sql: "SELECT * FROM playlistEpisode WHERE enclosureUrl = ? ORDER BY id LIMIT 1",
                    arguments: [enclosureUrl]
                )
                // Insert: byte-identical old algorithm against the list
                // without the episode (G1/G2).
                let result = PlaylistPositioning.insertPosition(at: index, orderedPositions: positions)
                if var moved = existingRow {
                    moved.playlistId = playlistId
                    moved.position = result.position
                    try moved.update(db)
                } else {
                    var inserted = episode
                    inserted.id = nil
                    inserted.playlistId = playlistId
                    inserted.position = result.position
                    try inserted.insert(db)
                }
                if result.needsReorder {
                    try renumber(db: db, playlistId: playlistId)
                }
            }
        }
    }

    private func renumber(db: Database, playlistId: Int64) throws {
        let ordered = try PlaylistEpisodeRow.fetchAll(
            db,
            sql: "SELECT * FROM playlistEpisode WHERE playlistId = ? ORDER BY position ASC",
            arguments: [playlistId]
        )
        for (offset, var row) in ordered.enumerated() {
            row.position = Double(offset)
            try row.update(db)
        }
    }

    /// Remove one queue entry plus its subtitle and translation rows — one
    /// transaction (08 §1.2). Cache file deletion belongs to the cache store
    /// (M2) and stays outside the transaction.
    @concurrent
    public func removeEpisodeCascade(byEnclosureURL enclosureUrl: String) async throws {
        try await database.queue.write { db in
            try db.execute(
                sql: "DELETE FROM playlistEpisode WHERE enclosureUrl = ?", arguments: [enclosureUrl]
            )
            try db.execute(
                sql: "DELETE FROM subtitle WHERE enclosureUrl = ?", arguments: [enclosureUrl]
            )
            try db.execute(
                sql: "DELETE FROM translation WHERE enclosureUrl = ?", arguments: [enclosureUrl]
            )
        }
    }

    /// `UPDATE playlistEpisode SET playedDuration = ? WHERE enclosureUrl = ?`
    /// — matches the queue head by URL, not by id (playlist_episode.dart:154-157).
    @concurrent
    public func updatePlayedDuration(_ milliseconds: Int64, byEnclosureURL url: String) async throws {
        try await database.queue.write { db in
            try db.execute(
                sql: "UPDATE playlistEpisode SET playedDuration = ? WHERE enclosureUrl = ?",
                arguments: [milliseconds, url]
            )
        }
    }
}
