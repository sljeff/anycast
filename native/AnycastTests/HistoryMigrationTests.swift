import Foundation
import GRDB
import Testing
@testable import AnycastKit

/// History schema 5: fresh installs and upgrades from a released v4 file
/// share the same columns, old rows keep their data with a NULL
/// `lastPlayedAt` (sorted below played rows), and new writes do not use a
/// caller-supplied id.
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
        #expect(listed.map(\.lastPlayedAt) == [nil, nil], "legacy rows keep an unknown play time")
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

    @Test("a newly played row sorts above NULL rows; legacy rows keep id-DESC order")
    func playedRowSortsAboveNullRows() async throws {
        let (database, directory) = try await openUpgraded()
        defer { SandboxCleanup.remove(directory, closing: [database.queue]) }

        try await database.historyRepository().insert(HistoryEpisodeRow(
            title: "fresh", enclosureUrl: "https://fresh.example/f.mp3", lastPlayedAt: 1
        ))
        let listed = try await database.historyRepository().listAll()
        #expect(listed.map(\.enclosureUrl) == [
            "https://fresh.example/f.mp3",
            "https://newer.example/b.mp3",
            "https://older.example/a.mp3",
        ], "even lastPlayedAt = 1 beats NULL")
        #expect(listed.map(\.lastPlayedAt) == [1, nil, nil])
    }

    @Test("trim keeps played rows first and removes the oldest NULL rows")
    func trimDropsNullRowsFirst() async throws {
        let (database, directory) = try await openUpgraded()
        defer { SandboxCleanup.remove(directory, closing: [database.queue]) }

        try await database.historyRepository().insert(HistoryEpisodeRow(
            title: "fresh", enclosureUrl: "https://fresh.example/f.mp3", lastPlayedAt: 1
        ))
        let removed = try await database.historyRepository().trim(keeping: 2)
        #expect(removed == ["https://older.example/a.mp3"], "oldest legacy row goes first")
        let kept = try await database.historyRepository().listAll()
        #expect(kept.map(\.enclosureUrl) == [
            "https://fresh.example/f.mp3",
            "https://newer.example/b.mp3",
        ])

        let removedAgain = try await database.historyRepository().trim(keeping: 1)
        #expect(removedAgain == ["https://newer.example/b.mp3"], "played row survives NULL rows")
        let last = try await database.historyRepository().listAll()
        #expect(last.map(\.enclosureUrl) == ["https://fresh.example/f.mp3"])
    }

    @Test("a clear keeps a row played after it began and deletes the rest")
    func clearSparesRowPlayedDuringUndoWindow() async throws {
        let (database, directory) = try await openUpgraded()
        defer { SandboxCleanup.remove(directory, closing: [database.queue]) }

        let repository = database.historyRepository()
        try await repository.insert(HistoryEpisodeRow(
            title: "before", enclosureUrl: "https://before.example/p.mp3", lastPlayedAt: 100
        ))
        try await repository.insert(HistoryEpisodeRow(
            title: "replayed", enclosureUrl: "https://newer.example/b.mp3", lastPlayedAt: 200
        ))

        try await repository.deleteMany(
            [
                "https://older.example/a.mp3",
                "https://newer.example/b.mp3",
                "https://before.example/p.mp3",
            ],
            notPlayedSince: 150
        )

        let kept = try await repository.listAll()
        #expect(kept.map(\.enclosureUrl) == ["https://newer.example/b.mp3"])
    }

    @Test("reopening an upgraded database is idempotent and keeps NULL rows NULL")
    func reopenIsIdempotent() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("anycast-history-reopen-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("anycast.db")
        try writeVersion4Database(at: url)

        let first = try await AppDatabase.openAt(url, localeIdentifier: "en_US")
        let firstRows = try await first.historyRepository().listAll()
        try first.queue.close()

        let second = try await AppDatabase.openAt(url, localeIdentifier: "en_US")
        defer { SandboxCleanup.remove(directory, closing: [second.queue]) }
        let secondRows = try await second.historyRepository().listAll()
        #expect(firstRows == secondRows)
        #expect(secondRows.map(\.lastPlayedAt) == [nil, nil])
        let version = try await second.queue.read { db in
            try Int.fetchOne(db, sql: "PRAGMA user_version") ?? 0
        }
        #expect(version == Schema.version)
    }

    @Test("a failing migration leaves the v4 file untouched and open fails")
    func failingMigrationLeavesNoPartialUpgrade() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("anycast-history-fail-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("anycast.db")
        try writeVersion4Database(at: url)
        // Make the 4 -> 5 ALTER fail: the column already exists.
        let setup = try DatabaseQueue(path: url.path)
        try await setup.write { db in
            try db.execute(sql: "ALTER TABLE historyEpisode ADD COLUMN lastPlayedAt INTEGER")
        }
        try setup.close()

        await #expect(throws: (any Error).self) {
            _ = try await AppDatabase.openAt(url, localeIdentifier: "en_US")
        }

        let check = try DatabaseQueue(path: url.path)
        defer { try? check.close() }
        let (version, titles) = try await check.read { db in
            (
                try Int.fetchOne(db, sql: "PRAGMA user_version") ?? 0,
                try String.fetchAll(db, sql: "SELECT title FROM historyEpisode ORDER BY id")
            )
        }
        #expect(version == 4, "version is not stamped after a failed migration")
        #expect(titles == ["older", "newer"], "user rows intact")
        let siblings = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        #expect(!siblings.contains { $0.contains("corrupt") }, "not quarantined or recreated")
    }

    private func openUpgraded() async throws -> (AppDatabase, URL) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("anycast-history-v4-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("anycast.db")
        try writeVersion4Database(at: url)
        return (try await AppDatabase.openAt(url, localeIdentifier: "en_US"), directory)
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
