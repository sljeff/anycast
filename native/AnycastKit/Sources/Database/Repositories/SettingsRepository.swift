import Foundation
import GRDB

// MARK: - Settings

public struct SettingsRepository: Sendable {
    let database: AppDatabase
    init(database: AppDatabase) { self.database = database }

    @concurrent
    public func load() async throws -> AppSettings {
        let row: SettingsRow? = try await database.queue.read { db in
            try SettingsRow.fetchOne(db, sql: "SELECT * FROM settings WHERE id = 1")
        }
        guard let row else {
            // K31 read-side defense: a missing row decodes to defaults.
            return AppSettings.defaults(localeIdentifier: Locale.preferredLanguages.first ?? "en_US")
        }
        return AppSettings(row: row)
    }

    @concurrent
    public func setDarkMode(_ value: Bool) async throws {
        try await set("darkMode", numeric: value ? 1 : 0)
    }

    @concurrent
    public func setSpeed(_ value: Double) async throws {
        try await update("speed = ?", [value])
    }

    /// `settings.skipSilence` is retained for schema compatibility and is
    /// never written by the UI (decision K2: the switch is removed); the
    /// setter exists only for schema-complete tooling.
    @concurrent
    public func setSkipSilence(_ value: Bool) async throws {
        try await set("skipSilence", numeric: value ? 1 : 0)
    }

    @concurrent
    public func setAutoSleepTimer(startHour: Int, endHour: Int, minsIndex: Int) async throws {
        try await update("autoSleepTimer = ?", ["\(startHour),\(endHour),\(minsIndex)"])
    }

    @concurrent
    public func setContinuousPlaying(_ value: Bool) async throws {
        try await set("continuousPlaying", numeric: value ? 1 : 0)
    }

    @concurrent
    public func setCountryCode(_ value: String) async throws {
        try await update("countryCode = ?", [value])
    }

    @concurrent
    public func setTargetLanguage(_ value: String) async throws {
        try await update("targetLanguage = ?", [value])
    }

    @concurrent
    public func setAutoRefreshInterval(_ seconds: Int64) async throws {
        try await update("autoRefreshInterval = ?", [seconds])
    }

    @concurrent
    public func setMaxFeedEpisodes(_ value: Int64) async throws {
        try await update("maxFeedEpisodes = ?", [value])
    }

    @concurrent
    public func setMaxHistoryEpisodes(_ value: Int64) async throws {
        try await update("maxHistoryEpisodes = ?", [value])
    }

    private func update(_ assignment: String, _ arguments: StatementArguments) async throws {
        try await database.queue.write { db in
            try db.execute(
                sql: "UPDATE settings SET \(assignment) WHERE id = 1",
                arguments: arguments
            )
        }
    }

    private func set(_ column: String, numeric: Int64) async throws {
        try await update("\(column) = ?", [numeric])
    }
}
