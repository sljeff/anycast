import Foundation
import Testing
import AnycastKit
@testable import Anycast

/// Settings page model (05 §6.1 S16 / 03 §2.13, restrained 2.0 Settings
/// direction 2026-10-21): group/row structure, row copy and trailing values,
/// VoiceOver hints, option lists, locale derivation, and the deep links —
/// asserted against data so the fixtures are independent of the live UI.
@MainActor
struct SettingsPageModelTests {

    // MARK: - Group / row order

    @Test("Sections and rows follow the task grouping, per tier")
    func sectionRowOrder() {
        let tail: [[SettingsPageModel.Row]] = [
            [.targetLanguage],
            [.maxFeedEpisodes, .maxHistoryEpisodes, .cacheLimit],
            [.country, .importExport],
            [.contactEmail, .privacyPolicy, .termsOfUse],
        ]
        for (tier, identity) in [
            (AccountPageModel.Tier.signedOut, [SettingsPageModel.Row.account, .plusUpgrade]),
            (.free, [.account, .plusUpgrade]),
            (.plus, [.account]),
        ] {
            let sections = SettingsPageModel.sections(tier: tier)
            #expect(sections.map(\.rows) == [identity] + tail, "\(tier)")
            #expect(sections.map(\.header) == [nil, "Transcripts", "Keep on this iPhone", "Shows", "Help"])
            #expect(sections.map(\.footer) == [nil, nil, .keep, nil, .version])
        }
        #expect(SettingsPageModel.identifier(for: .plusUpgrade) == "settings-row-plusUpgrade")
    }

    @Test("Plus row action: See Plans signed out, Upgrade for Free")
    func plusAction() {
        #expect(SettingsPageModel.plusActionTitle(tier: .signedOut) == "See Plans")
        #expect(SettingsPageModel.plusActionTitle(tier: .free) == "Upgrade")
    }

    @Test("Translation is on while a target language is set (settings.dart:239)")
    func translationGating() {
        #expect(SettingsPageModel.showsTargetLanguage(targetLanguage: "") == false)
        #expect(SettingsPageModel.showsTargetLanguage(targetLanguage: "ja") == true)
    }

    @Test("Row identifiers stay stable for surviving rows")
    func rowIdentifiers() {
        #expect(SettingsPageModel.identifier(for: .account) == "settings-row-account")
        #expect(SettingsPageModel.identifier(for: .country) == "settings-row-country")
        #expect(SettingsPageModel.identifier(for: .targetLanguage) == "settings-row-targetLanguage")
        #expect(SettingsPageModel.identifier(for: .cacheLimit) == "settings-row-cacheLimit")
    }

    @Test("Row titles")
    func rowLabels() {
        let expected: [SettingsPageModel.Row: String] = [
            .account: "Account",
            .plusUpgrade: "Anycast Plus",
            .targetLanguage: "Translate to",
            .maxFeedEpisodes: "Inbox",
            .maxHistoryEpisodes: "History",
            .cacheLimit: "Played audio",
            .country: "Charts from",
            .importExport: "Import & Export",
            .contactEmail: "Send Feedback",
            .privacyPolicy: "Privacy Policy",
            .termsOfUse: "Terms of Use",
        ]
        for (row, title) in expected {
            #expect(SettingsPageModel.title(for: row) == title)
        }
    }

    @Test("Trailing values: stored value, 'Off' while translation is off, none on link rows")
    func trailingValues() {
        var settings = AppSettings.defaults(localeIdentifier: "en_US")
        settings.countryCode = "JP"
        settings.targetLanguage = "zh"
        settings.maxFeedEpisodes = 200
        settings.maxHistoryEpisodes = 100
        settings.maxCacheCount = 10

        #expect(SettingsPageModel.value(for: .country, settings: settings) == "日本")
        #expect(SettingsPageModel.value(for: .targetLanguage, settings: settings) == "中文")
        #expect(SettingsPageModel.value(for: .maxFeedEpisodes, settings: settings) == "Latest 200")
        #expect(SettingsPageModel.value(for: .maxHistoryEpisodes, settings: settings) == "Latest 100")
        #expect(SettingsPageModel.value(for: .cacheLimit, settings: settings) == "10 episodes")

        settings.targetLanguage = ""
        #expect(SettingsPageModel.value(for: .targetLanguage, settings: settings) == "Off")

        for row: SettingsPageModel.Row in [
            .account, .plusUpgrade, .importExport, .contactEmail, .privacyPolicy, .termsOfUse,
        ] {
            #expect(SettingsPageModel.value(for: row, settings: settings) == nil)
        }
    }

