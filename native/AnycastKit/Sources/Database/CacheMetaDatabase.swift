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
/// M1 ships the tolerant reader (L0 matrix rows: missing meta DB, empty tmp
/// directory, orphaned rows). The LRU write path (max 10 objects, 30-day
/// stale period, delete only when >1 day untouched) lands with M2's cache
/// store.
public struct CacheMetaDatabase: Sendable {

    public struct CacheObjectRow: Codable, Sendable, Equatable, FetchableRecord, PersistableRecord {
        public static let databaseTableName = "cacheObject"

        public var _id: Int64?
        public var url: String?
        /// Cache key: `anycast_episode` for audio, `libCachedImageData` for covers.
        public var key: String?
        /// File NAME only (`<uuidv1>.<ext>`), resolved against
        /// `<tmp>/<cacheKey>/` — never a path (corrected column wording in
        /// docs/migration/01 §1.2).
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

    public let queue: DatabaseQueue?

    /// Tolerant open: a missing or unreadable index means "no downloads
    /// mapped" — callers degrade to streaming, they never crash
    /// (docs/migration/05 §2.1).
    @concurrent
    public static func open(at url: URL) async -> CacheMetaDatabase {
        // DatabaseQueue CREATES an empty database at a missing path — the
        // tolerant reader must never fabricate one (05 §2.1: missing meta DB
        // means "no downloads mapped").
        guard FileManager.default.fileExists(atPath: url.path) else {
            return CacheMetaDatabase(queue: nil)
        }
        return CacheMetaDatabase(queue: try? DatabaseQueue(path: url.path))
    }

    init(queue: DatabaseQueue?) {
        self.queue = queue
    }

    public var isAvailable: Bool { queue != nil }

    @concurrent
    public func entry(forURL url: String, cacheKey: String) async -> CacheObjectRow? {
        guard let queue else { return nil }
        return try? await queue.read { db in
            try CacheObjectRow.fetchOne(
                db,
                sql: "SELECT * FROM cacheObject WHERE url = ? AND key = ?",
                arguments: [url, cacheKey]
            )
        }
    }

    @concurrent
    public func entries(cacheKey: String) async -> [CacheObjectRow] {
        guard let queue else { return [] }
        return (try? await queue.read { db in
            try CacheObjectRow.fetchAll(
                db, sql: "SELECT * FROM cacheObject WHERE key = ?", arguments: [cacheKey]
            )
        }) ?? []
    }
}
