import Foundation
import Testing
@testable import AnycastKit

/// `SettingsRepository` setters against the real SQLite settings table.
struct SettingsRepositoryTests {

    private func freshDatabase() async throws -> (AppDatabase, URL) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("anycast-settings-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let database = try await AppDatabase.openAt(
            directory.appendingPathComponent("anycast.db"),
            localeIdentifier: "en_US"
        )
        return (database, directory)
    }

    @Test("setMaxCacheCount round-trips and leaves every other column untouched")
    func maxCacheCountRoundTrip() async throws {
        let (database, directory) = try await freshDatabase()
        defer { SandboxCleanup.remove(directory, closing: [database.queue]) }
        let repository = database.settingsRepository()

        let before = try await repository.load()
        #expect(before.maxCacheCount == 10)

        for value: Int64 in [5, 100, 20] {
            try await repository.setMaxCacheCount(value)
            let after = try await repository.load()
            #expect(after.maxCacheCount == value)

            var expected = before
            expected.maxCacheCount = value
            #expect(after == expected, "only maxCacheCount may change")
        }

        // The raw column holds the value, not a derived encoding.
        let raw = try await database.queue.read { db in
            try Int64.fetchOne(db, sql: "SELECT maxCacheCount FROM settings WHERE id = 1")
        }
        #expect(raw == 20)
    }
}
