import Foundation
import AnycastKit

/// Pure model for the settings sheet (lib/pages/settings.dart, 03 §2.13):
/// row/group structure, row copy and trailing values, tooltip copy, stepper
/// step math, option lists, and the deep links. The grouping, copy and
/// in-row steppers follow the restrained 2.0 Settings direction adopted
/// 2026-10-21 (the Dart scroll-wheel pickers are gone). UI-free so the
/// fixtures in AnycastAppTests/Settings assert against data, not UIKit.
nonisolated enum SettingsPageModel {

    // MARK: - Row identity (order = on-screen order)

    enum Row: Hashable {
        case account
        case cacheLimit
        case enableTranslation
        case targetLanguage
        case country
        case autoRefreshInterval
        case maxFeedEpisodes
        case maxHistoryEpisodes
        case importExport
        case history
        case contactEmail
        case privacyPolicy
        case termsOfUse
    }

    struct Section {
        let header: String?
        let rows: [Row]
        /// The trailing Privacy links render outside a group plate (a
        /// centered column of plain links, not a grouped list).
        let plainStyle: Bool
    }

    /// Group structure of the 2.0 Settings page. Target Language is always
    /// present; it reads "Off" and is inert while translation is off.
    static func sections() -> [Section] {
        [
            Section(header: nil, rows: [.account], plainStyle: false),
            Section(header: "Downloads & Storage", rows: [.cacheLimit], plainStyle: false),
            Section(header: "Subtitles & Translation",
                    rows: [.enableTranslation, .targetLanguage], plainStyle: false),
            Section(header: "Content & Discovery",
                    rows: [.country, .autoRefreshInterval, .maxFeedEpisodes,
                           .maxHistoryEpisodes, .importExport, .history],
                    plainStyle: false),
            Section(header: "Help", rows: [.contactEmail], plainStyle: false),
            Section(header: nil, rows: [.privacyPolicy, .termsOfUse], plainStyle: true),
        ]
    }

    /// Whether translation is on: a target language is set (settings.dart:239
    /// — `targetLanguage.value == ''` means off).
    static func showsTargetLanguage(targetLanguage: String) -> Bool {
        !targetLanguage.isEmpty
    }

    // MARK: - Row copy

    /// Stable UI-test handle (M3 DoD: every screen is verifiable by test).
    static func identifier(for row: Row) -> String {
        "settings-row-\(String(describing: row))"
    }

    static func title(for row: Row) -> String {
        switch row {
        case .account: return "Account"
        case .cacheLimit: return "Cache Limit"
        case .enableTranslation: return "Subtitle Translation"
        case .targetLanguage: return "Target Language"
        case .country: return "Discovery Region"
        case .autoRefreshInterval: return "Auto Refresh"
        case .maxFeedEpisodes: return "Inbox Limit"
        case .maxHistoryEpisodes: return "History Limit"
        case .importExport: return "Import & Export"
        case .history: return "Listening History"
        case .contactEmail: return "Contact Us"
        case .privacyPolicy: return "Privacy Policy"
        case .termsOfUse: return "Terms of Use (EULA)"
        }
    }

    /// Optional one-line caption under the title.
    static func subtitle(for row: Row) -> String? {
        row == .enableTranslation ? "Translate generated text" : nil
    }

    /// Trailing value text; nil for rows that show none (switch, plain
    /// chevron rows). Stepper rows show the stored value even when it is
    /// off the choice list.
    static func value(for row: Row, settings: AppSettings) -> String? {
        switch row {
        case .country:
            return countryName(forCode: settings.countryCode)
        case .targetLanguage:
            return showsTargetLanguage(targetLanguage: settings.targetLanguage)
                ? languageName(forCode: settings.targetLanguage) : "Off"
        case .autoRefreshInterval:
            return autoRefreshDisplay(seconds: settings.autoRefreshInterval)
        case .maxFeedEpisodes:
            return episodesDisplay(count: settings.maxFeedEpisodes)
        case .maxHistoryEpisodes:
            return episodesDisplay(count: settings.maxHistoryEpisodes)
        case .cacheLimit:
            return episodesDisplay(count: settings.maxCacheCount)
        case .contactEmail:
            return "Email"
        default:
            return nil
        }
    }

    /// Long-press info captions — the five Dart `Tooltip` messages verbatim
    /// (settings.dart:150, 255, 302, 356, 405). Trigger/display adaptation
    /// per 07 §2.7: long-press shows the caption ~2 s.
    static func tooltip(for row: Row) -> String? {
        switch row {
        case .country:
            return "Discover page will show episodes from this country."
        case .targetLanguage:
            return "Translates the podcast transcript into the target language."
        case .autoRefreshInterval:
            return "Automatically fetch new episodes every X minutes."
        case .maxFeedEpisodes:
            return "Limits the number of episodes in the inbox. Auto deleted if exceeded."
        case .maxHistoryEpisodes:
            return "Limits the number of episodes in the history. Auto deleted if exceeded."
        default:
            return nil
        }
    }

    // MARK: - Stepper step math

    /// Cache Limit choices (episodes kept in the audio cache).
    static let cacheLimitChoices: [Int64] = [5, 10, 20, 50, 100]

    enum StepDirection {
        case decrease
        case increase
    }

    /// Choice list behind a stepper row; nil for rows that are not steppers.
    static func stepperChoices(for row: Row) -> [Int64]? {
        switch row {
        case .autoRefreshInterval: return SettingsCodec.autoRefreshChoicesSeconds
        case .maxFeedEpisodes, .maxHistoryEpisodes: return SettingsCodec.maxEpisodesChoices
        case .cacheLimit: return cacheLimitChoices
        default: return nil
        }
    }

    /// The stored value a stepper row steps from.
    static func stepperValue(for row: Row, settings: AppSettings) -> Int64? {
        switch row {
        case .autoRefreshInterval: return settings.autoRefreshInterval
        case .maxFeedEpisodes: return settings.maxFeedEpisodes
        case .maxHistoryEpisodes: return settings.maxHistoryEpisodes
        case .cacheLimit: return settings.maxCacheCount
        default: return nil
        }
    }

    /// Exact match, otherwise the nearest choice (the lower one on a tie), so
    /// a stray stored value still steps from a sensible position.
    static func choiceIndex(of value: Int64, in choices: [Int64]) -> Int {
        if let exact = choices.firstIndex(of: value) { return exact }
        return choices.indices.min { abs(choices[$0] - value) < abs(choices[$1] - value) } ?? 0
    }

    /// The choice one step away from `value`, clamped at the list ends.
    static func steppedValue(from value: Int64, _ direction: StepDirection, in choices: [Int64]) -> Int64 {
        let current = choiceIndex(of: value, in: choices)
        let next = direction == .increase ? current + 1 : current - 1
        return choices[min(max(0, next), choices.count - 1)]
    }

    /// Whether the minus half is usable: false at the minimum choice.
    static func canDecrease(from value: Int64, in choices: [Int64]) -> Bool {
        choiceIndex(of: value, in: choices) > 0
    }

    /// Whether the plus half is usable: false at the maximum choice.
    static func canIncrease(from value: Int64, in choices: [Int64]) -> Bool {
        choiceIndex(of: value, in: choices) < choices.count - 1
    }

    /// Trailing value on the Auto Refresh row: `interval ~/ 60` minutes.
    static func autoRefreshDisplay(seconds: Int64) -> String {
        "\(seconds / 60) min"
    }

    static func episodesDisplay(count: Int64) -> String {
        "\(count) episodes"
    }

    /// VoiceOver names for the minus/plus halves of each stepper row.
    static func stepperAccessibilityLabels(for row: Row) -> (decrease: String, increase: String)? {
        switch row {
        case .autoRefreshInterval: return ("Shorter auto refresh interval", "Longer auto refresh interval")
        case .maxFeedEpisodes: return ("Lower inbox limit", "Raise inbox limit")
        case .maxHistoryEpisodes: return ("Lower history limit", "Raise history limit")
        case .cacheLimit: return ("Lower cache limit", "Raise cache limit")
        default: return nil
        }
    }

    // MARK: - Country / language options

    /// The 49-country whitelist sorted like the Dart build does
    /// (settings.dart:91 — `String.compareTo`, UTF-16 code-unit order).
    static let sortedCountries: [(name: String, code: String)] =
        SettingsCodec.countries.sorted { a, b in
            utf16Units(a.name).lexicographicallyPrecedes(utf16Units(b.name))
        }

    /// Languages keep declaration order (the package does not sort;
    /// settings.dart targetLangList).
    static let languages: [(name: String, code: String)] = SettingsCodec.targetLanguages

    /// Display name for a code; unknown codes fall back to the first entry,
    /// matching the picker's `elements[0]` fallback (country_code_picker
    /// createState/firstWhere).
    static func countryName(forCode code: String) -> String {
        let upper = code.uppercased()
        return sortedCountries.first { $0.code.uppercased() == upper }?.name
            ?? sortedCountries[0].name
    }

    static func languageName(forCode code: String) -> String {
        let lower = code.lowercased()
        return languages.first { $0.code.lowercased() == lower }?.name
            ?? languages[0].name
    }

    /// Language preselected when the translation switch turns on:
    /// `Platform.localeName` split on "_" taking the first segment, default
    /// "en" (settings.dart:221-228). iOS hands us hyphenated identifiers —
    /// the G9 locale fixture split (first segment = language).
    static func defaultTargetLanguage(localeIdentifier: String) -> String {
        let normalized = localeIdentifier.replacingOccurrences(of: "-", with: "_")
        let parts = normalized.split(separator: "_", omittingEmptySubsequences: false)
        guard parts.count > 1 else { return "en" }
        return String(parts[0])
    }

    // MARK: - Deep links

    /// The mailto the shipped app actually opens (settings.dart:451-458) —
    /// note the missing dot in the recipient, mirrored byte-for-byte.
    static let feedbackMailtoURL = URL(
        string: "mailto:kindjeffcom@gmail.com?subject=Anycast%20Feedback"
    )!

    /// Privacy/EULA targets (widgets/privacy.dart:17-19, 33-38).
    static let privacyPolicyURL = URL(string: "https://privacy.anycast.website")!
    static let termsOfUseURL = URL(
        string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/"
    )!

    /// Dart `String.compareTo` — UTF-16 code-unit lexicographic comparison.
    private static func utf16Units(_ string: String) -> [UInt16] {
        Array(string.utf16)
    }
}
