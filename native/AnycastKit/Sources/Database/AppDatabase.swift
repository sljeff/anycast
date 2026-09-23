import Foundation
import GRDB

/// Opens and owns the inherited `Documents/anycast.db`.
///
/// Responsibilities (docs/migration/00 M1, 05 §2):
/// - **Schema read-back validation**: `user_version` must be 4 (or migrate
///   from a supported older version) with the 9 expected tables.
/// - **Write-back compatibility**: same schema, rollback journal — never WAL
///   (a `DatabaseQueue` keeps the journal mode it finds; it does not enable
///   WAL) — so a Flutter build rolled back onto our writes keeps working
///   (docs/migration/05 §2.4).
/// - **K25 corrupt fallback**: a deterministically corrupt file is
///   quarantined (renamed `.corrupt`), a fresh default database is created,
///   and the event is reported — never a crash loop, and never triggered by
///   transient errors (IO, locks).
/// - **K31 idempotent defaults**: every successful open re-inserts the three
///   default rows (`INSERT OR IGNORE`), so a database whose `player` row was
///   deleted by `clear()` still restores without errors.
///
/// All SQLite work must stay off `@MainActor` stacks (docs/migration/08
/// §1.1): every accessor is `@concurrent` async.
public final class AppDatabase: Sendable {

    /// Exposed for the L0 test suites (schema/row comparisons). Production
    /// code goes through the repositories.
    public let queue: DatabaseQueue

    private init(queue: DatabaseQueue) {
        self.queue = queue
    }

    public typealias QuarantineHandler = @Sendable (_ originalURL: URL, _ reason: String) -> Void

    /// Opens the database at `url`, creating it when absent.
    ///
    /// - Parameter localeIdentifier: drives the fresh-install default
    ///   `countryCode`/`targetLanguage`; defaults to the device's first
    ///   preferred language. Tests pass G9 fixture values explicitly.
    /// - Parameter onQuarantine: K25 reporting hook (the app wires Sentry).
    @concurrent
    public static func openAt(
        _ url: URL,
        localeIdentifier: String? = nil,
        onQuarantine: QuarantineHandler? = nil
    ) async throws -> AppDatabase {
        let locale = localeIdentifier
            ?? Locale.preferredLanguages.first
            ?? "en_US"

        do {
            let queue = try await performOpen(url: url, localeIdentifier: locale)
            return AppDatabase(queue: queue)
        } catch {
            guard isDeterministicCorruption(error) else { throw error }

            // K25: quarantine, then continue as a fresh install.
            let reason = quarantineReason(for: error)
            quarantine(url: url)
            onQuarantine?(url, reason)
            let queue = try await performOpen(url: url, localeIdentifier: locale)
            return AppDatabase(queue: queue)
        }
    }

    // MARK: - Open / validate / migrate

    private static func performOpen(url: URL, localeIdentifier: String) async throws -> DatabaseQueue {
        // DatabaseQueue opens with create flags; an absent path yields an
        // empty database (user_version 0, no tables) which the fresh-create
        // branch below handles — mirroring sqflite's onCreate.
        let queue = try DatabaseQueue(path: url.path)

        let version = try await queue.read { db in
            try Int.fetchOne(db, sql: "PRAGMA user_version") ?? 0
        }

        // Integrity: K25 accepts open-time NOTADB/CORRUPT errors and explicit
        // integrity-check failures as quarantine triggers. quick_check(1)
        // returns "ok" on healthy files; anything else is deterministic
        // corruption. Transient failures surface as ordinary DatabaseErrors
        // and rethrow without quarantine.
        let check = try await queue.read { db in
            try String.fetchAll(db, sql: "PRAGMA quick_check(1)")
        }
        if check.first != "ok" {
            throw CorruptDatabaseError.quickCheck(check.joined(separator: "; "))
        }

        let tableCount = try await queue.read { db in
            try Int.fetchOne(
                db,
                sql: "SELECT COUNT(*) FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%'"
            ) ?? 0
        }

        if version == Schema.version {
            // Current schema: nothing to migrate.
        } else if tableCount == 0 {
            // Fresh install (or an empty/0-byte leftover): create the latest
            // schema, mirroring onCreate + the creators' own default-row
            // inserts, then stamp the version (sqflite does this after
            // onCreate returns).
            try await queue.write { db in
                try createFreshSchema(in: db, localeIdentifier: localeIdentifier)
                try setVersion(db, to: Schema.version)
            }
        } else if version < Schema.version {
            // Ordered migration from a released older schema (helper.dart
            // migrateDatabase port).
            try await queue.write { db in
                try applyMigrations(in: db, from: version)
                try setVersion(db, to: Schema.version)
            }
        } else {
            throw AppDatabaseError.schemaFromTheFuture(found: version, expected: Schema.version)
        }

        // K31: idempotent default rows on every successful open. Missing
        // rows (e.g. player after clear()) are read-side values, not errors.
        try await queue.write { db in
            try insertDefaultRows(in: db, localeIdentifier: localeIdentifier)
        }

        return queue
    }

