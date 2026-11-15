import Foundation
import GRDB

// MARK: - Translations

public struct TranslationRepository: Sendable {
    let database: AppDatabase
    init(database: AppDatabase) { self.database = database }

    /// Looked up by (enclosureUrl, language), but only enclosureUrl is
    /// unique: writing another language replaces the row (K15).
    @concurrent
    public func get(byEnclosureURL url: String, language: String) async throws -> TranslationRow? {
        try await database.queue.read { db in
            try TranslationRow.fetchOne(
                db,
                sql: "SELECT * FROM translation WHERE enclosureUrl = ? AND language = ?",
                arguments: [url, language]
            )
        }
    }

    @concurrent
    public func insert(_ row: TranslationRow) async throws {
        try await database.queue.write { db in
            var copy = row
            copy.id = nil
            try copy.insert(db, onConflict: .replace)
        }
    }

    @concurrent
    public func delete(byEnclosureURL url: String) async throws {
        try await database.queue.write { db in
            try db.execute(sql: "DELETE FROM translation WHERE enclosureUrl = ?", arguments: [url])
        }
    }
}
