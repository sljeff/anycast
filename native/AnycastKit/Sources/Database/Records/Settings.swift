import Foundation
import GRDB

// MARK: - settings (raw mirror + decoded value)

/// Raw settings row; semantics (bool/CSV) decode in `AppSettings`.
public struct SettingsRow: Codable, Sendable, Equatable, FetchableRecord {
    public static let databaseTableName = "settings"
    public var id: Int64?
    public var darkMode: Int64?
    public var speed: Double?
    public var skipSilence: Int64?
    public var autoSleepTimer: String?
    public var maxCacheCount: Int64?
    public var countryCode: String?
    public var targetLanguage: String?
    public var autoRefreshInterval: Int64?
    public var maxFeedEpisodes: Int64?
    public var maxHistoryEpisodes: Int64?
    public var continuousPlaying: Int64?
}

/// Settings values with the Dart `fromMap` semantics: booleans are
/// `column == 1` (NULL decodes false), `autoSleepTimer` stays a raw
/// `"start,end,minsIndex"` CSV (see G9 for the codec).
public struct AppSettings: Sendable, Equatable {
    public var darkMode: Bool
    public var speed: Double
    /// Kept readable for schema compatibility; the switch is removed from
    /// the UI and never written (decision K2).
    public var skipSilence: Bool
    public var autoSleepTimer: String
    public var maxCacheCount: Int64
    public var countryCode: String
    public var targetLanguage: String
    /// Seconds; DB default 300 is the canonical caliber (docs/migration/01 §2).
    public var autoRefreshInterval: Int64
    public var maxFeedEpisodes: Int64
    public var maxHistoryEpisodes: Int64
    public var continuousPlaying: Bool

    public init(row: SettingsRow) {
        self.darkMode = (row.darkMode ?? 0) == 1
        self.speed = row.speed ?? 1.0
        self.skipSilence = (row.skipSilence ?? 0) == 1
        self.autoSleepTimer = row.autoSleepTimer ?? "0,0,0"
        self.maxCacheCount = row.maxCacheCount ?? 10
        self.countryCode = row.countryCode ?? "US"
        self.targetLanguage = row.targetLanguage ?? "en"
        self.autoRefreshInterval = row.autoRefreshInterval ?? 300
        self.maxFeedEpisodes = row.maxFeedEpisodes ?? 100
        self.maxHistoryEpisodes = row.maxHistoryEpisodes ?? 100
        self.continuousPlaying = (row.continuousPlaying ?? 1) == 1
    }

    /// Fresh-install defaults (must equal the creator's INSERT, G9).
    public static func defaults(localeIdentifier: String) -> AppSettings {
        let (language, country) = Schema.localeComponents(fromLocaleIdentifier: localeIdentifier)
        return AppSettings(row: SettingsRow(
            id: 1,
            darkMode: 0,
            speed: 1.0,
            skipSilence: 0,
            autoSleepTimer: "0,0,0",
            maxCacheCount: 10,
            countryCode: country,
            targetLanguage: language,
            autoRefreshInterval: 300,
            maxFeedEpisodes: 100,
            maxHistoryEpisodes: 100,
            continuousPlaying: 1
        ))
    }
}
