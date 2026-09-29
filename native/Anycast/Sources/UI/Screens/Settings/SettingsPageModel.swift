import Foundation
import AnycastKit

/// Pure model for the settings sheet (lib/pages/settings.dart, 03 §2.13):
/// row/group structure, tooltip copy, picker value↔index mapping (G9),
/// option lists, and the deep links. UI-free so the parity fixtures in
/// AnycastAppTests/Settings assert against data, not UIKit.
nonisolated enum SettingsPageModel {

    // MARK: - Row identity (order = settings.dart ListView order)

    enum Row: Hashable {
        case account
        case country
        case enableTranslation
        case targetLanguage
        case importExport
        case history
        case autoRefreshInterval
        case maxFeedEpisodes
        case maxHistoryEpisodes
        case contactEmail
        case privacyPolicy
        case termsOfUse
    }

    struct Section {
        let header: String?
        let rows: [Row]
        /// The trailing Privacy links render outside a group card in Dart
        /// (a centered column, not a `SettingsGroup`).
        let plainStyle: Bool
    }

    /// Group structure exactly as settings.dart builds it. The Target
    /// Language row is conditional (appended by `sections(includeTargetLanguage:)`).
    static func sections(includeTargetLanguage: Bool) -> [Section] {
        var transcriptRows: [Row] = [.country, .enableTranslation]
        if includeTargetLanguage {
            transcriptRows.append(.targetLanguage)
        }
        return [
            Section(header: nil, rows: [.account], plainStyle: false),
            Section(header: "Transcript & Translation", rows: transcriptRows, plainStyle: false),
            Section(header: "Podcast", rows: [.importExport, .history], plainStyle: false),
            Section(header: "Other",
                    rows: [.autoRefreshInterval, .maxFeedEpisodes, .maxHistoryEpisodes],
                    plainStyle: false),
            Section(header: "Contact", rows: [.contactEmail], plainStyle: false),
            Section(header: nil, rows: [.privacyPolicy, .termsOfUse], plainStyle: true),
        ]
    }

    /// Whether the conditional row is visible: only while a target language
    /// is set (settings.dart:239 — `targetLanguage.value == ''` → shrink).
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
        case .country: return "Country"
        case .enableTranslation: return "Enable Transcript Translation"
        case .targetLanguage: return "Target Language"
        case .importExport: return "Import / Export"
        case .history: return "History"
        case .autoRefreshInterval: return "Auto Refresh Interval"
        case .maxFeedEpisodes: return "Max Episodes in Inbox"
        case .maxHistoryEpisodes: return "Max Episodes in History"
        case .contactEmail: return contactEmailDisplay
        case .privacyPolicy: return "Privacy Policy"
        case .termsOfUse: return "Terms of Use (EULA)"
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

    // MARK: - Picker mapping (G9)

    /// `minutes.indexOf(interval ~/ 60)` with the CupertinoPicker fallback
    /// (no match → row 0), settings.dart:312-316.
    static func autoRefreshPickerIndex(seconds: Int64) -> Int {
        let minutes = SettingsCodec.autoRefreshChoicesSeconds.map { $0 / 60 }
        let index = minutes.firstIndex(of: seconds / 60) ?? -1
        return max(0, index)
    }

    static func autoRefreshSeconds(at index: Int) -> Int64 {
        SettingsCodec.autoRefreshChoicesSeconds[clamped(index, in: SettingsCodec.autoRefreshChoicesSeconds)]
    }

    /// Picker rows: "1 min" … "30 min" (settings.dart:330-336).
    static func autoRefreshLabel(at index: Int) -> String {
        "\(SettingsCodec.autoRefreshChoicesSeconds[clamped(index, in: SettingsCodec.autoRefreshChoicesSeconds)] / 60) min"
    }

    /// Trailing value on the row: `interval ~/ 60` minutes.
    static func autoRefreshDisplay(seconds: Int64) -> String {
        "\(seconds / 60) min"
    }

    /// The caps use `value ~/ 100` as the picker index (settings.dart:370-372,
    /// 419-421) — NOT indexOf. Clamped so a stray DB value still lands on a
    /// valid row (the Dart picker would scroll off-list instead).
    static func maxEpisodesPickerIndex(count: Int64) -> Int {
        let index = Int(count / 100)
        return min(max(0, index), SettingsCodec.maxEpisodesChoices.count - 1)
    }

    static func maxEpisodesCount(at index: Int) -> Int64 {
        SettingsCodec.maxEpisodesChoices[clamped(index, in: SettingsCodec.maxEpisodesChoices)]
    }

    static func maxEpisodesLabel(at index: Int) -> String {
        String(SettingsCodec.maxEpisodesChoices[clamped(index, in: SettingsCodec.maxEpisodesChoices)])
    }

    static func maxEpisodesDisplay(count: Int64) -> String {
        String(count)
    }

    private static func clamped(_ index: Int, in choices: [Int64]) -> Int {
        min(max(0, index), choices.count - 1)
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

    /// Displayed contact address (settings.dart:461).
    static let contactEmailDisplay = "kindjeff.com@gmail.com"

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

    /// Both option sheets carry the package's default dialog header — the
    /// shipped app shows "Select Country" over the language list too
    /// (country_code_picker `headerText` default, never overridden).
    static let optionSheetTitle = "Select Country"

    /// Dart `String.compareTo` — UTF-16 code-unit lexicographic comparison.
    private static func utf16Units(_ string: String) -> [UInt16] {
        Array(string.utf16)
    }
}
