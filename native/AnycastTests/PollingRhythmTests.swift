import Foundation
import Testing
@testable import AnycastKit

/// The polling cadence red line (02 §6 line 5, 05 §4.1): transcription 15 s
/// ±1 s, translation 10 s ±1 s — NEVER faster — plus the K27 background
/// silence / K9 translation retry cap ported by `SubtitlePollController` /
/// `TranslationPollController`.
@MainActor
@Suite(.serialized)
struct PollingRhythmTests {

    // MARK: - Manual timer

    final class ManualPollTimer: PollTimer, @unchecked Sendable {
        let milliseconds: Int64
        private let fire: @Sendable () async -> Void
        private let lock = NSLock()
        private var cancelled = false

        init(milliseconds: Int64, fire: @escaping @Sendable () async -> Void) {
            self.milliseconds = milliseconds
            self.fire = fire
        }

        private func isCancelled_() -> Bool {
            lock.lock(); defer { lock.unlock() }
            return cancelled
        }

        func tick() async {
            guard !isCancelled_() else { return }
            await fire()
        }

        func cancel() {
            lock.lock()
            cancelled = true
            lock.unlock()
        }
    }

    final class ManualPollTimerFactory: PollTimerFactory, @unchecked Sendable {
        private let lock = NSLock()
        private var _timers: [ManualPollTimer] = []

        var intervals: [Int64] {
            lock.lock(); defer { lock.unlock() }
            return _timers.map(\.milliseconds)
        }

        var timers: [ManualPollTimer] {
            lock.lock(); defer { lock.unlock() }
            return _timers
        }

        func periodic(milliseconds: Int64, fire: @escaping @Sendable () async -> Void) -> any PollTimer {
            let timer = ManualPollTimer(milliseconds: milliseconds, fire: fire)
            lock.lock()
            _timers.append(timer)
            lock.unlock()
            return timer
        }
    }

    // MARK: - Helpers

    private func makeDatabase() async throws -> (AppDatabase, URL) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("poll-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let database = try await AppDatabase.openAt(directory.appendingPathComponent("anycast.db"))
        return (database, directory)
    }

    private func makeAPI() -> APIClient {
        APIClient(
            client: HTTPClient(protocolClasses: [L2ContractTests.ReplayProtocol.self]),
            tokenProvider: { "test-token" }
        )
    }

    // MARK: - Subtitle poller

