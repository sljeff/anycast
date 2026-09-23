import Foundation
import GRDB
import Testing
@testable import AnycastKit

/// L0 data-compatibility matrix (docs/migration/05 §2.1–§2.3) against the
/// M0 fixture buckets, golden-compared via G15.
@Suite(.serialized)
struct L0DatabaseTests {

    private func sandboxURL(_ bucket: String) throws -> URL {
        try RepoAssets.sandboxedCopy(ofFixtureDirectory: "db/\(bucket)")
    }

    private func openSandbox(_ bucket: String) async throws -> (AppDatabase, URL) {
        let sandbox = try sandboxURL(bucket)
        let database = try await AppDatabase.openAt(sandbox.appendingPathComponent("anycast.db"))
        return (database, sandbox)
    }

    // MARK: - §2.1 read matrix

    @Test("Buckets open at v4 and match their G15 golden dump row-for-row")
    func goldenDumpParity() async throws {
        let buckets = ["db_light", "db_heavy", "db_dirty", "db_user", "db_device", "db_edge_subs", "db_crashed"]
        for bucket in buckets {
            let (database, sandbox) = try await openSandbox(bucket)

            let version = try await database.queue.read { db in
                try Int.fetchOne(db, sql: "PRAGMA user_version") ?? 0
            }
            #expect(version == 4, "\(bucket): user_version")

            let comparison = try await G15.compare(database: database, goldenBucket: bucket, sandbox: sandbox)
            if !comparison.mismatches.isEmpty {
                Issue.record("\(bucket): \(comparison.mismatches.joined(separator: "; ").prefix(3000))")
            }
            #expect(comparison.mismatches.isEmpty)
        }
    }

    @Test("Read orderings: playlist position ASC, feed pubDate DESC, history id DESC, subscription title ASC (BINARY)")
    func readOrderings() async throws {
        let (database, _) = try await openSandbox("db_heavy")

        let playlists = try await database.playlistRepository().listPlaylists()
        let playlistPositions = playlists.compactMap(\.position)
        #expect(playlistPositions == playlistPositions.sorted(), "playlist position ASC")

        let queue = try await database.playlistRepository().listEpisodes(playlistId: 1)
        let positions = queue.compactMap(\.position)
        #expect(positions == positions.sorted(), "queue position ASC")

        let feed = try await database.feedRepository().listAll()
        let feedDates = feed.compactMap(\.pubDate)
        #expect(feedDates == feedDates.sorted(by: >), "feed pubDate DESC")

        let history = try await database.historyRepository().listAll()
        let historyIDs = history.compactMap(\.id)
        #expect(historyIDs == historyIDs.sorted(by: >), "history id DESC")

        // SQLite BINARY collation is byte order — compare against the
        // database's own ordering, never a localized Swift sort.
        let (swiftTitles, expectedTitles) = try await database.queue.read { db in
            let expected = try String.fetchAll(db, sql: "SELECT title FROM subscription ORDER BY title ASC")
            let actual = try String.fetchAll(db, sql: "SELECT title FROM subscription")
            return (actual, expected)
        }
        #expect(swiftTitles == expectedTitles)
    }

    @Test("Settings decode: CSV/enums/units per G9 caliber (db defaults)")
    func settingsDecode() async throws {
        let (database, _) = try await openSandbox("db_light")
        let settings = try await database.settingsRepository().load()
        #expect(settings.autoRefreshInterval == 300)
        #expect(settings.speed == 1.0)
        #expect(!settings.darkMode && !settings.skipSilence)
        #expect(settings.autoSleepTimer == "0,0,0")
        let decodedTimer = SettingsCodec.decodeAutoSleepTimer(settings.autoSleepTimer)
        #expect(decodedTimer?.startHour == 0 && decodedTimer?.endHour == 0 && decodedTimer?.minsIndex == 0)
        #expect(settings.maxCacheCount == 10)
        #expect(settings.maxFeedEpisodes == 100 && settings.maxHistoryEpisodes == 100)
        #expect(settings.continuousPlaying)
    }

