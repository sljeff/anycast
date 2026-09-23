import Foundation

/// Settings value codec (G9): the `autoSleepTimer` CSV, the 7 speed steps,
/// the countdown ladder, the 11 translation languages and the 49-country
/// whitelist — mirrored from pages/settings.dart so pickers and defaults
/// stay byte-compatible.
public enum SettingsCodec {

    /// Player speed slider: 0.5…2.0, 7 positions (divisions: 6).
    public static let speedSteps: [Double] = [0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0]

    /// Countdown slider: index → minutes (0 = OFF).
    public static let countdownMinutes: [Int] = [0, 10, 20, 30, 40, 50, 60]

    /// autoRefreshInterval picker: minutes × 60 (G9).
    public static let autoRefreshChoicesSeconds: [Int64] = [60, 180, 300, 600, 1800]

    /// Feed/history cap pickers (G9).
    public static let maxEpisodesChoices: [Int64] = [50, 100, 200, 300]

    public static let targetLanguages: [(name: String, code: String)] = [
        ("English", "en"), ("Français", "fr"), ("Deutsch", "de"), ("Español", "es"),
        ("Italiano", "it"), ("日本語", "ja"), ("中文", "zh"), ("Portugues", "pt"),
        ("Nederlands", "nl"), ("українська", "uk"), ("Pусский", "ru"),
    ]

    public static let countries: [(name: String, code: String)] = [
        ("Argentina", "AR"), ("Australia", "AU"), ("Österreich", "AT"),
        ("Bangladesh", "BD"), ("België / Belgique", "BE"), ("Brasil", "BR"),
        ("Canada", "CA"), ("Schweiz", "CH"), ("Chile", "CL"), ("中国", "CN"),
        ("Colombia", "CO"), ("Česká republika", "CZ"), ("Deutschland", "DE"),
        ("Danmark", "DK"), ("مصر", "EG"), ("España", "ES"), ("Suomi", "FI"),
        ("France", "FR"), ("United Kingdom", "GB"), ("Ελλάδα", "GR"),
        ("Magyarország", "HU"), ("Indonesia", "ID"), ("Ireland", "IE"),
        ("Israel", "IL"), ("India", "IN"), ("Italia", "IT"), ("日本", "JP"),
        ("대한민국", "KR"), ("México", "MX"), ("Malaysia", "MY"),
        ("Nigeria", "NG"), ("Nederland", "NL"), ("Norge", "NO"),
        ("New Zealand", "NZ"), ("Pakistan", "PK"), ("Polska", "PL"),
        ("Philippines", "PH"), ("Portugal", "PT"), ("România", "RO"),
        ("Россия", "RU"), ("Saudi Arabia", "SA"), ("Sverige", "SE"),
        ("Singapore", "SG"), ("ประเทศไทย", "TH"), ("Türkiye", "TR"),
        ("Україна", "UA"), ("United States", "US"), ("Việt Nam", "VN"),
        ("South Africa", "ZA"),
    ]

    /// `"startHour,endHour,minsIndex"` — hours are 0–23 indices, the tail is
    /// an INDEX into countdownMinutes (never the minutes value itself).
    public static func encodeAutoSleepTimer(startHour: Int, endHour: Int, minsIndex: Int) -> String {
        "\(startHour),\(endHour),\(minsIndex)"
    }

    public static func decodeAutoSleepTimer(_ csv: String) -> (startHour: Int, endHour: Int, minsIndex: Int)? {
        let parts = csv.split(separator: ",", omittingEmptySubsequences: false)
        guard parts.count == 3,
              let start = Int(parts[0]),
              let end = Int(parts[1]),
              let index = Int(parts[2])
        else { return nil }
        return (start, end, index)
    }

    /// Index → minutes (nil when out of range).
    public static func countdownMinutes(at index: Int) -> Int? {
        guard SettingsCodec.countdownMinutes.indices.contains(index) else { return nil }
        return SettingsCodec.countdownMinutes[index]
    }
}
