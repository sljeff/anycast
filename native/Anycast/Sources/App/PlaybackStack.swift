import AnycastKit
import Foundation

/// The M2 audio stack, assembled once the startup DAG has restored local
/// state (database + settings + pointer). Everything timer-shaped — the
/// 15 s/10 s pollers, the 1 s sleep countdown — comes into existence HERE,
/// after settings have loaded (docs/migration/06 §4 rule 4).
///
/// The session category itself is set far earlier (AppEnvironment init):
/// `setCategory(.playback)` never grabs audio focus, and the category must
/// exist before any playback could start (K18).
@MainActor
final class PlaybackStack {

    let cacheStore: EpisodeCacheStore
    let playback: PlaybackService
    let sleepTimer: SleepTimerController
    let subtitles: SubtitlePollController
    let translations: TranslationPollController

    /// Mutable settings view for the pollers and the cache-capacity
    /// provider (language changes land in M3 and propagate through here).
    let settingsBox: SettingsBox

    static func build(database: AppDatabase,
                      settings: AppSettings,
                      pointer: PlayerPointer?,
                      paths: ApplicationPaths,
                      session: AudioSessionController,
                      auth: AuthController,
                      sentry: SentryService) async -> PlaybackStack {
        let box = SettingsBox(settings)

        // Audio cache index: writable (downloads must be indexed for a
        // rolled-back Flutter build to recognize them, 05 §2.4). A failure
        // to open degrades to a no-op index — playback still streams.
        let meta = (try? await CacheMetaDatabase.openWritable(at: paths.episodeCacheMetaDatabaseURL))
            ?? CacheMetaDatabase(queue: nil)
        // Cover index: tolerant read for the K19 artwork fallback.
        let coverMeta = await CacheMetaDatabase.open(at: paths.coverCacheMetaDatabaseURL)

        let cacheStore = EpisodeCacheStore(
            meta: meta,
            directory: paths.episodeCacheDirectory,
            maxObjects: { [weak box] in
                Int(box?.current.maxCacheCount ?? 10)
            }
        )

        // Static, thread-safe token accessor — the closure captures nothing.
        let api = APIClient(client: HTTPClient(), tokenProvider: {
            try await AuthController.currentToken()
        })

        let subtitles = SubtitlePollController(
            api: api,
            subtitles: database.subtitleRepository()
        )
        let translations = TranslationPollController(
            api: api,
            translations: database.translationRepository(),
            subtitles: database.subtitleRepository(),
            targetLanguage: { [weak box] in box?.current.targetLanguage ?? "" },
            subtitleStatuses: { [weak subtitles] in subtitles?.statuses ?? [:] }
        )

        let nowPlaying = NowPlayingController(
            artworkProvider: NowPlayingArtworkProvider(
                coverMeta: coverMeta,
                coverDirectory: paths.coverCacheDirectory
            )
        )
        let playback = PlaybackService(
            engine: AVPlayerEngine(),
            cache: cacheStore,
            store: DatabasePlaybackStore(database: database),
            settings: settings,
            session: session,
            nowPlaying: nowPlaying
        )

        let stack = PlaybackStack(
            cacheStore: cacheStore,
            playback: playback,
            sleepTimer: SleepTimerController(isPlaying: { [weak playback] in
                playback?.isPlaying ?? false
            }),
            subtitles: subtitles,
            translations: translations,
            settingsBox: box,
            session: session,
            sentry: sentry
        )

        await playback.restore(pointer: pointer, settings: settings)
        await subtitles.start()
        translations.start()
        return stack
    }

    private init(cacheStore: EpisodeCacheStore,
                 playback: PlaybackService,
                 sleepTimer: SleepTimerController,
                 subtitles: SubtitlePollController,
                 translations: TranslationPollController,
                 settingsBox: SettingsBox,
                 session: AudioSessionController,
                 sentry: SentryService) {
        self.cacheStore = cacheStore
        self.playback = playback
        self.sleepTimer = sleepTimer
        self.subtitles = subtitles
        self.translations = translations
        self.settingsBox = settingsBox

        // K1: the lock-screen command set, wired to the queue semantics.
        playback.nowPlaying.attachRemoteCommands(NowPlayingController.RemoteCommands(
            skipBackward: { [weak playback] in playback?.seekByRelative(-10_000) },
            skipForward: { [weak playback] in playback?.seekByRelative(10_000) },
            togglePlayPause: { [weak playback] in Task { await playback?.togglePlay() } },
            changePlaybackPosition: { [weak playback] seconds in
                Task { await playback?.seek(Int64(seconds * 1000)) }
            }
        ))

        // K18: interruptions pause; unplugged routes pause; activation
        // failures are visible in Sentry (playback may be silent).
        session.onShouldPause = { [weak playback] in playback?.pause() }
        session.onActivateFailure = { sentry.captureMessage($0, context: "audio.session") }

        // K38: the countdown expiring pauses.
        sleepTimer.onExpired = { [weak playback] in playback?.pause() }

        // K3 cascade: a removed queue entry drops out of both pollers.
        playback.onEpisodeRemoved = { [weak subtitles, weak translations] url in
            Task { await subtitles?.remove(url: url) }
            Task { await translations?.remove(url: url) }
        }

        // K27: a background-poll 401 still reaches the login flow. Until
        // the M3 login sheet exists, it reports to Sentry.
        subtitles.onLoginRequired = {
            sentry.captureMessage("401 during subtitle polling", context: "subtitle.poll")
        }
    }

    /// 08 §4.1: background suspends the pollers; foreground resumes them
    /// with one immediate round. The K24 progress save rides along.
    func setSceneActive(_ active: Bool) {
        Task {
            await subtitles.setActive(active)
            await translations.setActive(active)
        }
        if !active {
            playback.applicationDidEnterBackground()
        }
    }

    #if DEBUG
    /// M2 simulator smoke hook (`-m2-smoke-play <audio-file-or-url>`): with
    /// no UI until M3, this drives the real stack end-to-end — engine,
    /// session activation, Now Playing, progress persistence. Debug builds
    /// only; removed when the M3 player page lands.
    func runSmokeTestIfRequested(arguments: [String]) {
        guard let index = arguments.firstIndex(of: "-m2-smoke-play"),
              arguments.count > index + 1,
              let queueHead = playback.queue.first
        else { return }
        let target = arguments[index + 1]
        print("[m2-smoke] playing \(target) for queue head \(queueHead.enclosureUrl ?? "?")")
        Task {
            await playback.playByEpisode(queueHead)
            try? await Task.sleep(for: .seconds(5))
            print("[m2-smoke] isPlaying=\(playback.isPlaying) position=\(playback.positionData.positionMilliseconds)ms error=\(playback.playbackError ?? "none")")
            playback.pause()
            await playback.flushStoreWrites()
            print("[m2-smoke] paused; playedDuration row saved")
        }
    }
    #endif
}

/// Small shared box so settings changes (M3) propagate to the pollers and
/// the cache-capacity provider without rebuilding the stack. Lock-guarded:
/// the cache-capacity provider reads it from a nonisolated context.
nonisolated final class SettingsBox: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: AppSettings

    var current: AppSettings {
        lock.lock(); defer { lock.unlock() }
        return stored
    }

    init(_ settings: AppSettings) {
        self.stored = settings
    }

    func update(_ settings: AppSettings) {
        lock.lock(); stored = settings; lock.unlock()
    }
}