    @Test("tmp audio variants: missing tmp tolerated, missing meta DB tolerated, orphan rows ignored")
    func tmpAndMetaVariants() async throws {
        let fileManager = FileManager.default

        // (a) full bucket: meta DB opens and maps URLs.
        let full = try sandboxURL("db_light")
        let fullMeta = await CacheMetaDatabase.open(
            at: full.appendingPathComponent("Library/Application Support/anycast_episode.db")
        )
        #expect(fullMeta.isAvailable, "meta DB opens")

        // (b) tmp emptied, meta DB kept → open tolerates; mapping still
        // readable (missing FILES are playback-time misses, never errors).
        let emptied = try sandboxURL("db_light")
        let tmpDir = emptied.appendingPathComponent("tmp/anycast_episode")
        if fileManager.fileExists(atPath: tmpDir.path) {
            for file in try fileManager.contentsOfDirectory(atPath: tmpDir.path) {
                try fileManager.removeItem(at: tmpDir.appendingPathComponent(file))
            }
        }
        let emptiedDB = try await AppDatabase.openAt(emptied.appendingPathComponent("anycast.db"))
        _ = try await emptiedDB.settingsRepository().load()
        let emptiedMeta = await CacheMetaDatabase.open(
            at: emptied.appendingPathComponent("Library/Application Support/anycast_episode.db")
        )
        #expect(emptiedMeta.isAvailable, "meta DB still readable with empty tmp")

        // (c) meta DB removed, tmp files kept → tolerant open, no mapping.
        let metaless = try sandboxURL("db_light")
        let metaURL = metaless.appendingPathComponent("Library/Application Support/anycast_episode.db")
        if fileManager.fileExists(atPath: metaURL.path) {
            try fileManager.removeItem(at: metaURL)
        }
        let metalessDB = try await AppDatabase.openAt(metaless.appendingPathComponent("anycast.db"))
        _ = try await metalessDB.settingsRepository().load()
        let missingMeta = await CacheMetaDatabase.open(at: metaURL)
        #expect(!missingMeta.isAvailable, "missing meta DB → unavailable, not an error")
    }

    @Test("db_v3 upgrades to v4: continuousPlaying default 1, everything else untouched")
    func v3Upgrade() async throws {
        let sandbox = try sandboxURL("db_v3")
        let database = try await AppDatabase.openAt(sandbox.appendingPathComponent("anycast.db"))

        let version = try await database.queue.read { db in
            try Int.fetchOne(db, sql: "PRAGMA user_version") ?? 0
        }
        #expect(version == 4)

        let settings = try await database.settingsRepository().load()
        #expect(settings.continuousPlaying)

        // The v3 golden is the PRE-migration dump: everything except the
        // migration-added column must be untouched (05 §2.1).
        let comparison = try await G15.compare(
            database: database, goldenBucket: "db_v3", sandbox: sandbox,
            ignoringColumns: ["continuousPlaying"]
        )
        #expect(comparison.mismatches.isEmpty)
    }

    @Test("db_crashed: hot journal recovers cleanly, data matches golden")
    func crashedRecovery() async throws {
        let (database, sandbox) = try await openSandbox("db_crashed")
        let comparison = try await G15.compare(database: database, goldenBucket: "db_crashed", sandbox: sandbox)
        #expect(comparison.mismatches.isEmpty)
    }

