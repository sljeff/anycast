import Foundation
import Observation

/// Timer abstraction whose ONLY job is making the polling CADENCE
/// assertable: the interval handed to the factory is red-line material
/// (15 s transcription / 10 s translation — never faster, 02 §6 line 5,
/// 05 §4.1). Production uses a main-runloop timer; tests record the
/// interval and fire rounds manually.
public protocol PollTimer: AnyObject, Sendable {
    func cancel()
}

public protocol PollTimerFactory: Sendable {
    func periodic(milliseconds: Int64, fire: @escaping @Sendable () async -> Void) -> any PollTimer
}

/// Main-runloop `Timer` whose tick hops into an async round on the main
/// actor (the Dart `Timer.periodic` ran on the main isolate).
public struct MainPollTimerFactory: PollTimerFactory {

    public init() {}

    public func periodic(milliseconds: Int64, fire: @escaping @Sendable () async -> Void) -> any PollTimer {
        MainPollTimer(milliseconds: milliseconds, fire: fire)
    }

    final class MainPollTimer: PollTimer, @unchecked Sendable {
        private let lock = NSLock()
        private var timer: Timer?

        init(milliseconds: Int64, fire: @escaping @Sendable () async -> Void) {
            let timer = Timer.scheduledTimer(
                withTimeInterval: Double(milliseconds) / 1000,
                repeats: true
            ) { _ in
                Task { await fire() }
            }
            lock.lock()
            self.timer = timer
            lock.unlock()
        }

        func cancel() {
            lock.lock()
            timer?.invalidate()
            timer = nil
            lock.unlock()
        }
    }
}

// MARK: - Transcription polling (states/subtitle.dart)

/// The transcription state machine: user `add()` triggers + the background
/// poller converge on one idempotent endpoint. Port decisions:
/// - cadence exactly 15 s (red line; "no processing → no request" is the
///   built-in idle path);
/// - **K27**: background errors are SILENT — transport failures and 5xx/429
///   keep the `processing` state and the poller running (the server is
///   idempotent by enclosure_url); only 401/login surfaces, to any page;
///   user-triggered `add()` still returns its error signal for a dialog;
/// - a server `failed` answer deletes the local row and frees the UI back
///   to the Generate button (old behavior, replicated);
/// - iteration runs over a snapshot key list — the old concurrent
///   modification crash (08 §12.1-6) is not ported.
@MainActor
@Observable
public final class SubtitlePollController {

    nonisolated public static let pollIntervalMilliseconds: Int64 = 15_000

    /// url → status ("processing" / "succeeded" / server strings pass
    /// through), the old `subtitleUrls` map.
    public private(set) var statuses: [String: String] = [:]
    /// K27: 401 during background polling still routes to the login sheet.
    public var onLoginRequired: (() -> Void)?

    private let api: APIClient
    private let subtitles: SubtitleRepository
    private let timerFactory: any PollTimerFactory
    private var timer: (any PollTimer)?
    private var isRefreshing = false

    public init(api: APIClient, subtitles: SubtitleRepository,
                timerFactory: any PollTimerFactory = MainPollTimerFactory()) {
        self.api = api
        self.subtitles = subtitles
        self.timerFactory = timerFactory
    }

    /// Startup (after settings load — the DAG rules): seed from stored rows
    /// (only `succeeded` rows exist on disk, 01 §1.1) and schedule the 15 s
    /// poller.
    public func start() async {
        statuses = (try? await subtitles.listStatuses()) ?? [:]
        guard timer == nil else { return }
        timer = timerFactory.periodic(milliseconds: Self.pollIntervalMilliseconds) { [weak self] in
            await self?.refreshProcessing()
        }
    }

    /// 08 §4.1: background suspends the poller; returning to the foreground
    /// runs one immediate round (covering what was missed) and resumes.
    public func setActive(_ active: Bool) async {
        if active {
            await start()
            await refreshProcessing()
        } else {
            timer?.cancel()
            timer = nil
        }
    }

    /// One polling round: every `processing` URL, sequentially — exactly the
    /// Dart `refreshProcessing` minus the CME.
    public func refreshProcessing() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        for url in statuses.keys.sorted() where statuses[url] == "processing" {
            await apply(url: url, result: try? await api.getSubtitles(enclosureURL: url))
        }
    }

    /// User-triggered transcription ("Generate transcript"). Returns the
    /// error signal for the UI to present (K27: user-initiated failures
    /// stay visible; nil = no dialog).
    @discardableResult
    public func add(url: String) async -> APIClient.ErrorSignal? {
        statuses[url] = "processing"
        do {
            let result = try await api.getSubtitles(enclosureURL: url)
            return await apply(url: url, result: result, userTriggered: true)
        } catch {
            return .errorBody(status: 0, body: error.localizedDescription)
        }
    }

    /// The Dart `_applyResult` (+ error-signal routing).
    private func apply(url: String, result: APIClient.SubtitleResult?,
                       userTriggered: Bool = false) async -> APIClient.ErrorSignal? {
        guard let result else {
            // Transport-level throw during a background round: silent, keep
            // polling (K27). (add() handles its own catch.)
            return nil
        }

        if let signal = result.error {
            if case .loginRequired = signal {
                onLoginRequired?()
                return nil
            }
            // K27: server text on a user trigger; silent in the background
            // round (processing continues).
            return userTriggered ? signal : nil
        }

        switch result.status {
        case "succeeded":
            statuses[url] = "succeeded"
            let payload = SubtitleSegment.encode(result.segments ?? [])
            try? await subtitles.insert(SubtitleRow(
                enclosureUrl: url,
                status: "succeeded",
                subtitle: payload,
                language: result.language,
                summary: nil
            ))
        case "failed":
            statuses[url] = nil
            try? await subtitles.delete(byEnclosureURL: url)
        default:
            break // still processing
        }
        return nil
    }

    /// K3 cascade: removing a queue entry drops its subtitle state too.
    public func remove(url: String) async {
        statuses[url] = nil
        try? await subtitles.delete(byEnclosureURL: url)
    }
}

