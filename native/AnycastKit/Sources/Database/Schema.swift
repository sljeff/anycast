import Foundation
import GRDB

/// The inherited schema, mirrored statement-for-statement from
/// lib/models/helper.dart + the individual model files (docs/migration/01 §1).
/// The native first release keeps this schema byte-compatible for
/// write-back: same tables, same columns, same `user_version`, rollback
/// journal (never WAL) — docs/migration/05 §2.4.
public enum Schema {

    /// `PRAGMA user_version` — the database schema version, not the app
    /// version (AGENTS.md).
    public static let version = 4

    /// Historical migration steps, ported from `migrations` in helper.dart.
    /// Keys are target schema versions; released steps are append-only.
    public static let migrations: [Int: [String]] = [
        // 3 -> 4
        4: [
            "ALTER TABLE settings ADD COLUMN continuousPlaying INTEGER DEFAULT 1",
        ],
    ]

    /// Table creators in creation order (helper.dart:17-27).
    public static let tableCreators: [String] = [
        """
        CREATE TABLE IF NOT EXISTS feedEpisode (
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
        """,
        """
        CREATE TABLE IF NOT EXISTS playlistEpisode (
          id INTEGER PRIMARY KEY,
          title TEXT,
          description TEXT,
          duration INTEGER,
          enclosureUrl TEXT UNIQUE,
          pubDate INTEGER,
          imageUrl TEXT,
          channelTitle TEXT,
          rssFeedUrl TEXT,
          playlistId INTEGER,
          position REAL,
          playedDuration INTEGER
        )
        """,
        """
        CREATE TABLE IF NOT EXISTS subscription (
          id INTEGER PRIMARY KEY,
          rssFeedUrl TEXT UNIQUE,
          title TEXT UNIQUE,
          description TEXT,
          imageUrl TEXT,
          link TEXT,
          categories TEXT,
          author TEXT,
          email TEXT,
          lastUpdated INTEGER
        )
        """,
        """
        CREATE TABLE IF NOT EXISTS playlist (
          id INTEGER PRIMARY KEY,
          title TEXT,
          position INTEGER
        )
        """,
        """
        CREATE TABLE IF NOT EXISTS player (
          id INTEGER PRIMARY KEY,
          currentPlaylistId INTEGER
        )
        """,
        """
        CREATE TABLE IF NOT EXISTS settings (
          id INTEGER PRIMARY KEY,
          darkMode INTEGER,
          speed REAL,
          skipSilence INTEGER,
          autoSleepTimer TEXT,
          maxCacheCount INTEGER,
          countryCode TEXT,
          targetLanguage TEXT,
          autoRefreshInterval INTEGER,
          maxFeedEpisodes INTEGER,
          maxHistoryEpisodes INTEGER,
          continuousPlaying INTEGER DEFAULT 1
        )
        """,
        """
        CREATE TABLE IF NOT EXISTS subtitle (
          id INTEGER PRIMARY KEY,
          enclosureUrl TEXT UNIQUE,
          status TEXT,
          subtitle TEXT,
          language TEXT,
          summary TEXT
        )
        """,
        """
        CREATE TABLE IF NOT EXISTS historyEpisode (
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
        """,
        """
        CREATE TABLE IF NOT EXISTS translation (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          enclosureUrl TEXT UNIQUE,
          status TEXT,
          translation TEXT,
          language TEXT
        )
        """,
    ]

    /// Locale → (country, language) default derivation, ported from
    /// settingsTableCreator (settings.dart:24-32). Dart's
    /// `Platform.localeName` uses underscores (`zh_Hans_CN`); iOS
    /// `Locale.preferredLanguages` uses hyphens (`zh-Hans-CN`). The split
    /// rule itself is pinned by the G9 fixture: first segment = language,
    /// last segment = country, `en`/`US` when there is no separator.
    public static func localeComponents(fromLocaleIdentifier identifier: String) -> (language: String, country: String) {
        let normalized = identifier.replacingOccurrences(of: "-", with: "_")
        let parts = normalized.split(separator: "_", omittingEmptySubsequences: false).map(String.init)
        guard parts.count > 1 else { return ("en", "US") }
        return (parts[0], parts[parts.count - 1])
    }

    /// The default settings row exactly as the Dart creator inserts it
    /// (settings.dart:34-37): `continuousPlaying` is omitted from the column
    /// list and relies on the column DEFAULT 1. The `autoRefreshInterval`
    /// default is 300 — the documented caliber (docs/migration/01 §2).
    public static func defaultSettingsInsertSQL(country: String, language: String) -> String {
        """
        INSERT OR IGNORE INTO settings (id, darkMode, speed, skipSilence, autoSleepTimer, maxCacheCount, countryCode, targetLanguage, autoRefreshInterval, maxFeedEpisodes, maxHistoryEpisodes)
        VALUES (1, 0, 1.0, 0, '0,0,0', 10, '\(country)', '\(language)', 300, 100, 100)
        """
    }

    public static let defaultPlaylistInsertSQL = """
        INSERT OR IGNORE INTO playlist (id, title, position)
        VALUES (1, 'Default', 1)
        """

    public static let defaultPlayerInsertSQL = """
        INSERT OR IGNORE INTO player (id, currentPlaylistId)
        VALUES (1, NULL)
        """
}