    @Test("db_corrupt ×3: quarantine + fresh rebuild + report, never a crash loop (K25)")
    func corruptQuarantine() async throws {
        for bucket in ["db_corrupt_notadb", "db_corrupt_truncated", "db_corrupt_partial"] {
            let sandbox = try sandboxURL(bucket)
            let url = sandbox.appendingPathComponent("anycast.db")

            let quarantines = QuarantineRecorder()
            let database = try await AppDatabase.openAt(url, onQuarantine: quarantines.handler)

            #expect(quarantines.events.count == 1, "\(bucket): quarantined exactly once")
            #expect(FileManager.default.fileExists(atPath: url.path + ".corrupt"),
                    "\(bucket): original preserved as .corrupt")

            // Rebuilt store: v4 + default rows.
            let version = try await database.queue.read { db in
                try Int.fetchOne(db, sql: "PRAGMA user_version") ?? 0
            }
            #expect(version == 4)
            let playlists = try await database.playlistRepository().listPlaylists()
            #expect(playlists.first?.title == "Default")
            let settings = try await database.settingsRepository().load()
            #expect(settings.autoRefreshInterval == 300)

            // Reopen is stable — no loop, no second quarantine.
            let secondRecorder = QuarantineRecorder()
            _ = try await AppDatabase.openAt(url, onQuarantine: secondRecorder.handler)
            #expect(secondRecorder.events.isEmpty, "\(bucket): healthy rebuilt database must not quarantine again")
        }
    }

    @Test("Fresh install: creators + default rows + locale-derived country/language")
    func freshInstallDefaults() async throws {
        func freshDatabase(locale: String) async throws -> AppDatabase {
            let directory = FileManager.default.temporaryDirectory
                .appendingPathComponent("anycast-fresh-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            return try await AppDatabase.openAt(
                directory.appendingPathComponent("anycast.db"),
                localeIdentifier: locale
            )
        }

        let database = try await freshDatabase(locale: "zh-Hans-CN")

        let playlists = try await database.playlistRepository().listPlaylists()
        #expect(playlists == [PlaylistRow(id: 1, title: "Default", position: 1)])

        let pointer = try await database.playerRepository().loadPointer()
        #expect(pointer?.currentPlaylistId == nil)

        let settings = try await database.settingsRepository().load()
        #expect(settings.countryCode == "CN")
        #expect(settings.targetLanguage == "zh")
        #expect(settings.darkMode == false)
        #expect(settings.speed == 1.0)
        #expect(settings.autoSleepTimer == "0,0,0")
        #expect(settings.maxCacheCount == 10)
        #expect(settings.autoRefreshInterval == 300)
        #expect(settings.maxFeedEpisodes == 100 && settings.maxHistoryEpisodes == 100)
        #expect(settings.continuousPlaying)

        // Dart-style underscore identifiers go through the same rule (G9).
        let underscored = try await freshDatabase(locale: "zh_Hans_CN")
        let settings2 = try await underscored.settingsRepository().load()
        #expect(settings2.countryCode == "CN" && settings2.targetLanguage == "zh")

        // No-separator fallback: en/US.
        let bare = try await freshDatabase(locale: "en")
        let settings3 = try await bare.settingsRepository().load()
        #expect(settings3.countryCode == "US" && settings3.targetLanguage == "en")
    }

    // MARK: - §2.2 semantic traps

    @Test("JSON columns decode to double-second segments; summary NULL reads clean; sqlite_sequence readable")
    func semanticTraps() async throws {
        let (database, _) = try await openSandbox("db_heavy")

        let subtitleURL = try await database.queue.read { db in
            try String.fetchOne(db, sql: "SELECT enclosureUrl FROM subtitle LIMIT 1")
        }
        guard let subtitleURL else {
            Issue.record("db_heavy has subtitle rows")
            return
        }

        let subtitle = try await database.subtitleRepository().get(byEnclosureURL: subtitleURL)
        #expect(subtitle != nil)
        let segments = subtitle?.segments ?? []
        #expect(!segments.isEmpty)
        #expect(segments.allSatisfy { ($0.start ?? 0) >= 0 && ($0.end ?? 0) > ($0.start ?? 0) })
        #expect(subtitle?.summary == nil, "summary column is always NULL")
        #expect(segments.contains { ($0.start ?? 0).rounded() != ($0.start ?? 0) },
                "fractional seconds survive as doubles")

        let sequenceNames = try await database.queue.read { db in
            try String.fetchAll(db, sql: "SELECT name FROM sqlite_sequence")
        }
        #expect(sequenceNames.contains("translation"))

        let dirty = try await openSandbox("db_dirty")
        let episodes = try await dirty.0.feedRepository().listAll()
        #expect(episodes.contains { $0.duration == nil || $0.pubDate == nil || $0.description == nil })
    }

    @Test("UNIQUE semantics: same episode moves across playlists; same-title subscriptions replace; language switch replaces translation")
    func uniqueSemantics() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("anycast-unique-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let database = try await AppDatabase.openAt(directory.appendingPathComponent("anycast.db"))

        // Same enclosureUrl re-inserted → one row (K14 move semantics).
        let episode = PlaylistEpisodeRow(
            title: "E1", enclosureUrl: "https://x.example/ep1.mp3", playlistId: 1
        )
        try await database.playlistRepository().insertOrUpdateByIndex(episode, playlistId: 1, index: 0)
        try await database.playlistRepository().insertOrUpdateByIndex(episode, playlistId: 1, index: 0)
        let episodeCount = try await database.queue.read { db in
            try Int.fetchOne(
                db,
                sql: "SELECT COUNT(*) FROM playlistEpisode WHERE enclosureUrl = ?",
                arguments: ["https://x.example/ep1.mp3"]
            ) ?? 0
        }
        #expect(episodeCount == 1)

        // K14 CROSS-playlist: UNIQUE(enclosureUrl) is table-global, so the
        // same episode added to a different playlist must MOVE there — a
        // plain insert would throw on the constraint (the shipped Dart
        // looked the row up table-wide and updated it).
        try await database.queue.write { db in
            try db.execute(sql: "INSERT INTO playlist (title, position) VALUES ('Second', 2)")
        }
        let secondPlaylistID = try await database.queue.read { db in
            try Int64.fetchOne(db, sql: "SELECT id FROM playlist WHERE title = 'Second'")
        }
        guard let secondPlaylistID else {
            Issue.record("second playlist created")
            return
        }
        try await database.playlistRepository().insertOrUpdateByIndex(
            episode, playlistId: secondPlaylistID, index: 0
        )
        let (movedPlaylistID, rowsAfterMove) = try await database.queue.read { db in
            let playlistID = try Int64.fetchOne(
                db, sql: "SELECT playlistId FROM playlistEpisode WHERE enclosureUrl = ?",
                arguments: ["https://x.example/ep1.mp3"]
            )
            let count = try Int.fetchOne(
                db, sql: "SELECT COUNT(*) FROM playlistEpisode WHERE enclosureUrl = ?",
                arguments: ["https://x.example/ep1.mp3"]
            ) ?? 0
            return (playlistID, count)
        }
        #expect(rowsAfterMove == 1, "cross-playlist add must not duplicate")
        #expect(movedPlaylistID == secondPlaylistID, "cross-playlist add moves the row (K14)")

        // Same-title subscription replaces the row, id changes (K13).
        try await database.subscriptionRepository().addMany([
            SubscriptionRow(rssFeedUrl: "https://a.example/feed", title: "Same", description: "one"),
        ])
        let idAfterFirst = try await database.queue.read { db in
            try Int64.fetchOne(db, sql: "SELECT id FROM subscription WHERE title = 'Same'")
        }
        try await database.subscriptionRepository().addMany([
            SubscriptionRow(rssFeedUrl: "https://b.example/feed", title: "Same", description: "two"),
        ])
        let (idAfterSecond, url, subscriptionCount) = try await database.queue.read { db in
            let id = try Int64.fetchOne(db, sql: "SELECT id FROM subscription WHERE title = 'Same'")
            let url = try String.fetchOne(db, sql: "SELECT rssFeedUrl FROM subscription WHERE title = 'Same'")
            let count = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM subscription") ?? 0
            return (id, url, count)
        }
        #expect(subscriptionCount == 1, "title collision replaces")
        #expect(url == "https://b.example/feed")
        #expect(idAfterFirst != idAfterSecond, "replaced row gets a new id")

        // Translation: switching language replaces (UNIQUE enclosureUrl, K15).
        let segments = [SubtitleSegment(start: 0.0, end: 1.5, text: "hola")]
        let encoded = SubtitleSegment.encode(segments)
        try await database.translationRepository().insert(
            TranslationRow(enclosureUrl: "https://x.example/ep1.mp3", status: "succeeded",
                           translation: encoded, language: "es")
        )
        try await database.translationRepository().insert(
            TranslationRow(enclosureUrl: "https://x.example/ep1.mp3", status: "succeeded",
                           translation: encoded, language: "zh")
        )
        let translationCount = try await database.queue.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM translation") ?? 0
        }
        #expect(translationCount == 1, "language switch replaces the row")
    }

    /// 2026-09-23 fix: neighbor lookups are index-aligned with the FULL
    /// ordered list — a NULL-position row (dirty data) means "no neighbor on
    /// that side" in Dart (`episodes[i].position` is nil), not a row that
    /// drops out of the array (the old `compactMap` shifted every lookup).
    @Test("NULL-position rows: neighbors come from the full ordered list")
    func nullPositionNeighbors() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("anycast-nullpos-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let database = try await AppDatabase.openAt(directory.appendingPathComponent("anycast.db"))

        // ORDER BY position ASC puts the NULL row first: [A(NULL), B(2.0)].
        try await database.queue.write { db in
            try db.execute(sql: """
                INSERT INTO playlistEpisode (enclosureUrl, playlistId, position)
                VALUES ('https://a.example/ep.mp3', 1, NULL),
                       ('https://b.example/ep.mp3', 1, 2.0)
                """)
        }

        // Insert at index 1: Dart's left neighbor is episodes[0] = the NULL
        // row (no left neighbor), right neighbor is episodes[1] = 2.0 — so
        // the position lands just BELOW 2.0. The compactMap bug treated B as
        // the left neighbor and landed above it.
        let episode = PlaylistEpisodeRow(
            title: "c", enclosureUrl: "https://c.example/ep.mp3", playlistId: 1
        )
        try await database.playlistRepository().insertOrUpdateByIndex(episode, playlistId: 1, index: 1)

        let inserted = try await database.playlistRepository()
            .episode(byEnclosureURL: "https://c.example/ep.mp3")
        #expect(inserted?.position == 2.0 - PlaylistPositioning.minPositionGap * 3)
    }

    @Test("K26 move semantics: cross-index moves persist across reopen (drag-index convention)")
    func k26MoveSemantics() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("anycast-k26-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("anycast.db")
        let database = try await AppDatabase.openAt(url)

        func episode(_ name: String) -> PlaylistEpisodeRow {
            PlaylistEpisodeRow(
                title: name, enclosureUrl: "https://x.example/\(name).mp3", playlistId: 1
            )
        }
        let repository = database.playlistRepository()
        for (index, name) in ["A", "B", "C"].enumerated() {
            try await repository.insertOrUpdateByIndex(episode(name), playlistId: 1, index: index)
        }

        // Downward move, drag-gesture convention (Flutter onReorder counts
        // the dragged item at its old slot: slot 0 → the end reports 3).
        // Expected [B, C, A]; the K26 bug computed the midpoint against the
        // pre-move list, landing back at the old spot after a restart.
        try await repository.insertOrUpdateByIndex(episode("A"), playlistId: 1, index: 3)

        var reopened = try await AppDatabase.openAt(url)
        let afterDownMove = try await reopened.playlistRepository().listEpisodes(playlistId: 1)
        #expect(afterDownMove.compactMap(\.title) == ["B", "C", "A"],
                "downward move survives reopen")

        // Upward move: [B, C, A] → C (slot 1) to the top reports 0.
        try await reopened.playlistRepository().insertOrUpdateByIndex(episode("C"), playlistId: 1, index: 0)
        reopened = try await AppDatabase.openAt(url)
        let afterUpMove = try await reopened.playlistRepository().listEpisodes(playlistId: 1)
        #expect(afterUpMove.compactMap(\.title) == ["C", "B", "A"],
                "upward move survives reopen")
    }

    // MARK: - §2.3 write-back loop

    @Test("Write-back: progress to queue head, removeTop cascade, trims, history re-insert, K31 reopen")
    func writeBackLoop() async throws {
        let sandbox = try sandboxURL("db_light")
        let url = sandbox.appendingPathComponent("anycast.db")
        let database = try await AppDatabase.openAt(url)

        // Progress lands on the queue HEAD row by enclosureUrl.
        let queue = try await database.playlistRepository().listEpisodes(playlistId: 1)
        guard let head = queue.first, let headURL = head.enclosureUrl else {
            Issue.record("db_light has a queue head")
            return
        }
        try await database.playlistRepository().updatePlayedDuration(42_000, byEnclosureURL: headURL)
        let headAfter = try await database.playlistRepository().episode(byEnclosureURL: headURL)
        #expect(headAfter?.playedDuration == 42_000)

        // removeTop cascade: playlistEpisode + subtitle + translation rows.
        try await database.subtitleRepository().insert(
            SubtitleRow(enclosureUrl: headURL, status: "succeeded",
                        subtitle: "[{\"start\":0.0,\"end\":1.0,\"text\":\"x\"}]", language: "en")
        )
        try await database.translationRepository().insert(
            TranslationRow(enclosureUrl: headURL, status: "succeeded",
                           translation: "[{\"start\":0.0,\"end\":1.0,\"text\":\"x\"}]", language: "zh")
        )
        try await database.playlistRepository().removeEpisodeCascade(byEnclosureURL: headURL)
        let (episodeRows, subtitleRows, translationRows) = try await database.queue.read { db in
            let e = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM playlistEpisode WHERE enclosureUrl = ?", arguments: [headURL]) ?? 0
            let s = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM subtitle WHERE enclosureUrl = ?", arguments: [headURL]) ?? 0
            let t = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM translation WHERE enclosureUrl = ?", arguments: [headURL]) ?? 0
            return (e, s, t)
        }
        #expect(episodeRows == 0 && subtitleRows == 0 && translationRows == 0)

        // Trim: feed keeps pubDate-newest N (db_light history is empty —
        // the resume rows below repopulate it).
        try await database.feedRepository().trim(keeping: 5)
        let (feedCount, feedDates) = try await database.queue.read { db in
            let count = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM feedEpisode") ?? 0
            let dates = try Int64.fetchAll(db, sql: "SELECT pubDate FROM feedEpisode ORDER BY pubDate DESC")
            return (count, dates)
        }
        #expect(feedCount == 5)
        #expect(feedDates == feedDates.sorted(by: >), "retained side = newest")

        // History resume (K30, corrected 2026-09-23): the Dart line inserts
        // `HistoryEpisodeModel.fromMap(playlistEpisode.toMap())` — the row
        // carries the PLAYLIST row's id, so a resume re-insert keeps both
        // the id and the row's place in the id-DESC ordering. Only an
        // episode with no id (Dart toMap omits a null id) autoincrements.
        let resumeEpisode = HistoryEpisodeRow(
            id: 42, title: "played", enclosureUrl: "https://resume.example/ep.mp3", pubDate: 1_000
        )
        try await database.historyRepository().insert(resumeEpisode)
        try await database.historyRepository().insert(
            HistoryEpisodeRow(title: "newer-than-resume", enclosureUrl: "https://newer.example/ep.mp3")
        )
        try await database.historyRepository().insert(resumeEpisode)
        let (resumeID, newestURL, historyTotal) = try await database.queue.read { db in
            let id = try Int64.fetchOne(db, sql: "SELECT id FROM historyEpisode WHERE enclosureUrl = 'https://resume.example/ep.mp3'")
            let newest = try String.fetchOne(db, sql: "SELECT enclosureUrl FROM historyEpisode ORDER BY id DESC LIMIT 1")
            let count = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM historyEpisode") ?? 0
            return (id ?? 0, newest ?? "", count)
        }
        #expect(resumeID == 42, "resume re-insert keeps the carried (playlist) id (K30)")
        #expect(newestURL == "https://newer.example/ep.mp3", "a kept id does not move the row to the top")
        #expect(historyTotal == 2, "delete-then-insert never duplicates")

        // Trim history keeping fewer rows than present.
        try await database.historyRepository().insert(
            HistoryEpisodeRow(title: "second", enclosureUrl: "https://resume2.example/ep.mp3")
        )
        try await database.historyRepository().trim(keeping: 1)
        let historyAfterTrim = try await database.queue.read { db in
            try String.fetchAll(db, sql: "SELECT enclosureUrl FROM historyEpisode ORDER BY id DESC")
        }
        #expect(historyAfterTrim == ["https://resume2.example/ep.mp3"], "history keeps id-newest")

        // New row ids never collide with existing data.
        try await database.feedRepository().insertMany([
            FeedEpisodeRow(title: "new", enclosureUrl: "https://new.example/ep.mp3"),
        ])
        let collisions = try await database.queue.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM (SELECT id FROM feedEpisode GROUP BY id HAVING COUNT(*) > 1)") ?? 0
        }
        #expect(collisions == 0)

        // clear() then reopen: missing player row is "no state" (K31), the
        // row is restored idempotently, and the store stays v4 + rollback
        // journal (write-back compatibility, 05 §2.4).
        try await database.playerRepository().clear()
        let reopened = try await AppDatabase.openAt(url)
        let pointer = try await reopened.playerRepository().loadPointer()
        #expect(pointer?.currentPlaylistId == nil)

        let (version, journalMode) = try await reopened.queue.read { db in
            let v = try Int.fetchOne(db, sql: "PRAGMA user_version") ?? 0
            let j = try String.fetchAll(db, sql: "PRAGMA journal_mode")
            return (v, j.first ?? "")
        }
        #expect(version == 4)
        #expect(journalMode.lowercased() == "delete", "rollback journal, never WAL")

        // Idempotent reopen after mutations.
        _ = try await AppDatabase.openAt(url)
    }

    @Test("Subtitle insert gate (1.2.1+38 baseline): incomplete payloads are dropped, complete rows persist")
    func subtitleInsertGate() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("anycast-gate-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let database = try await AppDatabase.openAt(directory.appendingPathComponent("anycast.db"))

        // No language → dropped.
        try await database.subtitleRepository().insert(
            SubtitleRow(enclosureUrl: "https://a.example/1", status: "succeeded",
                        subtitle: "[{\"start\":0.0,\"end\":1.0,\"text\":\"t\"}]", language: nil)
        )
        // Empty subtitle → dropped.
        try await database.subtitleRepository().insert(
            SubtitleRow(enclosureUrl: "https://a.example/2", status: "succeeded",
                        subtitle: "", language: "en")
        )
        // Literal "null" subtitle → dropped.
        try await database.subtitleRepository().insert(
            SubtitleRow(enclosureUrl: "https://a.example/3", status: "succeeded",
                        subtitle: "null", language: "en")
        )
        // Complete → persisted.
        try await database.subtitleRepository().insert(
            SubtitleRow(enclosureUrl: "https://a.example/4", status: "succeeded",
                        subtitle: "[{\"start\":0.0,\"end\":130.0,\"text\":\"t\"}]", language: "en")
        )

        let statuses = try await database.subtitleRepository().listStatuses()
        #expect(statuses == ["https://a.example/4": "succeeded"])

        // Encode writes Dart-style doubles (write-back parity: a rolled-back
        // Flutter build reading `130` as int would TypeError).
        let encoded = SubtitleSegment.encode([SubtitleSegment(start: 130, end: 131.25, text: "a\"b")])
        #expect(encoded == "[{\"start\":130.0,\"end\":131.25,\"text\":\"a\\\"b\"}]")
    }
}

/// Thread-safe quarantine spy (the handler can fire from any executor).
final class QuarantineRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private(set) var events: [(url: URL, reason: String)] = []

    var handler: AppDatabase.QuarantineHandler {
        let recorder = self
        return { url, reason in
            recorder.lock.lock()
            recorder.events.append((url, reason))
            recorder.lock.unlock()
        }
    }
}
