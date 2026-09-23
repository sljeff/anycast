import Foundation
import MediaPlayer
import Testing
@testable import AnycastKit

/// §5.1 playback state machine (docs/migration/05 §5.1): the queue
/// semantics run against a scriptable engine, the REAL GRDB repositories
/// on a temp database (SQL truth), and a recording cache — every row
/// pinned by the Dart baseline (K3/K4/K6/K11/K24/K30/K31, 08 §12.2).
@MainActor
@Suite(.serialized)
struct PlaybackStateMachineTests {

    // MARK: - Fakes

    @MainActor
    final class FakePlaybackEngine: PlaybackEngine {
        var events: (@MainActor (PlaybackEngineEvent) -> Void)?

        private(set) var loads: [(url: URL, initialPositionMilliseconds: Int64)] = []
        private(set) var playCount = 0
        private(set) var pauseCount = 0
        private(set) var seeks: [Int64] = []
        private(set) var speeds: [Float] = []

        var hasItem = false
        var positionMilliseconds: Int64 = 0
        var durationMilliseconds: Int64?
        var bufferedMilliseconds: Int64 = 0
        var rate: Float = 1.0

        /// Real AVPlayer resets currentTime to zero on replaceCurrentItem
        /// and lands the initial seek only some time later. The default
        /// applies the position synchronously; load-window races flip this.
        var appliesInitialPositionSynchronously = true

        func load(url: URL, initialPositionMilliseconds: Int64) {
            loads.append((url, initialPositionMilliseconds))
            hasItem = true
            positionMilliseconds =
                appliesInitialPositionSynchronously ? initialPositionMilliseconds : 0
        }

        func playImmediately() { playCount += 1 }
        func pause() { pauseCount += 1 }
        func seek(toMilliseconds: Int64) {
            seeks.append(toMilliseconds)
            positionMilliseconds = toMilliseconds
        }
        func setDesiredSpeed(_ speed: Float) { speeds.append(speed) }

        func emit(_ event: PlaybackEngineEvent) { events?(event) }
    }

    actor FakeCache: EpisodeCaching {
        var files: [String: URL] = [:]
        private(set) var downloads: [String] = []
        private(set) var removed: [String] = []

        func cachedFile(for url: String) -> URL? { files[url] }

        func startDownload(url: String, onProgress: @escaping @Sendable (Double?) -> Void) -> Task<URL, Error> {
            downloads.append(url)
            return Task { URL(fileURLWithPath: "/tmp/\(url.suffix(8)).mp3") }
        }

        func remove(url: String) async {
            removed.append(url)
            files[url] = nil
        }

        func setFile(url: String, file: URL) {
            files[url] = file
        }
    }

    final class NoArtwork: NowPlayingController.ArtworkProviding {
        func artwork(for urlString: String?) async -> UIImage? { nil }
    }

    final class FakeClock: @unchecked Sendable {
        var value: Int64 = 1_000_000
        func advance(_ ms: Int64) { value += ms }
        var now: Int64 { value }
    }

    final class SessionSpy: AudioSessionController.Backend, @unchecked Sendable {
        enum Call: Equatable { case setCategory, activate, deactivate }
        private let lock = NSLock()
        private var _calls: [Call] = []
        var calls: [Call] { lock.lock(); defer { lock.unlock() }; return _calls }
        func setCategoryPlayback() throws { lock.lock(); _calls.append(.setCategory); lock.unlock() }
        func activate() throws { lock.lock(); _calls.append(.activate); lock.unlock() }
        func deactivate(notifyOthers: Bool) throws { lock.lock(); _calls.append(.deactivate); lock.unlock() }
        func setInterruptionHandler(_ handler: @escaping @Sendable (AudioSessionController.Interruption) -> Void) {}
        func setRouteChangeHandler(_ handler: @escaping @Sendable (AudioSessionController.RouteChange) -> Void) {}
    }

    // MARK: - Harness

    @MainActor
    final class Harness {
        let database: AppDatabase
        let engine: FakePlaybackEngine
        let cache: FakeCache
        let sessionBackend: SessionSpy
        let service: PlaybackService
        let clock: FakeClock
        let databaseURL: URL