// MARK: - Translation polling (states/translation.dart)

/// The 10 s translation loop over succeeded subtitles:
/// - skip when no target language; skip same-language subtitles (detected
///   == target — re-checked each tick like the Dart loop, no network);
/// - cached translation rows short-circuit to `succeeded`;
/// - **K9**: failures (HTTP error, thrown transport error, or
///   `translation: null`) count per URL; after 5 consecutive failures the
///   URL moves to `failed` and leaves the loop — the old app re-requested
///   forever with a permanent "Translating subtitles..." bar;
/// - in-flight dedup so overlapping ticks never double-request.
@MainActor
@Observable
public final class TranslationPollController {

    nonisolated public static let pollIntervalMilliseconds: Int64 = 10_000
    /// K9: consecutive-failure cap before an URL leaves the loop.
    nonisolated public static let failureCap = 5

    public private(set) var statuses: [String: String] = [:]

    private let api: APIClient
    private let translations: TranslationRepository
    private let subtitles: SubtitleRepository
    private let targetLanguage: @MainActor () -> String
    private let subtitleStatuses: @MainActor () -> [String: String]
    private let timerFactory: any PollTimerFactory
    private var timer: (any PollTimer)?
    private var inFlight: Set<String> = []
    private var failureCounts: [String: Int] = [:]

    public init(api: APIClient,
                translations: TranslationRepository,
                subtitles: SubtitleRepository,
                targetLanguage: @escaping @MainActor () -> String,
                subtitleStatuses: @escaping @MainActor () -> [String: String],
                timerFactory: any PollTimerFactory = MainPollTimerFactory()) {
        self.api = api
        self.translations = translations
        self.subtitles = subtitles
        self.targetLanguage = targetLanguage
        self.subtitleStatuses = subtitleStatuses
        self.timerFactory = timerFactory
    }

    public func start() {
        guard timer == nil else { return }
        timer = timerFactory.periodic(milliseconds: Self.pollIntervalMilliseconds) { [weak self] in
            await self?.refresh()
        }
    }

    public func setActive(_ active: Bool) async {
        if active {
            start()
            await refresh()
        } else {
            timer?.cancel()
            timer = nil
        }
    }

    /// One round: the Dart `refreshSucceededSubtitles` (snapshot iteration).
    public func refresh() async {
        guard !targetLanguage().isEmpty else { return }
        let subtitleStatus = subtitleStatuses()
        for url in subtitleStatus.keys.sorted()
        where subtitleStatus[url] == "succeeded"
            && statuses[url] != "succeeded"
            && statuses[url] != "failed" {
            await loadTranslation(url)
        }
    }

    public func loadTranslation(_ url: String) async {
        guard inFlight.insert(url).inserted else { return }
        defer { inFlight.remove(url) }

        let language = targetLanguage()
        guard !language.isEmpty else { return }

        // Same-language (or unknown-language) subtitles are skipped, but
        // stay eligible — the Dart loop re-checked them every tick.
        guard let detected = (try? await subtitles.get(byEnclosureURL: url))??.language,
              detected != language
        else { return }

        if (try? await translations.get(byEnclosureURL: url, language: language)) != nil {
            statuses[url] = "succeeded"
            failureCounts[url] = 0
            return
        }

        statuses[url] = "processing"
        do {
            let result = try await api.getTranslation(enclosureURL: url, language: language)
            guard case .segments(let segments) = result else {
                registerFailure(url)
                return
            }
            try? await translations.insert(TranslationRow(
                enclosureUrl: url,
                status: "succeeded",
                translation: SubtitleSegment.encode(segments),
                language: language
            ))
            statuses[url] = "succeeded"
            failureCounts[url] = 0
        } catch {
            registerFailure(url)
        }
    }

    private func registerFailure(_ url: String) {
        let count = (failureCounts[url] ?? 0) + 1
        failureCounts[url] = count
        if count >= Self.failureCap {
            statuses[url] = "failed"
        }
    }

    /// Language switch clears the in-memory map (the Dart
    /// `setTargetLanguage` reset).
    public func resetForLanguageChange() {
        statuses.removeAll()
        failureCounts.removeAll()
    }

    /// K3 cascade.
    public func remove(url: String) async {
        statuses[url] = nil
        failureCounts[url] = nil
        try? await translations.delete(byEnclosureURL: url)
    }
}
