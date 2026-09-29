import Foundation
import Testing
import AnycastKit
@testable import Anycast

/// T7 settings page model parity (05 §6.1 S16 / 03 §2.13): group/row
/// structure, row copy, tooltip fixtures, option lists, locale derivation,
/// and the deep links — asserted against data so the fixtures are
/// independent of the live UI.
@MainActor
struct SettingsPageModelTests {

    // MARK: - Group / row order parity (settings.dart:110-475)

    @Test("Sections and rows mirror the Dart ListView order")
    func sectionRowOrder() {
        let off = SettingsPageModel.sections(includeTargetLanguage: false)
        #expect(off.map(\.header) == [
            nil, "Transcript & Translation", "Podcast", "Other", "Contact", nil,
        ])
        #expect(off.map(\.rows) == [
            [.account],
            [.country, .enableTranslation],
            [.importExport, .history],
            [.autoRefreshInterval, .maxFeedEpisodes, .maxHistoryEpisodes],
            [.contactEmail],
            [.privacyPolicy, .termsOfUse],
        ])
        // Only the trailing privacy links render outside a group card.
        #expect(off.map(\.plainStyle) == [false, false, false, false, false, true])

        let on = SettingsPageModel.sections(includeTargetLanguage: true)
        #expect(on[1].rows == [.country, .enableTranslation, .targetLanguage])
    }

    @Test("Target language row gates on a non-empty language (settings.dart:239)")
    func languageVisibilityGating() {
        #expect(SettingsPageModel.showsTargetLanguage(targetLanguage: "") == false)
        #expect(SettingsPageModel.showsTargetLanguage(targetLanguage: "ja") == true)
    }

    @Test("Row labels match the Dart copy verbatim")
    func rowLabels() {
        let expected: [SettingsPageModel.Row: String] = [
            .account: "Account",
            .country: "Country",
            .enableTranslation: "Enable Transcript Translation",
            .targetLanguage: "Target Language",
            .importExport: "Import / Export",
            .history: "History",
            .autoRefreshInterval: "Auto Refresh Interval",
            .maxFeedEpisodes: "Max Episodes in Inbox",
            .maxHistoryEpisodes: "Max Episodes in History",
            .contactEmail: "kindjeff.com@gmail.com",
            .privacyPolicy: "Privacy Policy",
            .termsOfUse: "Terms of Use (EULA)",
        ]
        for (row, title) in expected {
            #expect(SettingsPageModel.title(for: row) == title)
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
            .account, .enableTranslation, .importExport, .history,
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
        #expect(SettingsPageModel.contactEmailDisplay == "kindjeff.com@gmail.com")
        #expect(SettingsPageModel.feedbackMailtoURL.absoluteString
            == "mailto:kindjeffcom@gmail.com?subject=Anycast%20Feedback")
        #expect(SettingsPageModel.privacyPolicyURL.absoluteString == "https://privacy.anycast.website")
        #expect(SettingsPageModel.termsOfUseURL.absoluteString
            == "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")
        #expect(SettingsPageModel.optionSheetTitle == "Select Country")
    }
}
