import Foundation
import AnycastKit

/// Settings writes funnel (the Flutter `SettingsController` mutations):
/// repository write → settings box refresh → named notification. Screens
/// never write the repository or the box directly.
@MainActor
final class SettingsCoordinator {

    /// Discover reloads its channel list when the country changes (T7).
    static let countryCodeDidChange = Notification.Name("AnycastSettingsCountryCodeDidChange")
    /// The player re-polls translations with the new target language.
    static let targetLanguageDidChange = Notification.Name("AnycastSettingsTargetLanguageDidChange")
    /// Inbox trimming / auto-refresh cadence consumers.
    static let limitsDidChange = Notification.Name("AnycastSettingsLimitsDidChange")

    /// userInfo keys carried by the notifications above.
    static let countryCodeKey = "countryCode"
    static let targetLanguageKey = "targetLanguage"
    static let autoRefreshIntervalKey = "autoRefreshIntervalSeconds"
    static let maxFeedEpisodesKey = "maxFeedEpisodes"
    static let maxHistoryEpisodesKey = "maxHistoryEpisodes"

    private let repository: SettingsRepository
    private let settingsBox: SettingsBox
    private let center: NotificationCenter

    init(repository: SettingsRepository, settingsBox: SettingsBox,
         center: NotificationCenter = .default) {
        self.repository = repository
        self.settingsBox = settingsBox
        self.center = center
    }

    // MARK: - Mutations (each: persist → refresh box → notify)

    /// Failure contract: a write that did not land skips BOTH the box
    /// refresh and the notification — broadcasting a value the box does not
    /// hold sends consumers (Discover reload, pollers) chasing a phantom
    /// change. The DB remains the source of truth; the next successful
    /// write re-syncs.
    private func performPersist(notify: () -> Void,
                                _ persist: () async throws -> Void) async {
        do {
            try await persist()
        } catch {
            return
        }
        await refreshBox()
        notify()
    }

    func updateCountryCode(_ code: String) async {
        await performPersist(
            notify: {
                center.post(
                    name: Self.countryCodeDidChange,
                    object: nil,
                    userInfo: [Self.countryCodeKey: code]
                )
            }
        ) {
            try await repository.setCountryCode(code)
        }
    }

    func updateTargetLanguage(_ language: String) async {
        await performPersist(
            notify: {
                center.post(
                    name: Self.targetLanguageDidChange,
                    object: nil,
                    userInfo: [Self.targetLanguageKey: language]
                )
            }
        ) {
            try await repository.setTargetLanguage(language)
        }
    }

    func updateAutoRefreshInterval(_ seconds: Int64) async {
        await performPersist(
            notify: {
                center.post(
                    name: Self.limitsDidChange,
                    object: nil,
                    userInfo: [Self.autoRefreshIntervalKey: seconds]
                )
            }
        ) {
            try await repository.setAutoRefreshInterval(seconds)
        }
    }

    func updateMaxFeedEpisodes(_ count: Int64) async {
        await performPersist(
            notify: {
                center.post(
                    name: Self.limitsDidChange,
                    object: nil,
                    userInfo: [Self.maxFeedEpisodesKey: count]
                )
            }
        ) {
            try await repository.setMaxFeedEpisodes(count)
        }
    }

    func updateMaxHistoryEpisodes(_ count: Int64) async {
        await performPersist(
            notify: {
                center.post(
                    name: Self.limitsDidChange,
                    object: nil,
                    userInfo: [Self.maxHistoryEpisodesKey: count]
                )
            }
        ) {
            try await repository.setMaxHistoryEpisodes(count)
        }
    }

    /// The box is the pollers' live view; the DB stays the source of truth,
    /// so the refresh re-reads rather than patching a local copy.
    private func refreshBox() async {
        if let settings = try? await repository.load() {
            settingsBox.update(settings)
        }
    }
}