        init(database: AppDatabase, engine: FakePlaybackEngine, cache: FakeCache,
             sessionBackend: SessionSpy, service: PlaybackService, clock: FakeClock,
             databaseURL: URL) {
            self.database = database
            self.engine = engine
            self.cache = cache
            self.sessionBackend = sessionBackend
            self.service = service
            self.clock = clock
            self.databaseURL = databaseURL
        }
    }

    private func makeHarness(
        settings: AppSettings = .defaults(localeIdentifier: "en_US"),
        seed: Bool = true
    ) async throws -> Harness {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("playback-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let databaseURL = directory.appendingPathComponent("anycast.db")
        let database = try await AppDatabase.openAt(databaseURL)
        if seed {
            try await seedQueue(database)
        }

        let clock = FakeClock()
        let backend = SessionSpy()
        let engine = FakePlaybackEngine()
        let cache = FakeCache()
        let service = PlaybackService(
            engine: engine,
            cache: cache,
            store: DatabasePlaybackStore(database: database),
            settings: settings,
            session: AudioSessionController(backend: backend),
            nowPlaying: NowPlayingController(artworkProvider: NoArtwork()),
            nowMilliseconds: { clock.now }
        )
        return Harness(database: database, engine: engine, cache: cache,
                       sessionBackend: backend, service: service, clock: clock,
                       databaseURL: databaseURL)
    }

    /// Two queued episodes; subtitle + translation rows ride on the head.
    private func seedQueue(_ database: AppDatabase) async throws {
        let repository = database.playlistRepository()
        let episodes = [
            PlaylistEpisodeRow(id: nil, title: "Ep 1", description: nil, duration: 600_000,
                               enclosureUrl: "https://x.example/ep1.mp3", pubDate: 1_000,
                               imageUrl: "https://x.example/cover1.jpg", channelTitle: "Channel",
                               rssFeedUrl: "https://x.example/feed.xml",
                               playlistId: 1, position: nil, playedDuration: 120_000),
            PlaylistEpisodeRow(id: nil, title: "Ep 2", description: nil, duration: 600_000,
                               enclosureUrl: "https://x.example/ep2.mp3", pubDate: 2_000,
                               imageUrl: "https://x.example/cover2.jpg", channelTitle: "Channel",
                               rssFeedUrl: "https://x.example/feed.xml",
                               playlistId: 1, position: nil, playedDuration: 0),
        ]
        for (index, episode) in episodes.enumerated() {
            try await repository.insertOrUpdateByIndex(episode, playlistId: 1, index: index)
        }
        try await database.subtitleRepository().insert(SubtitleRow(
            enclosureUrl: "https://x.example/ep1.mp3", status: "succeeded",
            subtitle: SubtitleSegment.encode([SubtitleSegment(start: 0, end: 4, text: "hi")]),
            language: "en"
        ))
        try await database.translationRepository().insert(TranslationRow(
            enclosureUrl: "https://x.example/ep1.mp3", status: "succeeded",
            translation: SubtitleSegment.encode([SubtitleSegment(start: 0, end: 4, text: "你好")]),
            language: "zh"
        ))
    }

    /// Restore the pointer so the service has a queue (as the startup DAG
    /// does after settings load).
    private func restore(_ harness: Harness,
                         settings: AppSettings = .defaults(localeIdentifier: "en_US")) async {
        await harness.service.restore(pointer: PlayerPointer(currentPlaylistId: 1),
                                      settings: settings)
    }

    private func waitUntil(_ condition: @MainActor () async -> Bool) async {
        for _ in 0..<2_000 {
            if await condition() { return }
            try? await Task.sleep(for: .milliseconds(2))
        }
    }

    // MARK: - §5.1 cache-hit / cache-miss loading

    @Test("cache hit: local file loads at playedDuration; no download starts")
    func cacheHitLoad() async throws {
        let harness = try await makeHarness()
        await restore(harness)
        let local = URL(fileURLWithPath: "/tmp/ep1.mp3")
        await harness.cache.setFile(url: "https://x.example/ep1.mp3", file: local)

        await harness.service.playByEpisode(harness.service.queue.first!)

        #expect(harness.engine.loads.count == 1)
        #expect(harness.engine.loads[0].url == local)
        #expect(harness.engine.loads[0].initialPositionMilliseconds == 120_000,
                "resume from playedDuration")
        #expect(await harness.cache.downloads.isEmpty, "cache hit never re-downloads")
    }

