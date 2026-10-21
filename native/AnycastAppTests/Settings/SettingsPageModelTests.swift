import Foundation
import Testing
import AnycastKit
@testable import Anycast

/// Settings page model (05 §6.1 S16 / 03 §2.13, restrained 2.0 Settings
/// direction 2026-10-21): group/row structure, row copy and trailing values,
/// tooltip fixtures, option lists, locale derivation, and the deep links —
/// asserted against data so the fixtures are independent of the live UI.
@MainActor
struct SettingsPageModelTests {

    // MARK: - Group / row order

    @Test("Sections and rows follow the 2.0 Settings grouping")
    func sectionRowOrder() {
        let sections = SettingsPageModel.sections()
        #expect(sections.map(\.header) == [
            nil, "Downloads & Storage", "Subtitles & Translation",
            "Content & Discovery", "Help", nil,
        ])
        #expect(sections.map(\.rows) == [
            [.account],
            [.cacheLimit],
            [.enableTranslation, .targetLanguage],
            [.country, .autoRefreshInterval, .maxFeedEpisodes,
             .maxHistoryEpisodes, .importExport, .history],
            [.contactEmail],
            [.privacyPolicy, .termsOfUse],
        ])
        // Only the trailing privacy links render outside a group plate.
        #expect(sections.map(\.plainStyle) == [false, false, false, false, false, true])
    }

    @Test("Translation is on while a target language is set (settings.dart:239)")
    func translationGating() {
        #expect(SettingsPageModel.showsTargetLanguage(targetLanguage: "") == false)
        #expect(SettingsPageModel.showsTargetLanguage(targetLanguage: "ja") == true)
    }

    @Test("Row identifiers stay stable for existing rows")
    func rowIdentifiers() {
        #expect(SettingsPageModel.identifier(for: .account) == "settings-row-account")
        #expect(SettingsPageModel.identifier(for: .country) == "settings-row-country")
        #expect(SettingsPageModel.identifier(for: .enableTranslation) == "settings-row-enableTranslation")
        #expect(SettingsPageModel.identifier(for: .autoRefreshInterval) == "settings-row-autoRefreshInterval")
        #expect(SettingsPageModel.identifier(for: .cacheLimit) == "settings-row-cacheLimit")
    }

    @Test("Row titles and the switch subtitle")
    func rowLabels() {
        let expected: [SettingsPageModel.Row: String] = [
            .account: "Account",
            .cacheLimit: "Cache Limit",
            .enableTranslation: "Subtitle Translation",
            .targetLanguage: "Target Language",
            .country: "Discovery Region",
            .autoRefreshInterval: "Auto Refresh",
            .maxFeedEpisodes: "Inbox Limit",
            .maxHistoryEpisodes: "History Limit",
            .importExport: "Import & Export",
            .history: "Listening History",
            .contactEmail: "Contact Us",
            .privacyPolicy: "Privacy Policy",
            .termsOfUse: "Terms of Use (EULA)",
        ]
        for (row, title) in expected {
            #expect(SettingsPageModel.title(for: row) == title)
        }
        #expect(SettingsPageModel.subtitle(for: .enableTranslation) == "Translate generated text")
        for row in expected.keys where row != .enableTranslation {
            #expect(SettingsPageModel.subtitle(for: row) == nil)
        }
    }

    @Test("Trailing values: stored value, 'Off' while translation is off, 'Email' on Contact Us")
    func trailingValues() {
        var settings = AppSettings.defaults(localeIdentifier: "en_US")
        settings.countryCode = "JP"
        settings.targetLanguage = "zh"
        settings.autoRefreshInterval = 300
        settings.maxFeedEpisodes = 200
        settings.maxHistoryEpisodes = 50
        settings.maxCacheCount = 20

        #expect(SettingsPageModel.value(for: .country, settings: settings) == "日本")
        #expect(SettingsPageModel.value(for: .targetLanguage, settings: settings) == "中文")
        #expect(SettingsPageModel.value(for: .autoRefreshInterval, settings: settings) == "5 min")
        #expect(SettingsPageModel.value(for: .maxFeedEpisodes, settings: settings) == "200 episodes")
        #expect(SettingsPageModel.value(for: .maxHistoryEpisodes, settings: settings) == "50 episodes")
        #expect(SettingsPageModel.value(for: .cacheLimit, settings: settings) == "20 episodes")
        #expect(SettingsPageModel.value(for: .contactEmail, settings: settings) == "Email")

        settings.targetLanguage = ""
        #expect(SettingsPageModel.value(for: .targetLanguage, settings: settings) == "Off")

        for row: SettingsPageModel.Row in [
            .account, .enableTranslation, .importExport, .history, .privacyPolicy, .termsOfUse,
        ] {
            #expect(SettingsPageModel.value(for: row, settings: settings) == nil)
        }
    }

    // MARK: - Tooltip copy fixtures (settings.dart:150/255/302/356/405)

    @Test("Info tooltips: exact Dart copy on the five rows, none elsewhere")
    func tooltipFixtures() {
        #expect(SettingsPageModel.tooltip(for: .country)
            == "Discover page will show episodes from this country.")
        #expect(SettingsPageModel.tooltip(for: .targetLanguage)
            == "Translates the podcast transcript into the target language.")
        #expect(SettingsPageModel.tooltip(for: .autoRefreshInterval)
            == "Automatically fetch new episodes every X minutes.")
        #expect(SettingsPageModel.tooltip(for: .maxFeedEpisodes)
            == "Limits the number of episodes in the inbox. Auto deleted if exceeded.")
        #expect(SettingsPageModel.tooltip(for: .maxHistoryEpisodes)
            == "Limits the number of episodes in the history. Auto deleted if exceeded.")

        let withoutTooltip: [SettingsPageModel.Row] = [
            .account, .cacheLimit, .enableTranslation, .importExport, .history,
            .contactEmail, .privacyPolicy, .termsOfUse,
        ]
        for row in withoutTooltip {
            #expect(SettingsPageModel.tooltip(for: row) == nil)
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

    @Test("Switch-on default language follows the G9 locale split")
    func defaultLanguageDerivation() {
        #expect(SettingsPageModel.defaultTargetLanguage(localeIdentifier: "zh_Hans_CN") == "zh")
        #expect(SettingsPageModel.defaultTargetLanguage(localeIdentifier: "zh-Hans-CN") == "zh")
        #expect(SettingsPageModel.defaultTargetLanguage(localeIdentifier: "en_US") == "en")
        #expect(SettingsPageModel.defaultTargetLanguage(localeIdentifier: "en-US") == "en")
        #expect(SettingsPageModel.defaultTargetLanguage(localeIdentifier: "en") == "en")
        #expect(SettingsPageModel.defaultTargetLanguage(localeIdentifier: "pt_BR") == "pt")
    }

    // MARK: - Deep links

    @Test("Contact mailto mirrors the shipped recipient quirk; privacy URLs exact")
    func deepLinks() {
        #expect(SettingsPageModel.feedbackMailtoURL.absoluteString
            == "mailto:kindjeffcom@gmail.com?subject=Anycast%20Feedback")
        #expect(SettingsPageModel.privacyPolicyURL.absoluteString == "https://privacy.anycast.website")
        #expect(SettingsPageModel.termsOfUseURL.absoluteString
            == "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")
    }
}
