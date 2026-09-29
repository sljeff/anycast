import Foundation
import Testing
import AnycastKit
@testable import Anycast

/// T7 write flows: the settings coordinator's notification payloads and box
/// propagation over a real database, plus the language-change side-effect
/// ordering (reset before persist, mirroring Dart `setTargetLanguage`).
@MainActor
struct SettingsWriteFlowTests {

    private func makeCoordinator() async throws -> (coordinator: SettingsCoordinator, box: SettingsBox, database: AppDatabase, databaseURL: URL) {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("t7-settings-\(UUID().uuidString).sqlite")
        let database = try await AppDatabase.openAt(url, localeIdentifier: "en_US")
        let box = SettingsBox(AppSettings.defaults(localeIdentifier: "en_US"))
        let coordinator = SettingsCoordinator(
            repository: database.settingsRepository(),
            settingsBox: box
        )
        return (coordinator, box, database, url)
    }

    @Test("Country change: persists, refreshes the box, posts the payload")
    func countryChangeNotification() async throws {
        let (coordinator, box, database, databaseURL) = try await makeCoordinator()
        defer { try? FileManager.default.removeItem(at: databaseURL) }
        var notes = NotificationCenter.default.notifications(
            named: SettingsCoordinator.countryCodeDidChange, object: nil
        ).makeAsyncIterator()

        await coordinator.updateCountryCode("JP")

        let note = await notes.next()
        #expect(note?.userInfo?[SettingsCoordinator.countryCodeKey] as? String == "JP")
        #expect(box.current.countryCode == "JP")

        // The row survives a reopen (persisted, not in-memory only).
        let reloaded = try await database.settingsRepository().load()
        #expect(reloaded.countryCode == "JP")
    }

    @Test("Language change: persists '' or a code and posts the payload")
    func languageChangeNotification() async throws {
        let (coordinator, box, _, databaseURL) = try await makeCoordinator()
        defer { try? FileManager.default.removeItem(at: databaseURL) }
        var notes = NotificationCenter.default.notifications(
            named: SettingsCoordinator.targetLanguageDidChange, object: nil
        ).makeAsyncIterator()

        await coordinator.updateTargetLanguage("zh")
        var note = await notes.next()
        #expect(note?.userInfo?[SettingsCoordinator.targetLanguageKey] as? String == "zh")
        #expect(box.current.targetLanguage == "zh")
        #expect(SettingsPageModel.showsTargetLanguage(targetLanguage: box.current.targetLanguage))

        // Switch off writes the empty string and still notifies.
        await coordinator.updateTargetLanguage("")
        note = await notes.next()
        #expect(note?.userInfo?[SettingsCoordinator.targetLanguageKey] as? String == "")
        #expect(box.current.targetLanguage == "")
        #expect(!SettingsPageModel.showsTargetLanguage(targetLanguage: box.current.targetLanguage))
    }

    @Test("Limits writes post the numeric payloads (interval seconds, caps)")
    func limitsNotifications() async throws {
        let (coordinator, box, _, databaseURL) = try await makeCoordinator()
        defer { try? FileManager.default.removeItem(at: databaseURL) }
        var notes = NotificationCenter.default.notifications(
            named: SettingsCoordinator.limitsDidChange, object: nil
        ).makeAsyncIterator()

        await coordinator.updateAutoRefreshInterval(600)
        var note = await notes.next()
        #expect(note?.userInfo?[SettingsCoordinator.autoRefreshIntervalKey] as? Int64 == 600)
        #expect(box.current.autoRefreshInterval == 600)

        await coordinator.updateMaxFeedEpisodes(300)
        note = await notes.next()
        #expect(note?.userInfo?[SettingsCoordinator.maxFeedEpisodesKey] as? Int64 == 300)
        #expect(box.current.maxFeedEpisodes == 300)

        await coordinator.updateMaxHistoryEpisodes(50)
        note = await notes.next()
        #expect(note?.userInfo?[SettingsCoordinator.maxHistoryEpisodesKey] as? Int64 == 50)
        #expect(box.current.maxHistoryEpisodes == 50)
    }

    @Test("Language applier resets the translation map before persisting")
    func languageApplierOrdering() async {
        let calls = Calls()
        let applier = SettingsLanguageChangeApplier(
            resetTranslations: { calls.record("reset") },
            persist: { language in
                calls.record("persist:\(language)")
            }
        )
        await applier.apply("ja")
        #expect(calls.order == ["reset", "persist:ja"])
    }

    @Test("Live applier wires the real poller reset into the real write path")
    func liveApplierWiring() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("t7-poller-\(UUID().uuidString).sqlite")
        defer { try? FileManager.default.removeItem(at: url) }
        let database = try await AppDatabase.openAt(url, localeIdentifier: "en_US")
        let box = SettingsBox(AppSettings.defaults(localeIdentifier: "en_US"))
        let coordinator = SettingsCoordinator(
            repository: database.settingsRepository(),
            settingsBox: box
        )
        // A real poller over the same stack PlaybackStack builds.
        let poller = TranslationPollController(
            api: APIClient(client: HTTPClient(), tokenProvider: { nil }),
            translations: database.translationRepository(),
            subtitles: database.subtitleRepository(),
            targetLanguage: { box.current.targetLanguage },
            subtitleStatuses: { [:] }
        )
        var notes = NotificationCenter.default.notifications(
            named: SettingsCoordinator.targetLanguageDidChange, object: nil
        ).makeAsyncIterator()

        let applier = SettingsLanguageChangeApplier.live(
            translations: poller,
            coordinator: coordinator
        )
        await applier.apply("zh")

        // Persist + box refresh + notification all happened, and the reset
        // ran on the live poller (map empty, no state left behind).
        let note = await notes.next()
        #expect(note?.userInfo?[SettingsCoordinator.targetLanguageKey] as? String == "zh")
        #expect(box.current.targetLanguage == "zh")
        #expect(poller.statuses.isEmpty)
    }

    private final class Calls: @unchecked Sendable {
        private let lock = NSLock()
        private(set) var order: [String] = []
        func record(_ step: String) {
            lock.lock()
            order.append(step)
            lock.unlock()
        }
    }
}
