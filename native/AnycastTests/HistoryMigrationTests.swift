import Foundation
import GRDB
import Testing
@testable import AnycastKit

/// History schema 5: fresh installs and upgrades from a released v4 file
/// share the same columns, old rows keep their data with a monotonic
/// `lastPlayedAt`, and new writes do not use a caller-supplied id.
@Suite(.serialized)
struct HistoryMigrationTests {

    @Test("v4 history upgrades in place and matches a fresh history table")
    func upgradeMatchesFreshSchema() async throws {
        let upgradedDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("anycast-history-v4-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: upgradedDirectory, withIntermediateDirectories: true)
        let upgradedURL = upgradedDirectory.appendingPathComponent("anycast.db")
        try writeVersion4Database(at: upgradedURL)
        let upgraded = try await AppDatabase.openAt(upgradedURL, localeIdentifier: "en_US")
        defer { SandboxCleanup.remove(upgradedDirectory, closing: [upgraded.queue]) }

        let freshDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("anycast-history-fresh-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: freshDirectory, withIntermediateDirectories: true)
        let fresh = try await AppDatabase.openAt(
            freshDirectory.appendingPathComponent("anycast.db"),
            localeIdentifier: "en_US"
        )
        defer { SandboxCleanup.remove(freshDirectory, closing: [fresh.queue]) }

        let version = try await upgraded.queue.read { db in
            try Int.fetchOne(db, sql: "PRAGMA user_version") ?? 0
        }
        #expect(version == Schema.version)

        let upgradedColumns = try await columnNames(upgraded, table: "historyEpisode")
        let freshColumns = try await columnNames(fresh, table: "historyEpisode")
        #expect(upgradedColumns == freshColumns)
        #expect(upgradedColumns.contains("lastPlayedAt"))

        let listed = try await upgraded.historyRepository().listAll()
        #expect(listed.map(\.enclosureUrl) == [
            "https://newer.example/b.mp3",
            "https://older.example/a.mp3",
        ])
        #expect(listed.map(\.title) == ["newer", "older"])
        #expect(listed.map(\.lastPlayedAt) == [9, 2])
        #expect(listed.map(\.id) == [9, 2], "existing history ids are preserved")

        // A playlist-shaped id must not replace the row that already holds it.
        try await upgraded.historyRepository().insert(HistoryEpisodeRow(
            id: 9,
            title: "unrelated",
            enclosureUrl: "https://other.example/c.mp3",
            lastPlayedAt: 50
        ))
        let afterCollision = try await upgraded.historyRepository().listAll()
        #expect(afterCollision.map(\.enclosureUrl) == [
            "https://other.example/c.mp3",
            "https://newer.example/b.mp3",
            "https://older.example/a.mp3",
        ])
        #expect(afterCollision.first { $0.enclosureUrl == "https://newer.example/b.mp3" }?.title == "newer")

        try await upgraded.historyRepository().insert(HistoryEpisodeRow(
            id: 9,
            title: "newer-again",
            enclosureUrl: "https://newer.example/b.mp3",
            lastPlayedAt: 80
        ))
        let replayed = try await upgraded.historyRepository().listAll()
        #expect(replayed.first?.enclosureUrl == "https://newer.example/b.mp3")
        #expect(replayed.first?.id == 9)
        #expect(replayed.first?.title == "newer-again")
        #expect(replayed.count == 3)

        let trimmed = try await upgraded.historyRepository().trim(keeping: 1)
        #expect(Set(trimmed) == [
            "https://other.example/c.mp3",
            "https://older.example/a.mp3",
        ])
        let kept = try await upgraded.historyRepository().listAll()
        #expect(kept.map(\.enclosureUrl) == ["https://newer.example/b.mp3"])
    }

    private func writeVersion4Database(at url: URL) throws {
        let queue = try DatabaseQueue(path: url.path)
        try queue.write { db in
            for sql in Schema.tableCreators where !sql.contains("historyEpisode") {
                try db.execute(sql: sql)
            }
            try db.execute(sql: """
                CREATE TABLE historyEpisode (
                  id INTEGER PRIMARY KEY,
                  title TEXT,
                  description TEXT,
                  duration INTEGER,
                  enclosureUrl TEXT UNIQUE,
                  pubDate INTEGER,
                  imageUrl TEXT,
                  channelTitle TEXT,
                  rssFeedUrl TEXT
                )
                """)
            try db.execute(sql: """
                INSERT INTO historyEpisode (id, title, enclosureUrl)
                VALUES (2, 'older', 'https://older.example/a.mp3')
                """)
            try db.execute(sql: """
                INSERT INTO historyEpisode (id, title, enclosureUrl)
                VALUES (9, 'newer', 'https://newer.example/b.mp3')
                """)
            try db.execute(sql: "PRAGMA user_version = 4")
        }
    }

    private func columnNames(_ database: AppDatabase, table: String) async throws -> [String] {
        try await database.queue.read { db in
            try Row.fetchAll(db, sql: "PRAGMA table_info(\(table))").compactMap { row in
                row["name"] as String?
            }
        }
    }
}
