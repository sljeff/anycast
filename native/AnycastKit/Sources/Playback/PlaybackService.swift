import Foundation
import Observation

/// The application-layer playback queue — the merged port of Dart's
/// `PlayerController` + `MyAudioHandler` (states/player.dart,
/// utils/audio_handler.dart). One engine, one item; the QUEUE is the
/// `playlistEpisode` table, and **episodes[0] is always the current track**
/// (K3, docs/migration/04 §1.2).
///
/// Behavior pinned by 05 §5.1 (unit-tested against a scriptable engine):
/// - cache hit loads the local file at `playedDuration`; a miss streams the
///   URL while a full-file download runs in parallel (the old double-pull,
///   deliberately kept for v1 — 08 §5.3);
/// - a completed track is REMOVED from the queue (with its subtitle,
///   translation and cache file), then the new head plays; an emptied queue
///   pauses and clears the player pointer;
/// - progress persists every 2 s while playing, plus on pause and on
///   entering the background (K24), throttled at the periodic-observer
///   (08 §4.3);
/// - UI progress events are filtered exactly like the old four-condition
///   gate (K11): not playing / loading / position==0 / buffered==0 never
///   move the progress UI;
/// - every play/resume re-inserts the history row carrying the playlist
///   row's id (K30 — id and ordering position unchanged);
/// - Now Playing metadata updates the moment a load is INITIATED, before
///   it finishes (08 §12.2);
/// - load/playback failures surface as `playbackError` with `retry()`
///   (K6 — the old app buffered silently forever).
@MainActor
@Observable
public final class PlaybackService {

    public struct PositionData: Equatable, Sendable {
        public var positionMilliseconds: Int64
        public var bufferedMilliseconds: Int64
        public var durationMilliseconds: Int64
        public static let zero = PositionData(positionMilliseconds: 0, bufferedMilliseconds: 0, durationMilliseconds: 0)
    }

    // MARK: - UI state

    public private(set) var isPlaying = false
    public private(set) var isLoading = false
    public private(set) var positionData = PositionData.zero
    /// The current track (`playlistEpisode.value`).
    public private(set) var currentEpisode: PlaylistEpisodeRow?
    /// The current playlist's rows, position ASC; index 0 == current.
    public private(set) var queue: [PlaylistEpisodeRow] = []
    /// `player.currentPlaylistId`; nil = no playback state.
    public private(set) var currentPlaylistId: Int64?
    /// K6: last load/playback failure, cleared on retry/play.
    public private(set) var playbackError: String?
    /// Download progress per enclosure URL (1 = complete); the card state
    /// map of the old `CacheController.key2FileResponse`.
    public private(set) var cacheStates: [String: Double] = [:]
    public private(set) var speed: Float = 1.0

    // MARK: - Collaborators

    public let session: AudioSessionController
    public let nowPlaying: NowPlayingController
    private let engine: any PlaybackEngine
    private let cache: any EpisodeCaching
    private let store: any PlaybackStore
    private let nowMilliseconds: @Sendable () -> Int64
    private var settings: AppSettings

    /// Set by the composition root: queue removals must also drop the URL
    /// from the subtitle/translation pollers (the Dart removeTop cascaded
    /// into both controllers).
    public var onEpisodeRemoved: ((String) -> Void)?

    /// The enclosure URL of the source the engine currently holds (the Dart
    /// `mediaItem.value?.id` comparison in seekAndPlayByEpisode).
    private var loadedEnclosureURL: String?
    private var lastProgressPersistAt: Int64 = 0

    /// Fire-and-forget store writes, tracked so tests (and a future
    /// graceful-quit path) can await them.
    private var storeWrites: [Task<Void, Never>] = []

