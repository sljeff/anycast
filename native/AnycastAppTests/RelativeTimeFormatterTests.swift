import UIKit
import Testing
import Foundation
@testable import Anycast

/// RelativeTimeFormatter golden parity — the G10 expectations read straight
/// from test/golden/G10_time_formats.json with the exporter's pinned
/// reference instant injected (the golden's own note: "native side must
/// inject the same instant"). Timestamp construction mirrors the L1 suite
/// (midday UTC so calendar-day drift across runner timezones cannot flip a
/// branch).
struct RelativeTimeFormatterTests {

    struct G10 {
        var reference_now_ms: Int64
        var formatDatetime: [String: String]
        var formatDate: [String: String]
    }

    /// JSONSerialization, not Codable: the golden table carries non-string
    /// probes (`just_now_is_special_cased: true`) that break a strict decode
    /// (same lesson as the L1 suite).
    static func loadGolden() throws -> G10 {
        let data = try Data(contentsOf: TestRepoAssets.golden("G10_time_formats.json"))
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        func strings(_ key: String) -> [String: String] {
            (object[key] as? [String: Any])?.compactMapValues { $0 as? String } ?? [:]
        }
        return G10(
            reference_now_ms: (object["reference_now_ms"] as? NSNumber)?.int64Value ?? 0,
            formatDatetime: strings("formatDatetime"),
            formatDate: strings("formatDate")
        )
    }

    static func utcMilliseconds(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 12, _ min: Int = 30) -> Int64 {
        var calendar = Foundation.Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let date = calendar.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
        return Int64(date.timeIntervalSince1970 * 1000)
    }

    @Test("formatDatetime matches the G10 golden table")
    func formatDatetimeGolden() throws {
        let golden = try Self.loadGolden()
        let now = Date(timeIntervalSince1970: TimeInterval(golden.reference_now_ms) / 1000)

        var calendar = Foundation.Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let referenceYear = calendar.component(.year, from: now)

        let cases: [(key: String, ts: Int64)] = [
            ("past_2020", Self.utcMilliseconds(2020, 5, 15)),
            ("future_2030", Self.utcMilliseconds(2030, 1, 2, 3, 4)),
            ("this_year_jan", Self.utcMilliseconds(referenceYear, 1, 5)),
            ("last_year", Self.utcMilliseconds(referenceYear - 1, 6, 15)),
        ]
        for testCase in cases {
            let formatted = RelativeTimeFormatter.format(testCase.ts, now: now)
            #expect(
                formatted == golden.formatDatetime[testCase.key],
                "\(testCase.key): got \(formatted), want \(golden.formatDatetime[testCase.key] ?? "?")"
            )
        }
        // "now" special case → "just now".
        #expect(RelativeTimeFormatter.format(golden.reference_now_ms, now: now) == "just now")
    }

    @Test("formatDate matches the G10 golden table")
    func formatDateGolden() throws {
        let golden = try Self.loadGolden()
        let now = Date(timeIntervalSince1970: TimeInterval(golden.reference_now_ms) / 1000)
        var calendar = Foundation.Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let referenceYear = calendar.component(.year, from: now)

        #expect(
            RelativeTimeFormatter.formatDate(Self.utcMilliseconds(2020, 5, 15), now: now)
                == golden.formatDate["past_2020"]
        )
        #expect(
            RelativeTimeFormatter.formatDate(Self.utcMilliseconds(referenceYear, 1, 5), now: now)
                == golden.formatDate["this_year"]
        )
    }

    @Test("timeago en_short ladder spot checks")
    func ladder() {
        let nowMs: Int64 = 1_800_000_000_000
        let now = Date(timeIntervalSince1970: TimeInterval(nowMs) / 1000)
        func secondsAgo(_ s: Int) -> Int64 { nowMs - Int64(s) * 1000 }
        // "<45s → just now"; "45s–90s → 1m ago"; "5m"; "45-90m → ~1h".
        #expect(RelativeTimeFormatter.format(secondsAgo(10), now: now) == "just now")
        #expect(RelativeTimeFormatter.format(secondsAgo(60), now: now) == "1m ago")
        #expect(RelativeTimeFormatter.format(secondsAgo(5 * 60), now: now) == "5m ago")
        #expect(RelativeTimeFormatter.format(secondsAgo(47 * 60), now: now) == "~1h ago")
        #expect(RelativeTimeFormatter.format(secondsAgo(5 * 3600), now: now) == "5h ago")
    }
}
