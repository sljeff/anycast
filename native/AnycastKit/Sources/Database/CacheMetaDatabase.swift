import Foundation
import GRDB

/// The audio-cache index database the Flutter fork of
/// flutter_cache_manager kept at
/// `Library/Application Support/anycast_episode.db` (docs/migration/01 §1.2).
///
/// Its whole purpose for the migration is **mapping**: file names are
/// UUIDv1 + mime extension and have no relation to URLs — the only
/// URL→file mapping lives here. Keeping the same schema and semantics (same
/// `touched`/`validTill` calibers) is a write-back requirement: a rolled-back
/// Flutter build must still recognize natively-downloaded files
/// (docs/migration/05 §2.4).
///
/// Semantics pinned against the real container fixture `db_device`
/// (2026-09-23 correction, docs/migration/01 §1.2/§4.1):
/// - the `key` column holds **the resource URL itself** row by row (it is
///   NOT the literal config cacheKey `anycast_episode` — that string only
///   names the database file and the file directory);
/// - real device databases carry **no** `cacheObjectkey` unique index, so
///   writable opens create none either;
/// - `validTill`/`touched` are Unix epoch **milliseconds**; `validTill`
///   derives from HTTP cache headers (Date + Cache-Control max-age) when
///   present, else from the 30-day stale period.
public struct CacheMetaDatabase: Sendable {

    public struct CacheObjectRow: Codable, Sendable, Equatable, FetchableRecord, PersistableRecord {
        public static let databaseTableName = "cacheObject"

        public var _id: Int64?
        public var url: String?
        /// Same value as `url` on every real row (the fork stores the
        /// resource URL here; see the type documentation).
        public var key: String?
        /// File NAME only (`<uuidv1>.<ext>`), resolved against
        /// `<Library/Caches>/<cacheKey>/` — never a path.
        public var relativePath: String?
        public var eTag: String?
        /// Unix epoch, MILLISECONDS (fork cache_object.dart:
        /// `DateTime.fromMillisecondsSinceEpoch`).
        public var validTill: Int64?
        /// Unix epoch milliseconds, updated on access — the LRU heartbeat
        /// (the fork compares against `millisecondsSinceEpoch`).
        public var touched: Int64?
        public var length: Int64?

        public enum CodingKeys: String, CodingKey {
            case _id = "_id"
            case url, key, relativePath, eTag, validTill, touched, length
        }
    }

    /// The fork's v3 schema, exactly as observed on real device databases
    /// (no `cacheObjectkey` index — db_device `sqlite_master`).
    static let createSQL = """
        CREATE TABLE IF NOT EXISTS cacheObject (
        _id INTEGER PRIMARY KEY,
        url TEXT,
        key TEXT,
        relativePath TEXT,
        eTag TEXT,
        validTill INTEGER,
        touched INTEGER,
        length INTEGER
        )
        """

    public let queue: DatabaseQueue?

    /// Tolerant reader open (L0 matrix): a missing or unreadable index means
    /// "no downloads mapped" — callers degrade to streaming, they never crash
    /// (docs/migration/05 §2.1). This flavor never fabricates a database.
    @concurrent
    public static func open(at url: URL) async -> CacheMetaDatabase {
        // DatabaseQueue CREATES an empty database at a missing path — the
        // tolerant reader must not (05 §2.1: missing meta DB means "no
        // downloads mapped").
        guard FileManager.default.fileExists(atPath: url.path) else {
            return CacheMetaDatabase(queue: nil)
        }
        return CacheMetaDatabase(queue: try? DatabaseQueue(path: url.path))
    }

    /// Writable open for the download path: creates the database (v3 schema)
    /// when absent. A rolled-back Flutter build reads whatever we wrote, so
    /// new downloads must be indexed even on a fresh install.
    @concurrent
    public static func openWritable(at url: URL) async throws -> CacheMetaDatabase {
        let directory = url.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let queue = try DatabaseQueue(path: url.path)
        let version = try await queue.read { db in
            try Int.fetchOne(db, sql: "PRAGMA user_version") ?? 0
        }
        if version == 0 {
            try await queue.write { db in
                try db.execute(sql: Self.createSQL)
                try db.execute(sql: "PRAGMA user_version = 3")
            }
        }
        return CacheMetaDatabase(queue: queue)
    }

    public init(queue: DatabaseQueue?) {
        self.queue = queue
    }

    public var isAvailable: Bool { queue != nil }

    // MARK: - Reads

    /// Row for a resource URL. The lookup is by `url` (== `key` on every
    /// real row) — the M1 `WHERE url = ? AND key = 'anycast_episode'` variant
    /// would never match real data.
    @concurrent
    public func entry(forURL url: String) async -> CacheObjectRow? {
        guard let queue else { return nil }
        return try? await queue.read { db in
            try CacheObjectRow.fetchOne(
                db,
                sql: "SELECT * FROM cacheObject WHERE url = ? ORDER BY _id LIMIT 1",
                arguments: [url]
            )
        }
    }

    @concurrent
    public func allRows() async -> [CacheObjectRow] {
        guard let queue else { return [] }
        return (try? await queue.read { db in
            try CacheObjectRow.fetchAll(db, sql: "SELECT * FROM cacheObject ORDER BY _id")
        }) ?? []
    }

    /// LRU ordering for capacity cleanup: least recently touched first.
    @concurrent
    public func rowsOrderedByTouched() async -> [CacheObjectRow] {
        guard let queue else { return [] }
        return (try? await queue.read { db in
            try CacheObjectRow.fetchAll(
                db, sql: "SELECT * FROM cacheObject ORDER BY touched IS NULL, touched ASC, _id ASC"
            )
        }) ?? []
    }

    // MARK: - Writes (download path, same semantics the fork wrote)

    /// The access heartbeat: `touched = now` (05 §2.4 — the LRU clock caliber).
    @concurrent
    public func updateTouched(_id: Int64, toMilliseconds now: Int64) async {
        guard let queue else { return }
        _ = try? await queue.write { db in
            try db.execute(
                sql: "UPDATE cacheObject SET touched = ? WHERE _id = ?",
                arguments: [now, _id]
            )
        }
    }

    /// Insert-or-update by resource URL, keeping `key = url` (fork rows).
    @concurrent
    public func upsert(row: CacheObjectRow) async {
        guard let queue else { return }
        _ = try? await queue.write { db in
            if row._id != nil {
                var copy = row
                try copy.update(db)
            } else if let existing = try CacheObjectRow.fetchOne(
                db, sql: "SELECT * FROM cacheObject WHERE url = ? ORDER BY _id LIMIT 1",
                arguments: [row.url ?? ""]
            ) {
                var copy = row
                copy._id = existing._id
                try copy.update(db)
            } else {
                var copy = row
                try copy.insert(db)
            }
        }
    }

    @concurrent
    public func delete(_id: Int64) async {
        guard let queue else { return }
        _ = try? await queue.write { db in
            try db.execute(sql: "DELETE FROM cacheObject WHERE _id = ?", arguments: [_id])
        }
    }

    @concurrent
    public func delete(forURL url: String) async {
        guard let queue else { return }
        _ = try? await queue.write { db in
            try db.execute(sql: "DELETE FROM cacheObject WHERE url = ?", arguments: [url])
        }
    }
}