    public init(
        engine: any PlaybackEngine,
        cache: any EpisodeCaching,
        store: any PlaybackStore,
        settings: AppSettings,
        session: AudioSessionController,
        nowPlaying: NowPlayingController,
        nowMilliseconds: @escaping @Sendable () -> Int64 = { Int64(Date().timeIntervalSince1970 * 1000) }
    ) {
        self.engine = engine
        self.cache = cache
        self.store = store
        self.settings = settings
        self.session = session
        self.nowPlaying = nowPlaying
        self.nowMilliseconds = nowMilliseconds
        self.speed = Float(settings.speed)

        engine.events = { [weak self] event in
            self?.handle(event)
        }
    }

    /// Awaits every pending store write (test determinism; also usable on
    /// app termination).
    public func flushStoreWrites() async {
        while let task = storeWrites.popLast() {
            await task.value
        }
        storeWrites.removeAll()
    }

    // MARK: - Cold-start restore (no source preloaded)

    /// Startup DAG step: restore the pointer and the queue for display —
    /// position shows `playedDuration`, the engine stays EMPTY until the
    /// user actually plays (docs/migration/04 §3.2).
    public func restore(pointer: PlayerPointer?, settings: AppSettings) async {
        self.settings = settings
        self.speed = Float(settings.speed)
        engine.setDesiredSpeed(speed)

        guard let playlistId = pointer?.currentPlaylistId else { return }
        currentPlaylistId = playlistId
        queue = (try? await store.episodes(playlistId: playlistId)) ?? []
        if let head = queue.first {
            currentEpisode = head
            initProgress()
        }
    }

    // MARK: - Transport

    /// Play a specific episode (queue head, inbox play, search play): the
    /// full path — pointer, history, load, activate, play.
    public func playByEpisode(_ episode: PlaylistEpisodeRow) async {
        guard let playlistId = episode.playlistId else { return }
        currentPlaylistId = playlistId
        currentEpisode = episode
        initProgress()
        if queue.first?.enclosureUrl != episode.enclosureUrl {
            queue = (try? await store.episodes(playlistId: playlistId)) ?? []
        }

        try? await store.insertHistory(episode: episode)
        trackStoreWrite { try await self.store.savePointer(playlistId: playlistId) }

        await setByEpisodeInner(episode)
        session.activateForPlayback()
        playbackError = nil
        engine.playImmediately()
    }

    /// Load without playing — the reorder-involving-index-0 path
    /// (`setByEpisode`, pause + reload; the 100 ms blocking sleep of the
    /// Dart `move()` is cargo cult and NOT ported — 08 §11.4).
    public func setByEpisode(_ episode: PlaylistEpisodeRow) async {
        guard let playlistId = episode.playlistId else { return }
        currentPlaylistId = playlistId
        currentEpisode = episode
        initProgress()
        trackStoreWrite { try await self.store.savePointer(playlistId: playlistId) }
        await setByEpisodeInner(episode)
    }

    /// The Dart `autoSet`: cache hit → local file at the saved position;
    /// miss → stream the URL while the full file downloads in parallel.
    /// Metadata publishes BEFORE the load completes (08 §12.2); the load
    /// future itself is discarded (failures arrive as engine events, K6).
    private func setByEpisodeInner(_ episode: PlaylistEpisodeRow) async {
        guard let urlString = episode.enclosureUrl else { return }
        let initialPosition = episode.playedDuration ?? 0
        loadedEnclosureURL = urlString
        lastProgressPersistAt = nowMilliseconds()
        playbackError = nil

        // mediaItem timing: published the moment loading is initiated.
        nowPlaying.update(
            metadata: NowPlayingController.Metadata(
                title: episode.title ?? "",
                channelTitle: episode.channelTitle,
                durationMilliseconds: episode.duration,
                artworkURL: episode.imageUrl
            ),
            speed: speed,
            positionMilliseconds: initialPosition,
            playing: false
        )

        if let file = await cache.cachedFile(for: urlString) {
            guard loadedEnclosureURL == urlString else { return }
            engine.load(url: file, initialPositionMilliseconds: initialPosition)
        } else if let remote = URL(string: urlString) {
            engine.load(url: remote, initialPositionMilliseconds: initialPosition)
            cacheStates[urlString] = 0
            observeDownload(urlString)
        } else {
            playbackError = "Invalid audio URL"
        }
    }