    @Test("cache miss: stream the URL while the full file downloads in parallel")
    func cacheMissLoad() async throws {
        let harness = try await makeHarness()
        await restore(harness)
        await harness.service.playByEpisode(harness.service.queue.first!)

        #expect(harness.engine.loads.count == 1)
        #expect(harness.engine.loads[0].url.absoluteString == "https://x.example/ep1.mp3")
        #expect(harness.engine.loads[0].initialPositionMilliseconds == 120_000)
        await waitUntil { await harness.cache.downloads.count == 1 }
        #expect(await harness.cache.downloads == ["https://x.example/ep1.mp3"],
                "playing an episode caches the whole file (play-to-cache)")
    }

    @Test("mediaItem publishes at load INITIATION — before loading finishes (08 §12.2)")
    func mediaItemTiming() async throws {
        let harness = try await makeHarness()
        await restore(harness)
        await harness.service.playByEpisode(harness.service.queue.first!)

        // The fake engine never "finishes" loading — yet the metadata is
        // already published.
        #expect(harness.engine.loads.count == 1)
        #expect(harness.service.nowPlaying.currentInfo[MPMediaItemPropertyTitle] as? String == "Ep 1")
        #expect(harness.service.nowPlaying.currentInfo[MPMediaItemPropertyAlbumTitle] as? String == "Channel")
    }

    // MARK: - §5.1 completion chain (K3)

    @Test("completion removes the head (rows + cache) and plays the next episode")
    func completionAdvances() async throws {
        let harness = try await makeHarness()
        await restore(harness)
        let removedByHook = L2ContractTests.Locked<[String]>([])
        harness.service.onEpisodeRemoved = { url in removedByHook.with { $0.append(url) } }

        await harness.service.playByEpisode(harness.service.queue.first!)
        harness.engine.emit(.playingChanged(true))
        harness.engine.emit(.completed)

        await waitUntil { harness.service.currentEpisode?.enclosureUrl == "https://x.example/ep2.mp3" }

        // The finished episode is gone from every store: queue rows…
        let remaining = try await harness.database.playlistRepository().listEpisodes(playlistId: 1)
        #expect(remaining.map(\.enclosureUrl) == ["https://x.example/ep2.mp3"])
        // …its subtitle and translation rows (K3 cascade)…
        #expect(try await harness.database.subtitleRepository().get(byEnclosureURL: "https://x.example/ep1.mp3") == nil)
        #expect(try await harness.database.translationRepository().get(byEnclosureURL: "https://x.example/ep1.mp3", language: "zh") == nil)
        // …and its cache file.
        #expect(await harness.cache.removed == ["https://x.example/ep1.mp3"])
        #expect(removedByHook.with { $0 } == ["https://x.example/ep1.mp3"])

        // The next head plays automatically.
        #expect(harness.engine.loads.map(\.url.absoluteString).last == "https://x.example/ep2.mp3")
        #expect(harness.engine.loads.last?.initialPositionMilliseconds == 0)
        await harness.service.flushStoreWrites()
        let history = try await harness.database.historyRepository().listAll()
        #expect(history.contains { $0.enclosureUrl == "https://x.example/ep2.mp3" })
    }

    @Test("continuousPlaying off: after completion the service pauses and resets the progress display")
    func completionStopsWithoutContinuous() async throws {
        var settings = AppSettings.defaults(localeIdentifier: "en_US")
        settings.continuousPlaying = false
        let harness = try await makeHarness(settings: settings)
        await restore(harness, settings: settings)

        await harness.service.playByEpisode(harness.service.queue.first!)
        harness.engine.emit(.playingChanged(true))
        harness.engine.emit(.completed)

        await waitUntil { harness.service.currentEpisode?.enclosureUrl == "https://x.example/ep2.mp3" }
        await waitUntil { harness.service.isPlaying == false }

        // The next episode LOADED (queue-head semantics) but paused, with
        // the progress display reset to its saved position.
        #expect(harness.engine.loads.count == 2)
        #expect(harness.engine.pauseCount >= 1)
        #expect(harness.service.positionData.positionMilliseconds == 0,
                "initProgress shows the new head's playedDuration")
    }

    @Test("continuousPlaying off: the transition pause never persists the pre-seek ~0 over the new head")
    func completionPauseKeepsHeadProgress() async throws {
        var settings = AppSettings.defaults(localeIdentifier: "en_US")
        settings.continuousPlaying = false
        let harness = try await makeHarness(settings: settings)
        // The new head carries half-listened progress…
        try await harness.database.playlistRepository()
            .updatePlayedDuration(40_000, byEnclosureURL: "https://x.example/ep2.mp3")
        await restore(harness, settings: settings)

        // …and the engine behaves like real AVPlayer across the transition
        // load: position reads zero until the pending initial seek lands.
        harness.engine.appliesInitialPositionSynchronously = false
        await harness.service.playByEpisode(harness.service.queue.first!)
        harness.engine.emit(.playingChanged(true))
        harness.engine.emit(.completed)
        await waitUntil { harness.engine.pauseCount >= 1 }

        await harness.service.flushStoreWrites()
        let row = try await harness.database.playlistRepository()
            .episode(byEnclosureURL: "https://x.example/ep2.mp3")
        #expect(row?.playedDuration == 40_000,
                "the head keeps its saved progress (Dart's pause persists nothing)")
        #expect(harness.service.queue.first?.playedDuration == 40_000)
        #expect(harness.service.positionData.positionMilliseconds == 40_000,
                "initProgress shows the saved position, not the engine's pre-seek zero")
    }

    @Test("drained queue: pause + clear — the player pointer row is deleted (K31 stays recoverable)")
    func drainedQueueClears() async throws {
        // Single-episode queue: complete it and the queue drains.
        let harness = try await makeHarness(seed: false)
        let repository = harness.database.playlistRepository()
        try await repository.insertOrUpdateByIndex(
            PlaylistEpisodeRow(title: "Ep only", duration: 600_000,
                               enclosureUrl: "https://x.example/only.mp3",
                               channelTitle: "Channel", rssFeedUrl: "https://x.example/feed.xml",
                               playlistId: 1, playedDuration: 0),
            playlistId: 1, index: 0
        )
        await restore(harness)

        await harness.service.playByEpisode(harness.service.queue.first!)
        harness.engine.emit(.playingChanged(true))
        harness.engine.emit(.completed)

        await waitUntil { harness.service.currentPlaylistId == nil }
        #expect(harness.engine.pauseCount >= 1)
        await harness.service.flushStoreWrites()

        // Pointer row gone: K31 — reopening re-creates defaults and reads
        // "no playback state" without an error.
        let pointer = try await harness.database.playerRepository().loadPointer()
        #expect(pointer?.currentPlaylistId == nil)

        let reopened = try await AppDatabase.openAt(harness.databaseURL)
        let restored = try await reopened.playerRepository().loadPointer()
        #expect(restored?.currentPlaylistId == nil)

        // Queue drained → the session deactivates politely (K18).
        #expect(harness.sessionBackend.calls.contains(.deactivate))
    }

    // MARK: - §5.1 seek paths

    @Test("seekByRelative clamps to [0, duration]; nil duration no longer crashes (K4)")
    func relativeSeekClamps() async throws {
        let harness = try await makeHarness()
        await restore(harness)
        await harness.service.playByEpisode(harness.service.queue.first!)

        harness.engine.positionMilliseconds = 5_000
        harness.engine.durationMilliseconds = 100_000
        harness.service.seekByRelative(10_000)
        #expect(harness.engine.seeks.last == 15_000)

        harness.service.seekByRelative(1_000_000)
        #expect(harness.engine.seeks.last == 100_000, "upper clamp to duration")

        harness.service.seekByRelative(-1_000_000)
        #expect(harness.engine.seeks.last == 0, "lower clamp to zero")

        // Unknown duration: no crash, no upper clamp (K4 fix — the Dart
        // `_player.duration!` crash family).
        harness.engine.durationMilliseconds = nil
        harness.service.seekByRelative(1_000_000)
        #expect(harness.engine.seeks.last == 1_000_000)
    }

    @Test("seek on the loaded episode: pause → seek → play, and NO extra history insert")
    func seekSameEpisode() async throws {
        let harness = try await makeHarness()
        await restore(harness)
        await harness.service.playByEpisode(harness.service.queue.first!)

        #expect(try await harness.database.historyRepository().listAll().count == 1,
                "playByEpisode inserts history once")

        await harness.service.seek(50_000)
        #expect(harness.engine.pauseCount >= 1, "pause first (the old unawaited pause)")
        #expect(harness.engine.seeks == [50_000])
        #expect(harness.engine.playCount >= 2)
        #expect(try await harness.database.historyRepository().listAll().count == 1,
                "same-episode seek never re-inserts history")
    }

    @Test("seek before anything is loaded reloads the episode at the target (mini-player +30 s path)")
    func seekWithoutLoadedItem() async throws {
        let harness = try await makeHarness()
        await restore(harness)
        #expect(harness.engine.loads.isEmpty, "cold restore preloads nothing")

        await harness.service.seek(150_000)
        #expect(harness.engine.loads.count == 1)
        #expect(harness.engine.loads[0].initialPositionMilliseconds == 150_000,
                "reload carries the seek target as the initial position")

        // Dart's seek path is handler-level on a different/unloaded episode:
        // no history insert, no pointer write (unlike a controller-level
        // playByEpisode).
        await harness.service.flushStoreWrites()
        #expect(try await harness.database.historyRepository().listAll().isEmpty,
                "the cold-seek reload never inserts history")
        let pointer = try await harness.database.playerRepository().loadPointer()
        #expect(pointer?.currentPlaylistId == nil, "and never writes the pointer")
    }

    // MARK: - §5.1 progress persistence (K24) + event filter (K11)

    @Test("progress persists every 2 s while playing, and on pause / background")
    func progressPersistence() async throws {
        let harness = try await makeHarness()
        await restore(harness)
        await harness.service.playByEpisode(harness.service.queue.first!)
        harness.engine.emit(.playingChanged(true))

        func playedDurationInDB() async throws -> Int64 {
            await harness.service.flushStoreWrites()
            let row = try await harness.database.playlistRepository()
                .episode(byEnclosureURL: "https://x.example/ep1.mp3")
            return row?.playedDuration ?? -1
        }

        // Ticks every 500 ms of fake time; only the 2 s boundary persists.
        for step in 1...5 {
            harness.clock.advance(500)
            harness.engine.positionMilliseconds = Int64(step) * 500
            harness.engine.emit(.positionTick(
                positionMilliseconds: harness.engine.positionMilliseconds,
                bufferedMilliseconds: 600_000,
                durationMilliseconds: 600_000
            ))
        }
        #expect(try await playedDurationInDB() == 2_000)

        harness.clock.advance(2_000)
        harness.engine.positionMilliseconds = 4_500
        harness.engine.emit(.positionTick(positionMilliseconds: 4_500,
                                          bufferedMilliseconds: 600_000,
                                          durationMilliseconds: 600_000))
        #expect(try await playedDurationInDB() == 4_500)

        // Pause saves immediately (K24).
        harness.engine.positionMilliseconds = 5_200
        harness.service.pause()
        #expect(try await playedDurationInDB() == 5_200)

        // Background entry saves again (K24).
        harness.engine.positionMilliseconds = 5_400
        harness.service.applicationDidEnterBackground()
        #expect(try await playedDurationInDB() == 5_400)
    }

    @Test("K11: paused / loading / zero-position / zero-buffered ticks never move the progress UI")
    func progressEventFilter() async throws {
        let harness = try await makeHarness()
        await restore(harness)
        await harness.service.playByEpisode(harness.service.queue.first!)
        harness.engine.emit(.playingChanged(true))
        harness.engine.emit(.positionTick(positionMilliseconds: 8_000,
                                          bufferedMilliseconds: 600_000,
                                          durationMilliseconds: 600_000))
        #expect(harness.service.positionData.positionMilliseconds == 8_000)

        // Not playing → frozen.
        harness.engine.emit(.playingChanged(false))
        harness.engine.emit(.positionTick(positionMilliseconds: 9_000,
                                          bufferedMilliseconds: 600_000,
                                          durationMilliseconds: 600_000))
        #expect(harness.service.positionData.positionMilliseconds == 8_000)

        // Loading → frozen.
        harness.engine.emit(.playingChanged(true))
        harness.engine.emit(.loadingChanged(true))
        harness.engine.emit(.positionTick(positionMilliseconds: 10_000,
                                          bufferedMilliseconds: 600_000,
                                          durationMilliseconds: 600_000))
        #expect(harness.service.positionData.positionMilliseconds == 8_000)

        // position == 0 or buffered == 0 → frozen.
        harness.engine.emit(.loadingChanged(false))
        harness.engine.emit(.positionTick(positionMilliseconds: 0,
                                          bufferedMilliseconds: 600_000,
                                          durationMilliseconds: 600_000))
        #expect(harness.service.positionData.positionMilliseconds == 8_000)
        harness.engine.emit(.positionTick(positionMilliseconds: 11_000,
                                          bufferedMilliseconds: 0,
                                          durationMilliseconds: 600_000))
        #expect(harness.service.positionData.positionMilliseconds == 8_000)

        // Healthy tick moves it again.
        harness.engine.emit(.positionTick(positionMilliseconds: 12_000,
                                          bufferedMilliseconds: 600_000,
                                          durationMilliseconds: 600_000))
        #expect(harness.service.positionData.positionMilliseconds == 12_000)
    }

    // MARK: - Cold-start restore

    @Test("cold restore shows the saved position, preloads NOTHING, and re-applies the persisted speed")
    func coldRestore() async throws {
        var settings = AppSettings.defaults(localeIdentifier: "en_US")
        settings.speed = 1.5
        let harness = try await makeHarness(settings: settings)
        await restore(harness, settings: settings)

        #expect(harness.engine.loads.isEmpty, "no source preloaded before the user plays")
        #expect(harness.service.currentEpisode?.enclosureUrl == "https://x.example/ep1.mp3")
        #expect(harness.service.positionData.positionMilliseconds == 120_000,
                "UI progress = playedDuration")
        #expect(harness.service.positionData.durationMilliseconds == 600_000,
                "UI duration = RSS duration")
        #expect(harness.engine.speeds.last == 1.5,
                "the persisted speed reaches the engine at restore (§5.6)")

        // First play loads at the saved position and activates the session.
        await harness.service.play()
        #expect(harness.engine.loads.count == 1)
        #expect(harness.engine.loads[0].initialPositionMilliseconds == 120_000)
        #expect(harness.sessionBackend.calls.contains(.activate))
    }

    // MARK: - K30 history semantics

    @Test("every resume re-inserts history; id and ordering position stay unchanged (K30)")
    func historyResumeSemantics() async throws {
        let harness = try await makeHarness()
        await restore(harness)
        await harness.service.playByEpisode(harness.service.queue.first!)

        let first = try await harness.database.historyRepository().listAll()
        #expect(first.count == 1)

        // Pause → resume: the delete+INSERT(REPLACE) keeps the same id.
        harness.service.pause()
        await harness.service.play()
        let second = try await harness.database.historyRepository().listAll()
        #expect(second.count == 1)
        #expect(second.first?.id == first.first?.id, "id unchanged — no reordering")
    }

    // MARK: - K6 failure + retry

    @Test("engine failure surfaces as an error; retry reloads at the last position (K6)")
    func failureAndRetry() async throws {
        let harness = try await makeHarness()
        await restore(harness)
        await harness.service.playByEpisode(harness.service.queue.first!)
        harness.engine.emit(.playingChanged(true))
        harness.engine.positionMilliseconds = 130_000

        harness.engine.emit(.failed("network gone"))
        #expect(harness.service.playbackError == "network gone")

        await harness.service.retry()
        #expect(harness.service.playbackError == nil)
        #expect(harness.engine.loads.count == 2)
        #expect(harness.engine.loads.last?.initialPositionMilliseconds == 130_000,
                "retry resumes from the last known position")
        #expect(harness.engine.playCount >= 2)
    }

    // MARK: - speed (§5.6)

    @Test("speed applies to the engine and persists; the 7 slider values stay exact (G9)")
    func speedSetting() async throws {
        let harness = try await makeHarness()
        await restore(harness)
        await harness.service.playByEpisode(harness.service.queue.first!)

        harness.service.setSpeed(1.5)
        #expect(harness.engine.speeds.last == 1.5)
        await harness.service.flushStoreWrites()
        let settings = try await harness.database.settingsRepository().load()
        #expect(settings.speed == 1.5)

        #expect(SettingsCodec.speedSteps == [0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0])
    }
}
