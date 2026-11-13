import Foundation
import AnycastKit

/// Pure model for the settings sheet (lib/pages/settings.dart, 03 §2.13):
/// row/group structure, row copy and trailing values, VoiceOver hints, stepper
/// step math, option lists, and the deep links. The grouping, copy and
/// in-row steppers follow the restrained 2.0 Settings direction adopted
/// 2026-10-21 (the Dart scroll-wheel pickers are gone), regrouped by task in
/// the batch-1 redesign. UI-free so the fixtures in AnycastAppTests/Settings
/// assert against data, not UIKit.
nonisolated enum SettingsPageModel {

    // MARK: - Row identity (order = on-screen order)

    enum Row: Hashable {
        case account
        /// Anycast Plus offer, the second row of the identity plate (signed
        /// out and free tiers only).
        case plusUpgrade
        case targetLanguage
        case maxFeedEpisodes
        case maxHistoryEpisodes
        case cacheLimit
        /// Space the played audio takes, and the action to clear it.
        case clearCache
        case country
        case importSubscriptions
        case exportSubscriptions
        case contactEmail
        case privacyPolicy
        case termsOfUse
    }

    /// The text under a section's plate.
    enum Footer {
        /// "Keep on this iPhone": the standing note, or the held-limit notices.
        case keep
        /// The note under "Shows": what Export covers.
        case shows
        /// The app version line.
        case version
    }

    struct Section {
        let header: String?
        let rows: [Row]
        let footer: Footer?
    }

    /// Group structure of the Settings page. The Plus offer joins the
    /// identity plate for everyone who is not Plus.
    static func sections(tier: AccountPageModel.Tier) -> [Section] {
        let identity: [Row] = tier == .free || tier == .signedOut ? [.account, .plusUpgrade] : [.account]
        return [
            Section(header: nil, rows: identity, footer: nil),
            Section(header: "Transcripts", rows: [.targetLanguage], footer: nil),
            Section(header: "Keep on this iPhone",
                    rows: [.maxFeedEpisodes, .maxHistoryEpisodes, .cacheLimit, .clearCache], footer: .keep),
            Section(header: "Shows", rows: [.country, .importSubscriptions, .exportSubscriptions],
                    footer: .shows),
            Section(header: "Help",
                    rows: [.contactEmail, .privacyPolicy, .termsOfUse], footer: .version),
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
        case .plusUpgrade: return AccountPageModel.upgradePlateTitle
        case .targetLanguage: return "Translate to"
        case .maxFeedEpisodes: return "Inbox"
        case .maxHistoryEpisodes: return "History"
        case .cacheLimit: return "Played audio"
        case .country: return "Charts from"
        case .clearCache: return "Clear played audio"
        case .importSubscriptions: return "Import subscriptions"
        case .exportSubscriptions: return "Export subscriptions"
        case .contactEmail: return "Send Feedback"
        case .privacyPolicy: return "Privacy Policy"
        case .termsOfUse: return "Terms of Use"
        }
    }

    /// Trailing action on the Plus row: plans for a visitor, upgrade for Free.
    static func plusActionTitle(tier: AccountPageModel.Tier) -> String {
        tier == .signedOut ? "See Plans" : AccountPageModel.upgradePlateAction
    }

    /// Trailing value text; nil for rows that show none. Stepper rows show
    /// the stored value even when it is off the choice list.
    static func value(for row: Row, settings: AppSettings) -> String? {
        switch row {
        case .country:
            return countryName(forCode: settings.countryCode)
        case .targetLanguage:
            return showsTargetLanguage(targetLanguage: settings.targetLanguage)
                ? languageName(forCode: settings.targetLanguage) : "Off"
        case .maxFeedEpisodes:
            return "Latest \(settings.maxFeedEpisodes)"
        case .maxHistoryEpisodes:
            return "Latest \(settings.maxHistoryEpisodes)"
        case .cacheLimit:
            return "\(settings.maxCacheCount) episodes"
        default:
            return nil
        }
    }

    /// Trailing value of "Export subscriptions": a note instead when there
    /// is nothing to export.
    static func exportValue(subscriptionCount: Int) -> String? {
        subscriptionCount == 0 ? ImportCopy.exportEmpty : nil
    }

    /// Trailing value of "Clear played audio": the space the files take.
    static func cacheUsageValue(bytes: Int64) -> String {
        bytes <= 0 ? "None" : ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    /// The confirmation before clearing played audio.
    static func clearCacheMessage(bytes: Int64) -> String {
        "Frees \(ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)). "
            + "Episodes download again when you play them. The episode playing now stays."
    }

    /// VoiceOver hint read after the row name; the sighted page carries no
    /// long-press captions.
    static func accessibilityHint(for row: Row) -> String? {
        switch row {
        case .country:
            return "Discover shows charts from this country."
        case .targetLanguage:
            return "Translates transcripts into this language."
        case .maxFeedEpisodes, .maxHistoryEpisodes:
            return "Older episodes are removed automatically."
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
        case .maxFeedEpisodes, .maxHistoryEpisodes: return SettingsCodec.maxEpisodesChoices
        case .cacheLimit: return cacheLimitChoices
        default: return nil
        }
    }

    /// The stored value a stepper row steps from.
    static func stepperValue(for row: Row, settings: AppSettings) -> Int64? {
        switch row {
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

    /// Standing note under "Keep on this iPhone".
    static let keepNote = "Older ones are removed automatically."

    /// Line for a held Inbox or History limit that is lower than the number
    /// of episodes stored. Nil when nothing would be removed.
    static func removalNotice(for row: Row, pendingLimit: Int64, count: Int) -> String? {
        let removed = count - Int(clamping: pendingLimit)
        guard removed > 0 else { return nil }
        let place = row == .maxFeedEpisodes ? "the Inbox" : "History"
        return removed == 1
            ? "Oldest episode leaves \(place) when you close Settings."
            : "\(removed) oldest episodes leave \(place) when you close Settings."
    }

    /// The "Keep on this iPhone" footer: the held-limit notices (Inbox
    /// first, one per line) or, with none, the standing note.
    static func keepFooter(pendingLimits: [Row: Int64], counts: [Row: Int]) -> String {
        let notices = [Row.maxFeedEpisodes, .maxHistoryEpisodes].compactMap { row in
            pendingLimits[row].flatMap { pending in
                counts[row].flatMap { removalNotice(for: row, pendingLimit: pending, count: $0) }
            }
        }
        return notices.isEmpty ? keepNote : notices.joined(separator: "\n")
    }

    /// An Inbox or History limit stepped in this sheet. Steps are held here
    /// and written once, when Settings closes, so stepping below the stored
    /// count removes nothing yet and can be stepped back.
    struct LimitDraft: Equatable {
        /// The limit persisted in settings.
        let stored: Int64
        /// A held value that differs from `stored`; nil when there is none.
        private(set) var pending: Int64?

        init(stored: Int64, pending: Int64? = nil) {
            self.stored = stored
            self.pending = pending == stored ? nil : pending
        }

        /// What the stepper row shows.
        var shown: Int64 { pending ?? stored }

        mutating func step(_ direction: StepDirection, in choices: [Int64]) {
            let next = SettingsPageModel.steppedValue(from: shown, direction, in: choices)
            pending = next == stored ? nil : next
        }
    }

    /// VoiceOver names for the minus/plus halves of each stepper row.
    static func stepperAccessibilityLabels(for row: Row) -> (decrease: String, increase: String)? {
        switch row {
        case .maxFeedEpisodes: return ("Lower inbox limit", "Raise inbox limit")
        case .maxHistoryEpisodes: return ("Lower history limit", "Raise history limit")
        case .cacheLimit: return ("Lower cache limit", "Raise cache limit")
        default: return nil
        }
    }

    // MARK: - Country / language options

    /// The 49-country whitelist, named in the system language and sorted
    /// by that name with the locale's own collation, so "Österreich" sits
    /// with the O's. The stored value is still the region code.
    static func sortedCountries(locale: Locale = .current) -> [(name: String, code: String)] {
        SettingsCodec.countries
            .map { (name: displayName(forRegion: $0.code, fallback: $0.name, locale: locale), code: $0.code) }
            .sorted { $0.name.compare($1.name, locale: locale) == .orderedAscending }
    }

    /// A region's name in the system language; the whitelist's own name
    /// when the system has none.
    static func displayName(forRegion code: String, fallback: String, locale: Locale = .current) -> String {
        locale.localizedString(forRegionCode: code) ?? fallback
    }

    /// Languages keep declaration order (the package does not sort;
    /// settings.dart targetLangList).
    static let languages: [(name: String, code: String)] = SettingsCodec.targetLanguages

    /// Display name for a code; unknown codes fall back to the first entry,
    /// matching the picker's `elements[0]` fallback (country_code_picker
    /// createState/firstWhere).
    static func countryName(forCode code: String, locale: Locale = .current) -> String {
        let upper = code.uppercased()
        let countries = sortedCountries(locale: locale)
        return countries.first { $0.code.uppercased() == upper }?.name ?? countries[0].name
    }

    static func languageName(forCode code: String) -> String {
        let lower = code.lowercased()
        return languages.first { $0.code.lowercased() == lower }?.name
            ?? languages[0].name
    }

    /// Language sheet options: "Off" (the empty stored value) first.
    static let languageOptions: [(name: String, code: String)] = [("Off", "")] + languages

    // MARK: - Deep links

    /// The mailto the shipped app actually opens (settings.dart:451-458) —
    /// note the missing dot in the recipient, mirrored byte-for-byte. The
    /// composer takes its recipient from here.
    static let feedbackMailtoURL = URL(
        string: "mailto:kindjeffcom@gmail.com?subject=Anycast%20Feedback"
    )!

    /// Recipient address of `feedbackMailtoURL`.
    static var feedbackAddress: String {
        URLComponents(url: feedbackMailtoURL, resolvingAgainstBaseURL: false)?.path ?? ""
    }

    static let feedbackSubject = "Anycast Feedback"

    /// Feedback mail body: room to write, then a diagnostics block.
    static func feedbackBody(appVersion: String, build: String, systemVersion: String,
                             deviceModel: String) -> String {
        """


        ---
        Anycast \(appVersion) (\(build))
        iOS \(systemVersion)
        \(deviceModel)
        """
    }

    /// The version line under the Help plate.
    static func versionLine(appVersion: String, build: String) -> String {
        "Anycast \(appVersion) (\(build))"
    }

    /// Privacy/EULA targets (widgets/privacy.dart:17-19, 33-38).
    static let privacyPolicyURL = URL(string: "https://privacy.anycast.website")!
    static let termsOfUseURL = URL(
        string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/"
    )!

}