    /// Download progress → the card state map (the old
    /// `key2FileResponse`/`CacheController.get`).
    private func observeDownload(_ urlString: String) {
        Task { [weak self] in
            guard let self else { return }
            let task = await self.cache.startDownload(url: urlString) { [weak self] progress in
                Task { @MainActor in
                    guard let self, let progress else { return }
                    self.cacheStates[urlString] = progress
                }
            }
            _ = try? await task.value
            await MainActor.run { [weak self] in
                guard let self else { return }
                if self.cacheStates[urlString] != nil {
                    self.cacheStates[urlString] = 1
                }
            }
        }
    }

    /// Resume/pause entry (mini player, lock screen toggle, lyrics tap).
    public func play() async {
        if !engine.hasItem {
            guard let episode = currentEpisode else { return }
            await playByEpisode(episode)
            return
        }
        if let episode = currentEpisode {
            // K30: every resume re-inserts the history row (same id — the
            // delete+INSERT(REPLACE) preserves it).
            try? await store.insertHistory(episode: episode)
        }
        session.activateForPlayback()
        playbackError = nil
        engine.playImmediately()
    }

    public func pause() {
        engine.pause()
        saveProgressNow()
    }

    /// The completed-transition pause: Dart's pause here is handler-level
    /// and never persists (its only writer is the 2 s timer, gated on
    /// isPlaying). The new head's initial seek has not landed yet either, so
    /// reading the engine position now would persist ~0 over the head's
    /// saved playedDuration.
    private func pauseEngineOnly() {
        engine.pause()
    }

    public func togglePlay() async {
        guard currentEpisode != nil else { return }
        if isPlaying {
            pause()
        } else {
            await play()
        }
    }

    /// Progress-bar seek / mini-player +30 s — the `seekAndPlayByEpisode`
    /// semantics: an unawaited pause first; SAME episode → seek + play
    /// (no history insert); DIFFERENT → the Dart HANDLER-level reload (load
    /// + play only — unlike a controller-level playByEpisode it inserts no
    /// history row and writes no pointer). The target only enters memory;
    /// the 2 s persist still owns the DB.
    public func seek(_ positionMilliseconds: Int64) async {
        guard let episode = currentEpisode else { return }
        engine.pause()
        if engine.hasItem && loadedEnclosureURL == episode.enclosureUrl {
            engine.seek(toMilliseconds: positionMilliseconds)
            session.activateForPlayback()
            playbackError = nil
            engine.playImmediately()
            return
        }
        var updated = episode
        updated.playedDuration = positionMilliseconds
        currentEpisode = updated
        await setByEpisodeInner(updated)
        session.activateForPlayback()
        playbackError = nil
        engine.playImmediately()
    }

    /// ±10 s (lock screen, K1) and −10 s/+30 s (full-screen controls):
    /// clamped to [0, duration] — a nil duration no longer crashes (K4),
    /// it simply skips the upper clamp.
    public func seekByRelative(_ deltaMilliseconds: Int64) {
        var target = engine.positionMilliseconds + deltaMilliseconds
        if target < 0 { target = 0 }
        if let duration = engine.durationMilliseconds, target > duration {
            target = duration
        }
        engine.seek(toMilliseconds: target)
    }

    /// K6: manual retry after a failure — reload at the last known position.
    public func retry() async {
        guard let episode = currentEpisode else { return }
        let position = max(engine.positionMilliseconds, episode.playedDuration ?? 0)
        var updated = episode
        updated.playedDuration = position
        await setByEpisode(updated)
        session.activateForPlayback()
        playbackError = nil
        engine.playImmediately()
    }

    /// K24: entering the background saves once more.
    public func applicationDidEnterBackground() {
        saveProgressNow()
    }