    private static func createFreshSchema(in db: Database, localeIdentifier: String) throws {
        for creatorSQL in Schema.tableCreators {
            try db.execute(sql: creatorSQL)
        }
        let (language, country) = Schema.localeComponents(fromLocaleIdentifier: localeIdentifier)
        try db.execute(sql: Schema.defaultPlaylistInsertSQL)
        try db.execute(sql: Schema.defaultPlayerInsertSQL)
        try db.execute(sql: Schema.defaultSettingsInsertSQL(country: country, language: language))
    }

    private static func applyMigrations(in db: Database, from oldVersion: Int) throws {
        for target in Schema.migrations.keys.sorted() where oldVersion < target && target <= Schema.version {
            for statement in Schema.migrations[target]! {
                try db.execute(sql: statement)
            }
        }
    }

    private static func insertDefaultRows(in db: Database, localeIdentifier: String) throws {
        let (language, country) = Schema.localeComponents(fromLocaleIdentifier: localeIdentifier)
        try db.execute(sql: Schema.defaultPlaylistInsertSQL)
        try db.execute(sql: Schema.defaultPlayerInsertSQL)
        try db.execute(sql: Schema.defaultSettingsInsertSQL(country: country, language: language))
    }

    private static func setVersion(_ db: Database, to version: Int) throws {
        try db.execute(sql: "PRAGMA user_version = \(version)")
    }

    // MARK: - K25 quarantine

    private static func isDeterministicCorruption(_ error: Error) -> Bool {
        if error is CorruptDatabaseError { return true }
        guard let dbError = error as? DatabaseError else { return false }
        let code = dbError.resultCode.rawValue
        let primary = code & 0xFF
        // SQLITE_NOTADB (26) / SQLITE_CORRUPT (11, incl. extended variants).
        return primary == 26 || primary == 11
    }

    private static func quarantineReason(for error: Error) -> String {
        if let quickCheck = error as? CorruptDatabaseError {
            return quickCheck.message
        }
        let dbError = error as? DatabaseError
        return "sqlite error \(dbError?.resultCode.rawValue ?? 0): \(dbError?.message ?? String(describing: error))"
    }

    /// Renames the corrupt main database to `<name>.corrupt` (uniquely
    /// suffixed when one already exists) and removes stale journal siblings.
    private static func quarantine(url: URL) {
        let fileManager = FileManager.default
        do {
            if fileManager.fileExists(atPath: url.path) {
                var destination = url.appendingPathExtension("corrupt")
                if fileManager.fileExists(atPath: destination.path) {
                    destination = URL(fileURLWithPath: "\(url.path).corrupt-\(Int(Date().timeIntervalSince1970))")
                }
                try fileManager.moveItem(at: url, to: destination)
            }
            for suffix in ["-journal", "-wal", "-shm"] {
                let sidecar = URL(fileURLWithPath: url.path + suffix)
                if fileManager.fileExists(atPath: sidecar.path) {
                    try? fileManager.removeItem(at: sidecar)
                }
            }
        } catch {
            // Moving failed (permissions, full disk): the subsequent open
            // will fail again with a non-corruption error and surface
            // through the startup DAG. Never loop.
        }
    }

    // MARK: - Repositories

    public func settingsRepository() -> SettingsRepository { SettingsRepository(database: self) }
    public func playerRepository() -> PlayerRepository { PlayerRepository(database: self) }
    public func feedRepository() -> FeedRepository { FeedRepository(database: self) }
    public func historyRepository() -> HistoryRepository { HistoryRepository(database: self) }
    public func playlistRepository() -> PlaylistRepository { PlaylistRepository(database: self) }
    public func subscriptionRepository() -> SubscriptionRepository { SubscriptionRepository(database: self) }
    public func subtitleRepository() -> SubtitleRepository { SubtitleRepository(database: self) }
    public func translationRepository() -> TranslationRepository { TranslationRepository(database: self) }
}

// MARK: - Errors

public enum AppDatabaseError: Error, LocalizedError, Equatable {
    /// `user_version` above what this build understands (downgrade attempt).
    case schemaFromTheFuture(found: Int, expected: Int)

    public var errorDescription: String? {
        switch self {
        case let .schemaFromTheFuture(found, expected):
            "Database schema v\(found) is newer than this build supports (v\(expected))"
        }
    }
}

/// Deterministic corruption as reported by an integrity check (K25).
public struct CorruptDatabaseError: Error, @unchecked Sendable {
    public let message: String
    public static func quickCheck(_ message: String) -> CorruptDatabaseError {
        CorruptDatabaseError(message: "quick_check: \(message)")
    }
}