    @Test("subtitle poller: exactly 15s cadence; one round per tick; idle rounds emit nothing")
    func subtitleCadence() async throws {
        let (database, databaseDirectory) = try await makeDatabase()
        defer { SandboxCleanup.remove(databaseDirectory, closing: [database.queue]) }
        let factory = ManualPollTimerFactory()
        let controller = SubtitlePollController(
            api: makeAPI(),
            subtitles: database.subtitleRepository(),
            timerFactory: factory
        )

        L2ContractTests.ReplayProtocol.reset { _ in
            .response(status: 200, body: #"{"status": "processing"}"#)
        }
        await controller.start()

        // The red line is the interval handed to the timer factory.
        #expect(factory.intervals == [SubtitlePollController.pollIntervalMilliseconds])
        #expect(SubtitlePollController.pollIntervalMilliseconds == 15_000)

        // No processing entries → a full round emits zero requests.
        await factory.timers.first!.tick()
        #expect(L2ContractTests.ReplayProtocol.requests().isEmpty,
                "idle rounds must not hit the server")

        // One processing URL → one request per tick, no extras.
        await controller.add(url: "https://x.example/ep1.mp3")
        let firstCount = L2ContractTests.ReplayProtocol.requests().count
        await factory.timers.first!.tick()
        let secondCount = L2ContractTests.ReplayProtocol.requests().count
        #expect(secondCount == firstCount + 1,
                "exactly one request per round per processing URL — never faster than the cadence")
    }

    @Test("subtitle poller K27: background 5xx keeps processing silently; 401 routes to login")
    func subtitleBackgroundSilence() async throws {
        let (database, databaseDirectory) = try await makeDatabase()
        defer { SandboxCleanup.remove(databaseDirectory, closing: [database.queue]) }
        let factory = ManualPollTimerFactory()
        let controller = SubtitlePollController(
            api: makeAPI(),
            subtitles: database.subtitleRepository(),
            timerFactory: factory
        )
        let loginFired = L2ContractTests.Locked(false)
        controller.onLoginRequired = { loginFired.with { $0 = true } }

        await controller.add(url: "https://x.example/ep1.mp3") // → processing (in-memory)

        // Background round hits 500: silent, processing survives.
        L2ContractTests.ReplayProtocol.reset { _ in .response(status: 500, body: "boom") }
        await controller.refreshProcessing()
        #expect(controller.statuses["https://x.example/ep1.mp3"] == "processing",
                "K27: transient 5xx must not roll the UI back to Generate")

        // 401 → login signal, still processing.
        L2ContractTests.ReplayProtocol.reset { _ in .response(status: 401, body: "Unauthorized") }
        await controller.refreshProcessing()
        #expect(loginFired.with { $0 })
        #expect(controller.statuses["https://x.example/ep1.mp3"] == "processing")
    }

    @Test("subtitle add(): succeeded persists the row; failed deletes it; user-visible error signals surface")
    func subtitleAddBranches() async throws {
        let (database, databaseDirectory) = try await makeDatabase()
        defer { SandboxCleanup.remove(databaseDirectory, closing: [database.queue]) }
        let controller = SubtitlePollController(
            api: makeAPI(),
            subtitles: database.subtitleRepository(),
            timerFactory: ManualPollTimerFactory()
        )
        let url = "https://x.example/ep1.mp3"

        // succeeded → row lands with the JSON payload + language.
        L2ContractTests.ReplayProtocol.reset { _ in
            .response(status: 200, body: #"{"status":"succeeded","subtitle":{"detected_language":"en","segments":[{"start":0.0,"end":4.0,"text":"Hello"},{"start":4.2,"end":8.2,"text":"World"}]}}"#)
        }
        let ok = await controller.add(url: url)
        #expect(ok == nil)
        #expect(controller.statuses[url] == "succeeded")
        let stored = try await database.subtitleRepository().get(byEnclosureURL: url)
        #expect(stored?.status == "succeeded")
        #expect(stored?.language == "en")
        #expect((stored?.segments ?? []).count == 2)

        // failed → local record removed, UI frees back to Generate.
        L2ContractTests.ReplayProtocol.reset { _ in
            .response(status: 200, body: #"{"status":"failed"}"#)
        }
        await controller.add(url: url)
        #expect(controller.statuses[url] == nil)
        #expect(try await database.subtitleRepository().get(byEnclosureURL: url) == nil)

        // User-triggered 403 quota → the server's error text returns for
        // the dialog (K27: user-initiated failures stay visible).
        L2ContractTests.ReplayProtocol.reset { _ in
            .response(status: 403, body: #"{"error":"Monthly transcription quota exhausted","code":1}"#)
        }
        let quota = await controller.add(url: url)
        #expect(quota == .errorMessage("Monthly transcription quota exhausted"))
    }

    @Test("login-cancel rollback: processing entries clear, succeeded and other statuses survive")
    func subtitleLoginCancelRollbackRevertsProcessing() async throws {
        let (database, databaseDirectory) = try await makeDatabase()
        defer { SandboxCleanup.remove(databaseDirectory, closing: [database.queue]) }
        let controller = SubtitlePollController(
            api: makeAPI(),
            subtitles: database.subtitleRepository(),
            timerFactory: ManualPollTimerFactory()
        )
        let pending = "https://x.example/ep1.mp3"
        let done = "https://x.example/ep2.mp3"
        let passthrough = "https://x.example/ep3.mp3"

        // DB-seeded rows survive `start()` as-is: one succeeded row, one
        // row carrying an arbitrary pass-through status string.
        try await seedSubtitle(database: database, url: done, language: "en")
        try await database.subtitleRepository().insert(SubtitleRow(
            enclosureUrl: passthrough,
            status: "queued",
            subtitle: SubtitleSegment.encode([SubtitleSegment(start: 0, end: 4, text: "Hi")]),
            language: "en"
        ))
        await controller.start()
        #expect(controller.statuses[done] == "succeeded")
        #expect(controller.statuses[passthrough] == "queued")

        // An optimistic "processing" entry, seeded via a 200
        // still-processing replay (the 401 variant is exercised by the
        // after-loginRequired test below).
        L2ContractTests.ReplayProtocol.reset { _ in
            .response(status: 200, body: #"{"status": "processing"}"#)
        }
        await controller.add(url: pending)
        #expect(controller.statuses[pending] == "processing")

        controller.cancelLoginGatedProcessing()

        #expect(controller.statuses[pending] == nil,
                "processing entries roll back to an absent key (Generate button)")
        #expect(controller.statuses[done] == "succeeded",
                "succeeded entries are real server state and must survive")
        #expect(controller.statuses[passthrough] == "queued",
                "non-processing pass-through statuses must survive")
    }

    @Test("login-cancel rollback: a round after rollback emits no request for the reverted URL")
    func subtitleLoginCancelRollbackStopsPolling() async throws {
        let (database, databaseDirectory) = try await makeDatabase()
        defer { SandboxCleanup.remove(databaseDirectory, closing: [database.queue]) }
        let factory = ManualPollTimerFactory()
        let controller = SubtitlePollController(
            api: makeAPI(),
            subtitles: database.subtitleRepository(),
            timerFactory: factory
        )
        let url = "https://x.example/ep1.mp3"

        await controller.start()
        L2ContractTests.ReplayProtocol.reset { _ in
            .response(status: 200, body: #"{"status": "processing"}"#)
        }
        await controller.add(url: url)

        // Before the rollback every round re-requests the URL (the
        // re-401 → re-present loop of the bug).
        await controller.refreshProcessing()
        #expect(!L2ContractTests.ReplayProtocol.requests().isEmpty)

        controller.cancelLoginGatedProcessing()
        L2ContractTests.ReplayProtocol.reset { _ in
            .response(status: 401, body: "Unauthorized")
        }

        // After the rollback the URL left the poll set: a full tick emits
        // nothing, so the poller cannot re-401 and re-present login.
        await factory.timers.first!.tick()
        #expect(L2ContractTests.ReplayProtocol.requests().isEmpty,
                "a reverted URL must not be polled anymore")
    }

    @Test("login-cancel rollback: add() → loginRequired keeps processing until the rollback clears it")
    func subtitleLoginCancelAfterLoginRequired() async throws {
        let (database, databaseDirectory) = try await makeDatabase()
        defer { SandboxCleanup.remove(databaseDirectory, closing: [database.queue]) }
        let controller = SubtitlePollController(
            api: makeAPI(),
            subtitles: database.subtitleRepository(),
            timerFactory: ManualPollTimerFactory()
        )
        let url = "https://x.example/ep1.mp3"
        let loginFired = L2ContractTests.Locked(false)
        controller.onLoginRequired = { loginFired.with { $0 = true } }

        // Signed-out Generate: the request 401s, the login signal fires,
        // `add()` returns nil (the sheet is the handling — apply routes
        // loginRequired to onLoginRequired), and the optimistic
        // "processing" stays (the sheet is pending, the user may still
        // sign in).
        L2ContractTests.ReplayProtocol.reset { _ in
            .response(status: 401, body: "Unauthorized")
        }
        let signal = await controller.add(url: url)
        #expect(signal == nil)
        #expect(loginFired.with { $0 })
        #expect(controller.statuses[url] == "processing")

        // The user dismisses the sheet WITHOUT signing in: the rollback
        // frees the UI back to the Generate button.
        controller.cancelLoginGatedProcessing()
        #expect(controller.statuses[url] == nil)
        #expect(try await database.subtitleRepository().get(byEnclosureURL: url) == nil,
                "no row was persisted for the never-accepted request")
    }

    // MARK: - Translation poller

    /// Seed a succeeded subtitle row (language) as the translation input.
    private func seedSubtitle(database: AppDatabase, url: String, language: String) async throws {
        try await database.subtitleRepository().insert(SubtitleRow(
            enclosureUrl: url,
            status: "succeeded",
            subtitle: SubtitleSegment.encode([SubtitleSegment(start: 0, end: 4, text: "Hi")]),
            language: language
        ))
    }

    @Test("translation poller: exactly 10s cadence; requires a target language and a succeeded subtitle")
    func translationCadence() async throws {
        let (database, databaseDirectory) = try await makeDatabase()
        defer { SandboxCleanup.remove(databaseDirectory, closing: [database.queue]) }
        let factory = ManualPollTimerFactory()
        let url = "https://x.example/ep1.mp3"
        try await seedSubtitle(database: database, url: url, language: "en")

        let subtitleStatuses: @MainActor () -> [String: String] = { [url: "succeeded"] }
        var language = "zh"
        let controller = TranslationPollController(
            api: makeAPI(),
            translations: database.translationRepository(),
            subtitles: database.subtitleRepository(),
            targetLanguage: { language },
            subtitleStatuses: subtitleStatuses,
            timerFactory: factory
        )

        L2ContractTests.ReplayProtocol.reset { _ in
            .response(status: 200, body: #"{"translation":[{"start":0.0,"end":4.0,"text":"你好"}]}"#)
        }

        // No target language → a round emits nothing (language "" = off).
        language = ""
        controller.start()
        #expect(factory.intervals == [TranslationPollController.pollIntervalMilliseconds])
        #expect(TranslationPollController.pollIntervalMilliseconds == 10_000)
        await factory.timers.first!.tick()
        #expect(L2ContractTests.ReplayProtocol.requests().isEmpty)

        // Language set → one request per round.
        L2ContractTests.ReplayProtocol.reset { _ in
            .response(status: 200, body: #"{"translation":null}"#)
        }
        language = "zh"
        await factory.timers.first!.tick()
        let afterFirst = L2ContractTests.ReplayProtocol.requests().count
        #expect(afterFirst == 1)
        await factory.timers.first!.tick()
        #expect(L2ContractTests.ReplayProtocol.requests().count == afterFirst + 1)
    }

    @Test("translation: detected == target skips the request; cached row short-circuits")
    func translationSkips() async throws {
        let (database, databaseDirectory) = try await makeDatabase()
        defer { SandboxCleanup.remove(databaseDirectory, closing: [database.queue]) }
        let url = "https://x.example/ep1.mp3"

        // Same language → no request, ever.
        try await seedSubtitle(database: database, url: url, language: "zh")
        let controller = TranslationPollController(
            api: makeAPI(),
            translations: database.translationRepository(),
            subtitles: database.subtitleRepository(),
            targetLanguage: { "zh" },
            subtitleStatuses: { [url: "succeeded"] },
            timerFactory: ManualPollTimerFactory()
        )
        L2ContractTests.ReplayProtocol.reset { _ in .response(status: 200, body: "{}") }
        await controller.refresh()
        #expect(L2ContractTests.ReplayProtocol.requests().isEmpty,
                "same-language subtitles are skipped without a request")

        // Cached translation → succeeded without a request.
        try await database.translationRepository().insert(TranslationRow(
            enclosureUrl: url, status: "succeeded",
            translation: SubtitleSegment.encode([SubtitleSegment(start: 0, end: 4, text: "你好")]),
            language: "de"
        ))
        let deController = TranslationPollController(
            api: makeAPI(),
            translations: database.translationRepository(),
            subtitles: database.subtitleRepository(),
            targetLanguage: { "de" },
            subtitleStatuses: { [url: "succeeded"] },
            timerFactory: ManualPollTimerFactory()
        )
        // detected=en, target=de; the cached row (language=de) short-circuits.
        try await seedSubtitle(database: database, url: url, language: "en")
        await deController.refresh()
        #expect(L2ContractTests.ReplayProtocol.requests().isEmpty)
        #expect(deController.statuses[url] == "succeeded")
    }

    @Test("translation K9: five consecutive failures stop the loop for that URL")
    func translationRetryCap() async throws {
        let (database, databaseDirectory) = try await makeDatabase()
        defer { SandboxCleanup.remove(databaseDirectory, closing: [database.queue]) }
        let url = "https://x.example/ep1.mp3"
        try await seedSubtitle(database: database, url: url, language: "en")

        let controller = TranslationPollController(
            api: makeAPI(),
            translations: database.translationRepository(),
            subtitles: database.subtitleRepository(),
            targetLanguage: { "zh" },
            subtitleStatuses: { [url: "succeeded"] },
            timerFactory: ManualPollTimerFactory()
        )

        L2ContractTests.ReplayProtocol.reset { _ in
            .response(status: 200, body: #"{"translation":null}"#)
        }
        for _ in 0..<5 {
            await controller.refresh()
        }
        #expect(controller.statuses[url] == "failed", "K9: cap reached → failure state")
        let requestCount = L2ContractTests.ReplayProtocol.requests().count
        #expect(requestCount == TranslationPollController.failureCap)

        // Further rounds emit nothing — the forever-retry of the old build
        // is gone.
        await controller.refresh()
        await controller.refresh()
        #expect(L2ContractTests.ReplayProtocol.requests().count == requestCount)

        // A language switch resets the map (Dart setTargetLanguage).
        controller.resetForLanguageChange()
        #expect(controller.statuses.isEmpty)
    }

    @Test("translation success persists the row with the encoded payload")
    func translationPersists() async throws {
        let (database, databaseDirectory) = try await makeDatabase()
        defer { SandboxCleanup.remove(databaseDirectory, closing: [database.queue]) }
        let url = "https://x.example/ep1.mp3"
        try await seedSubtitle(database: database, url: url, language: "en")

        let controller = TranslationPollController(
            api: makeAPI(),
            translations: database.translationRepository(),
            subtitles: database.subtitleRepository(),
            targetLanguage: { "zh" },
            subtitleStatuses: { [url: "succeeded"] },
            timerFactory: ManualPollTimerFactory()
        )
        L2ContractTests.ReplayProtocol.reset { _ in
            .response(status: 200, body: #"{"translation":[{"start":0.0,"end":4.0,"text":"你好"}]}"#)
        }
        await controller.refresh()
        #expect(controller.statuses[url] == "succeeded")
        let stored = try await database.translationRepository().get(byEnclosureURL: url, language: "zh")
        #expect(stored != nil)
        #expect((stored?.segments ?? []).first?.text == "你好")
    }
}