    /// Refresh the in-memory queue after external mutations (M3 reorder /
    /// add / remove).
    public func reloadQueue() async {
        guard let playlistId = currentPlaylistId else { return }
        queue = (try? await store.episodes(playlistId: playlistId)) ?? []
    }

    public func isPlayingEpisode(_ enclosureURL: String) -> Bool {
        guard isPlaying else { return false }
        return currentEpisode?.enclosureUrl == enclosureURL
    }

    public func setSpeed(_ value: Float) {
        speed = value
        settings.speed = Double(value)
        engine.setDesiredSpeed(value)
        nowPlaying.updateSpeed(value)
        trackStoreWrite { try await self.store.persistSpeed(Double(value)) }
    }

    public func setContinuousPlaying(_ value: Bool) {
        settings.continuousPlaying = value
        trackStoreWrite { try await self.store.persistContinuousPlaying(value) }
    }

    // MARK: - Engine events

    private func handle(_ event: PlaybackEngineEvent) {
        switch event {
        case let .playingChanged(playing):
            isPlaying = playing
            nowPlaying.updatePlaybackState(
                positionMilliseconds: engine.positionMilliseconds,
                speed: speed,
                playing: playing
            )
        case let .loadingChanged(loading):
            isLoading = loading
        case let .positionTick(position, buffered, duration):
            handleTick(position: position, buffered: buffered, duration: duration)
        case .completed:
            Task { await handleCompleted() }
        case let .failed(message):
            playbackError = message
        }
    }

    /// K11 four-condition gate + K24 2 s persistence in the same place
    /// (08 §4.3).
    private func handleTick(position: Int64, buffered: Int64, duration: Int64?) {
        nowPlaying.updatePlaybackState(
            positionMilliseconds: position,
            speed: speed,
            playing: isPlaying
        )

        // K11: while paused/loading/at zero the progress UI must not move.
        if isPlaying && !isLoading && position != 0 && buffered != 0 {
            positionData = PositionData(
                positionMilliseconds: position,
                bufferedMilliseconds: buffered,
                durationMilliseconds: duration ?? 0
            )
        }

        guard isPlaying, currentEpisode?.enclosureUrl != nil else { return }
        let now = nowMilliseconds()
        if now - lastProgressPersistAt >= 2_000 {
            persistProgress(positionMilliseconds: position, at: now)
        }
    }

    /// Completed → removeTop → next (K3).
    private func handleCompleted() async {
        // Dart: no current playlist → nothing to do (the player stays in
        // its completed state).
        guard currentPlaylistId != nil else { return }
        guard let url = queue.first?.enclosureUrl else { return }

        queue.removeFirst()
        try? await store.removeEpisodeCascade(enclosureURL: url)
        await cache.remove(url: url)
        cacheStates[url] = nil
        onEpisodeRemoved?(url)

        if queue.isEmpty {
            pause()
            await clearPlaybackState()
            return
        }

        await playByEpisode(queue[0])
        if !settings.continuousPlaying {
            pauseEngineOnly()
            initProgress()
        }
    }

    private func clearPlaybackState() async {
        currentEpisode = nil
        positionData = .zero
        currentPlaylistId = nil
        try? await store.clearPointer()
        session.deactivate()
    }

    // MARK: - Progress persistence (K24)

    private func saveProgressNow() {
        guard engine.hasItem, currentEpisode?.enclosureUrl != nil else { return }
        persistProgress(positionMilliseconds: engine.positionMilliseconds,
                        at: nowMilliseconds())
    }

    private func persistProgress(positionMilliseconds: Int64, at now: Int64) {
        guard let url = currentEpisode?.enclosureUrl else { return }
        lastProgressPersistAt = now
        if !queue.isEmpty {
            queue[0].playedDuration = positionMilliseconds
        }
        currentEpisode?.playedDuration = positionMilliseconds
        // The progress DISPLAY only ever moves through the K11-filtered
        // tick path (handleTick) or initProgress — persistence never
        // touches it (paused/zero ticks must not leak through).
        trackStoreWrite { try await self.store.updatePlayedDuration(positionMilliseconds, enclosureURL: url) }
    }