    @Test("VoiceOver hints on the five rows that had captions, none elsewhere")
    func accessibilityHints() {
        #expect(SettingsPageModel.accessibilityHint(for: .maxFeedEpisodes) == "Older episodes are removed automatically.")
        #expect(SettingsPageModel.accessibilityHint(for: .maxHistoryEpisodes) == "Older episodes are removed automatically.")
        #expect(SettingsPageModel.accessibilityHint(for: .country) == "Discover shows charts from this country.")
        #expect(SettingsPageModel.accessibilityHint(for: .targetLanguage) == "Translates transcripts into this language.")
        for row: SettingsPageModel.Row in [.account, .plusUpgrade, .cacheLimit, .importExport, .contactEmail] {
            #expect(SettingsPageModel.accessibilityHint(for: row) == nil)
        }
    }

    // MARK: - Country list (49 whitelist, Dart compareTo display order)

    @Test("Country options: 49 entries, full Dart-UTF16-sorted order")
    func countryOrderFixture() {
        let expected: [(name: String, code: String)] = [
            ("Argentina", "AR"), ("Australia", "AU"), ("Bangladesh", "BD"),
            ("België / Belgique", "BE"), ("Brasil", "BR"), ("Canada", "CA"),
            ("Chile", "CL"), ("Colombia", "CO"), ("Danmark", "DK"),
            ("Deutschland", "DE"), ("España", "ES"), ("France", "FR"),
            ("India", "IN"), ("Indonesia", "ID"), ("Ireland", "IE"),
            ("Israel", "IL"), ("Italia", "IT"), ("Magyarország", "HU"),
            ("Malaysia", "MY"), ("México", "MX"), ("Nederland", "NL"),
            ("New Zealand", "NZ"), ("Nigeria", "NG"), ("Norge", "NO"),
            ("Pakistan", "PK"), ("Philippines", "PH"), ("Polska", "PL"),
            ("Portugal", "PT"), ("România", "RO"), ("Saudi Arabia", "SA"),
            ("Schweiz", "CH"), ("Singapore", "SG"), ("South Africa", "ZA"),
            ("Suomi", "FI"), ("Sverige", "SE"), ("Türkiye", "TR"),
            ("United Kingdom", "GB"), ("United States", "US"),
            ("Việt Nam", "VN"), ("Österreich", "AT"), ("Česká republika", "CZ"),
            ("Ελλάδα", "GR"), ("Россия", "RU"), ("Україна", "UA"),
            ("مصر", "EG"), ("ประเทศไทย", "TH"), ("中国", "CN"),
            ("日本", "JP"), ("대한민국", "KR"),
        ]
        // Tuple arrays are not Equatable; compare element by element.
        #expect(SettingsPageModel.sortedCountries.count == 49)
        #expect(SettingsPageModel.sortedCountries.count == expected.count)
        for (index, option) in SettingsPageModel.sortedCountries.enumerated() {
            #expect(option.name == expected[index].name)
            #expect(option.code == expected[index].code)
        }

        // Same 49 codes as the codec whitelist (order is the only change).
        #expect(Set(SettingsPageModel.sortedCountries.map(\.code))
            == Set(SettingsCodec.countries.map(\.code)))
    }

    @Test("Country name lookup: exact code, case-insensitive, first-entry fallback")
    func countryNameLookup() {
        #expect(SettingsPageModel.countryName(forCode: "US") == "United States")
        #expect(SettingsPageModel.countryName(forCode: "jp") == "日本")
        // country_code_picker falls back to elements[0] ("Argentina").
        #expect(SettingsPageModel.countryName(forCode: "XX") == "Argentina")
    }

    // MARK: - Language list (11 entries, declaration order)

    @Test("Language options and name lookup")
    func languageList() {
        #expect(SettingsPageModel.languages.map(\.code)
            == ["en", "fr", "de", "es", "it", "ja", "zh", "pt", "nl", "uk", "ru"])
        #expect(SettingsPageModel.languageName(forCode: "zh") == "中文")
        #expect(SettingsPageModel.languageName(forCode: "JA") == "日本語")
        // elements[0] fallback = "English".
        #expect(SettingsPageModel.languageName(forCode: "xx") == "English")
    }

    @Test("Language sheet lists Off (the empty stored value) first")
    func languageOptions() {
        #expect(SettingsPageModel.languageOptions.first?.name == "Off")
        #expect(SettingsPageModel.languageOptions.first?.code == "")
        #expect(SettingsPageModel.languageOptions.dropFirst().map(\.code) == SettingsPageModel.languages.map(\.code))
    }

    // MARK: - Inbox / History limits (held until Settings closes)

    @Test("Removal notice: singular, plural, and hidden at or above the count")
    func removalNotice() {
        let feed = SettingsPageModel.Row.maxFeedEpisodes
        let history = SettingsPageModel.Row.maxHistoryEpisodes
        #expect(SettingsPageModel.removalNotice(for: history, pendingLimit: 100, count: 311)
            == "211 oldest episodes leave History when you close Settings.")
        #expect(SettingsPageModel.removalNotice(for: history, pendingLimit: 100, count: 101)
            == "Oldest episode leaves History when you close Settings.")
        #expect(SettingsPageModel.removalNotice(for: feed, pendingLimit: 50, count: 120)
            == "70 oldest episodes leave the Inbox when you close Settings.")
        #expect(SettingsPageModel.removalNotice(for: feed, pendingLimit: 50, count: 51)
            == "Oldest episode leaves the Inbox when you close Settings.")
        #expect(SettingsPageModel.removalNotice(for: feed, pendingLimit: 100, count: 100) == nil)
        #expect(SettingsPageModel.removalNotice(for: history, pendingLimit: 300, count: 100) == nil)
        #expect(SettingsPageModel.removalNotice(for: history, pendingLimit: 100, count: 0) == nil)
    }

    @Test("Keep footer: standing note, one notice, or both with the Inbox first")
    func keepFooter() {
        let feed = SettingsPageModel.Row.maxFeedEpisodes
        let history = SettingsPageModel.Row.maxHistoryEpisodes
        let counts = [feed: 120, history: 101]
        #expect(SettingsPageModel.keepFooter(pendingLimits: [:], counts: counts) == "Older ones are removed automatically.")
        #expect(SettingsPageModel.keepFooter(pendingLimits: [feed: 100], counts: counts)
            == "20 oldest episodes leave the Inbox when you close Settings.")
        #expect(SettingsPageModel.keepFooter(pendingLimits: [history: 100], counts: counts)
            == "Oldest episode leaves History when you close Settings.")
        #expect(SettingsPageModel.keepFooter(pendingLimits: [history: 100, feed: 100], counts: counts)
            == "20 oldest episodes leave the Inbox when you close Settings.\nOldest episode leaves History when you close Settings.")
        // A raised limit, or an unread count, has nothing to announce.
        #expect(SettingsPageModel.keepFooter(pendingLimits: [feed: 300], counts: counts)
            == "Older ones are removed automatically.")
        #expect(SettingsPageModel.keepFooter(pendingLimits: [feed: 50], counts: [:])
            == "Older ones are removed automatically.")
    }

    @Test("Limit draft holds steps, steps back to cancel, and clamps")
    func limitDraft() throws {
        let choices = try #require(SettingsPageModel.stepperChoices(for: .maxHistoryEpisodes))
        let stored = choices[choices.count / 2]
        var draft = SettingsPageModel.LimitDraft(stored: stored)
        #expect(draft.shown == stored)
        #expect(draft.pending == nil)

        draft.step(.decrease, in: choices)
        let lower = choices[choices.count / 2 - 1]
        #expect(draft.shown == lower)
        #expect(draft.pending == lower)
        #expect(draft.stored == stored, "stepping never changes the stored value")

        draft.step(.increase, in: choices)
        #expect(draft.shown == stored)
        #expect(draft.pending == nil, "stepping back to the stored value drops the held change")

        draft.step(.increase, in: choices)
        #expect(draft.pending == choices[choices.count / 2 + 1], "raising is held too")

        var floor = SettingsPageModel.LimitDraft(stored: choices[0])
        floor.step(.decrease, in: choices)
        #expect(floor.pending == nil, "no step below the smallest choice")
        #expect(SettingsPageModel.LimitDraft(stored: stored, pending: stored).pending == nil)
    }

    // MARK: - Deep links

    @Test("Contact mailto mirrors the shipped recipient quirk; privacy URLs exact")
    func deepLinks() {
        #expect(SettingsPageModel.feedbackMailtoURL.absoluteString
            == "mailto:kindjeffcom@gmail.com?subject=Anycast%20Feedback")
        #expect(SettingsPageModel.feedbackAddress == "kindjeffcom@gmail.com")
        #expect(SettingsPageModel.feedbackSubject == "Anycast Feedback")
        #expect(SettingsPageModel.privacyPolicyURL.absoluteString == "https://privacy.anycast.website")
        #expect(SettingsPageModel.termsOfUseURL.absoluteString
            == "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")
    }

    @Test("Feedback body ends with the diagnostics block; version line")
    func feedbackBody() {
        let body = SettingsPageModel.feedbackBody(
            appVersion: "1.4.0", build: "57", systemVersion: "27.0", deviceModel: "iPhone17,1"
        )
        #expect(body.hasPrefix("\n\n---\n"))
        #expect(body.hasSuffix("---\nAnycast 1.4.0 (57)\niOS 27.0\niPhone17,1"))
        #expect(SettingsPageModel.versionLine(appVersion: "1.4.0", build: "57") == "Anycast 1.4.0 (57)")
    }
}
