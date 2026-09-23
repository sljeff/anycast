import Foundation
import AnycastKit

/// The startup DAG (docs/migration/06 §4, 08 §2.3 / §12.1-5):
///
///     Sentry → Firebase/RC configure → DB open/migrate/K25 fallback
///     → settings loaded → player pointer restored → [timers] → ready
///
/// Two hard rules encoded here:
/// 1. **No timer is ever scheduled before settings have loaded** — this is
///    what kills the 180/300 auto-refresh race at the root.
/// 2. RC `logIn(uid)` runs only after `Purchases.configure` has completed,
///    with retry — never replicating the old build's swallowed-error path
///    that left a session silently anonymous.
///
/// The first frame does not wait for this chain; it is a background task and
/// the UI observes `phase`.
@MainActor
final class StartupSequence {

    enum Phase: Equatable {
        case idle
        case running
        case ready
        case degraded(String)
    }

    private(set) var phase: Phase = .idle

    // State produced by the DAG; M2/M3 controllers consume these.
    private(set) var database: AppDatabase?
    private(set) var settings: AppSettings?
    private(set) var playerPointer: PlayerPointer?

    /// Fired once local state is restored (database + settings + pointer).
    /// The composition root installs the playback stack here — timers of
    /// any kind exist only after this point (the DAG's hard rule).
    var onReady: (@MainActor (_ database: AppDatabase, _ settings: AppSettings, _ pointer: PlayerPointer?) -> Void)?

    private let sentry: SentryService
    private let auth: AuthController
    private let purchases: RevenueCatController
    private let paths: ApplicationPaths

    init(sentry: SentryService, auth: AuthController, purchases: RevenueCatController, paths: ApplicationPaths) {
        self.sentry = sentry
        self.auth = auth
        self.purchases = purchases
        self.paths = paths
    }

    func start() {
        guard phase == .idle else { return }
        phase = .running
        Task { await run() }
    }

    private func run() async {
        // 1. Sentry first: everything below is already monitored.
        sentry.start()

        // 2. Firebase + RevenueCat configuration.
        auth.configureFirebase()
        await purchases.configureIfPossible()
        // 2b. The auth-state observer is the Flutter line's `authStateChanges`
        // binding path: a uid restored late (or a post-startup sign-in) must
        // re-bind RevenueCat, not leave the session silently anonymous. The
        // eager bind in step 6 covers the already-restored case; `bind` is
        // idempotent for a repeated uid.
        auth.setUIDObserver { [weak self] _ in
            guard let self else { return }
            Task { await self.bindRevenueCatWithRetry() }
        }

        // 3. Main database: open, validate schema, run K25 quarantine if the
        //    file is deterministically corrupt, migrate from v4+, then the
        //    K31 idempotent default rows. All SQLite work runs off the main
        //    actor (08 §1.1).
        do {
            // K25: the quarantine report is part of the decision (05 §11) —
            // Sentry must hear about every deterministically corrupt main
            // database, even though openAt already rebuilt a fresh one.
            let database = try await AppDatabase.openAt(paths.mainDatabaseURL) { originalURL, reason in
                let sentry = self.sentry
                Task { @MainActor in
                    sentry.captureMessage(
                        "db quarantined: \(reason) (\(originalURL.lastPathComponent))",
                        context: "db.quarantine"
                    )
                }
            }
            self.database = database

            // 4. Settings load completes before anything timer-shaped exists.
            let settings = try await database.settingsRepository().load()
            self.settings = settings

            // 5. Restore the player pointer (K31: missing row is not an
            //    error — it means "no playback state").
            let pointer = try await database.playerRepository().loadPointer()
            self.playerPointer = pointer

            phase = .ready

            // 6. Local state restored: install the playback stack and only
            //    now schedule the pollers (15 s/10 s) — nothing
            //    timer-shaped existed before settings loaded.
            onReady?(database, settings, pointer)
        } catch {
            // K25 already handled corrupt files inside openAt; landing here
            // means even a rebuilt database will not open — degrade visibly
            // instead of crash-looping.
            sentry.capture(error, context: "startup.database")
            phase = .degraded("database: \(error.localizedDescription)")
        }

        // 6. RC binding: after configure, retried, reported. Runs after local
        //    state restore so entitlements never gate data access — and
        //    deliberately outside the do/catch: a degraded database must not
        //    also drop the user's entitlement identity.
        await bindRevenueCatWithRetry()
    }

    private func bindRevenueCatWithRetry() async {
        guard let uid = auth.currentUID else { return }
        for attempt in 1...3 {
            do {
                try await purchases.bind(uid: uid)
                return
            } catch {
                sentry.capture(error, context: "startup.revenuecat.logIn(\(attempt))")
                try? await Task.sleep(for: .milliseconds(500 * attempt))
            }
        }
    }
}

/// Sandbox layout, resolved once at launch (docs/migration/01 §4.4).
struct ApplicationPaths {
    let documents: URL
    let applicationSupport: URL
    let temporary: URL
    let caches: URL

    var mainDatabaseURL: URL { AppConfiguration.mainDatabaseURL(documents: documents) }
    var episodeCacheMetaDatabaseURL: URL { AppConfiguration.episodeCacheMetaDatabaseURL(appSupport: applicationSupport) }
    /// Real-device layout (db_device evidence, 01 §4.1 2026-09-23
    /// correction): audio files live under Library/Caches, not tmp/.
    var episodeCacheDirectory: URL { caches.appendingPathComponent("anycast_episode", isDirectory: true) }
    var coverCacheMetaDatabaseURL: URL { AppConfiguration.coverCacheMetaDatabaseURL(appSupport: applicationSupport) }
    var coverCacheDirectory: URL { caches.appendingPathComponent("libCachedImageData", isDirectory: true) }

    static func standard() -> ApplicationPaths {
        let fileManager = FileManager.default
        let base = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return ApplicationPaths(
            documents: base,
            applicationSupport: fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0],
            temporary: URL(fileURLWithPath: NSTemporaryDirectory()),
            caches: fileManager.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        )
    }
}