    private func initProgress() {
        guard let episode = currentEpisode else {
            positionData = .zero
            return
        }
        positionData = PositionData(
            positionMilliseconds: episode.playedDuration ?? 0,
            bufferedMilliseconds: 0,
            durationMilliseconds: episode.duration ?? 0
        )
    }

    /// The task inherits the main actor (created here), so the @MainActor
    /// store protocol stays on its actor.
    private func trackStoreWrite(_ operation: @escaping () async throws -> Void) {
        storeWrites.append(Task {
            try? await operation()
        })
    }
}

// MARK: - Store abstraction (real repositories for production, fakes in tests)

/// The DB surface the service needs, as one protocol so the §5.1 suite can
/// run against real temp databases (SQL truth) while call order stays
/// observable.
@MainActor
public protocol PlaybackStore: AnyObject {
    func episodes(playlistId: Int64) async throws -> [PlaylistEpisodeRow]
    /// One transaction: playlistEpisode + subtitle + translation rows
    /// (the cache FILE deletion happens in the cache store, outside).
    func removeEpisodeCascade(enclosureURL: String) async throws
    func updatePlayedDuration(_ milliseconds: Int64, enclosureURL: String) async throws
    func savePointer(playlistId: Int64?) async throws
    func clearPointer() async throws
    func insertHistory(episode: PlaylistEpisodeRow) async throws
    func loadSettings() async throws -> AppSettings
    func persistSpeed(_ value: Double) async throws
    func persistContinuousPlaying(_ value: Bool) async throws
}

/// Production store over the AnycastKit repositories (all SQL hops off the
/// main actor).
@MainActor
public final class DatabasePlaybackStore: PlaybackStore {
    private let database: AppDatabase

    public init(database: AppDatabase) {
        self.database = database
    }

    public func episodes(playlistId: Int64) async throws -> [PlaylistEpisodeRow] {
        try await database.playlistRepository().listEpisodes(playlistId: playlistId)
    }

    public func removeEpisodeCascade(enclosureURL: String) async throws {
        try await database.playlistRepository().removeEpisodeCascade(byEnclosureURL: enclosureURL)
    }

    public func updatePlayedDuration(_ milliseconds: Int64, enclosureURL: String) async throws {
        try await database.playlistRepository().updatePlayedDuration(milliseconds, byEnclosureURL: enclosureURL)
    }

    public func savePointer(playlistId: Int64?) async throws {
        try await database.playerRepository().updatePointer(currentPlaylistId: playlistId)
    }

    public func clearPointer() async throws {
        try await database.playerRepository().clear()
    }

    public func insertHistory(episode: PlaylistEpisodeRow) async throws {
        let row = HistoryEpisodeRow(
            id: episode.id,
            title: episode.title,
            description: episode.description,
            duration: episode.duration,
            enclosureUrl: episode.enclosureUrl,
            pubDate: episode.pubDate,
            imageUrl: episode.imageUrl,
            channelTitle: episode.channelTitle,
            rssFeedUrl: episode.rssFeedUrl
        )
        try await database.historyRepository().insert(row)
    }

    public func loadSettings() async throws -> AppSettings {
        try await database.settingsRepository().load()
    }

    public func persistSpeed(_ value: Double) async throws {
        try await database.settingsRepository().setSpeed(value)
    }

    public func persistContinuousPlaying(_ value: Bool) async throws {
        try await database.settingsRepository().setContinuousPlaying(value)
    }
}

// MARK: - Cache abstraction

public protocol EpisodeCaching: Actor {
    func cachedFile(for url: String) async -> URL?
    @discardableResult
    func startDownload(url: String, onProgress: @escaping @Sendable (Double?) -> Void) async -> Task<URL, Error>
    func remove(url: String) async
}

extension EpisodeCacheStore: EpisodeCaching {}
