import Foundation
import GRDB

// MARK: - Subtitles

public struct SubtitleRepository: Sendable {
    let database: AppDatabase
    init(database: AppDatabase) { self.database = database }

    @concurrent
    public func get(byEnclosureURL url: String) async throws -> SubtitleRow? {
        try await database.queue.read { db in
            try SubtitleRow.fetchOne(
                db, sql: "SELECT * FROM subtitle WHERE enclosureUrl = ?", arguments: [url]
            )
        }
    }

    /// url → status map for the polling set (subtitle.dart `list`).
    @concurrent
    public func listStatuses() async throws -> [String: String] {
        try await database.queue.read { db in
            var result: [String: String] = [:]
            for row in try Row.fetchAll(db, sql: "SELECT enclosureUrl, status FROM subtitle") {
                if let url = row["enclosureUrl"] as String?, let status = row["status"] as String? {
                    result[url] = status
                }
            }
            return result
        }
    }

    /// The 1.2.1+38 insert gate (subtitle.dart:68-75 in the baseline): a row
    /// persists only when it carries a usable payload (non-empty subtitle
    /// that is not the literal "null", plus a language). The baseline keeps
    /// only complete `succeeded` rows; a rejected write is a no-op, not an
    /// error. (A 2026-07 unreleased Flutter-line change started persisting
    /// processing rows; it is not part of the shipped baseline and is not
    /// ported.)
    @concurrent
    public func insert(_ row: SubtitleRow) async throws {
        try await database.queue.write { db in
            guard let subtitle = row.subtitle,
                  !subtitle.isEmpty,
                  subtitle != "null",
                  row.language != nil
            else { return }
            var copy = row
            copy.id = nil
            try copy.insert(db, onConflict: .replace)
        }
    }

    @concurrent
    public func delete(byEnclosureURL url: String) async throws {
        try await database.queue.write { db in
            try db.execute(sql: "DELETE FROM subtitle WHERE enclosureUrl = ?", arguments: [url])
        }
    }
}
