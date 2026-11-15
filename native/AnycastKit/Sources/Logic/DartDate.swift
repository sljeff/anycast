import Foundation

/// Dart `DateTime.parse` port (SDK `date.dart` regex semantics) plus the
/// epoch-ms conventions shared with the shipped database. Needed because
/// several golden families pin exact epoch values for ISO strings
/// (G7 weird dates, G11 expired_at) and Dart's parser is more permissive
/// than `ISO8601DateFormatter`.
public enum DartDate {

    /// Seconds in the linear day arithmetic below.
    private static let secondsPerDay: Int64 = 86_400

    /// Mirrors DateTime.parse: `YYYY-MM-DD` (compact forms allowed), optional
    /// `T`/space time with cascade-optional components, optional fractional
    /// seconds (`.` or `,`), optional timezone (`Z`/`z` or ±HH[:MM]).
    /// Strings without a timezone resolve to LOCAL time (Dart behavior).
    /// Returns epoch milliseconds.
    public static func parseToEpochMilliseconds(_ input: String) -> Int64? {
        let pattern = #"^([+-]?\d{4,})?-?(\d\d)?-?(\d\d)?(?:[ T](\d\d)(?::?(\d\d)(?::?(\d\d)(?:[.,](\d+))?)?)?( ?[zZ]| ?([-+])(\d\d)(?::?(\d\d))?)?)?$"#
        guard let match = input.firstMatch(of: try! NSRegularExpression(pattern: pattern)) else {
            return nil
        }

        func group(_ index: Int) -> String? {
            let range = match.range(at: index)
            guard range.location != NSNotFound, let swiftRange = Range(range, in: input) else {
                return nil
            }
            return String(input[swiftRange])
        }

        // A year is mandatory in practice: Dart requires either a full date or
        // accepts year alone; a completely empty match ("") is invalid.
        guard let yearString = group(1) else { return nil }

        var year = Int32(yearString) ?? 0
        if yearString.hasPrefix("-") || yearString.hasPrefix("+") {
            // sign already handled by Int32 parsing
        }

        let month = Int32(group(2) ?? "01") ?? 1
        let day = Int32(group(3) ?? "01") ?? 1
        let hour = Int32(group(4) ?? "0") ?? 0
        let minute = Int32(group(5) ?? "0") ?? 0
        let second = Int32(group(6) ?? "0") ?? 0

        // Fractional seconds truncate to milliseconds (Dart keeps
        // microseconds; every persisted value is whole milliseconds).
        var millisecond: Int32 = 0
        if let fraction = group(7) {
            let padded = (fraction + "000").prefix(3)
            millisecond = Int32(padded) ?? 0
        }

        // Timezone: explicit ±HH[:MM] offset, else 'z'/'Z', else local.
        // (Group 8 captures the WHOLE alternative — including the offset
        // text — so the sign group must be examined first.)
        var offsetSeconds: Int64 = 0
        var isLocal = true
        if let sign = group(9), let offsetHour = Int32(group(10) ?? "0"),
           let offsetMinute = Int32(group(11) ?? "0") {
            isLocal = false
            let magnitude = Int64(offsetHour) * 3600 + Int64(offsetMinute) * 60
            offsetSeconds = sign == "-" ? -magnitude : magnitude
        } else if group(8) != nil {
            isLocal = false // 'z'/'Z'
        }

        // Year adjustment: Dart's DateTime handles years from the raw string;
        // the sign is part of Int32 parsing above.
        if yearString.hasPrefix("+") { year = Int32(yearString.dropFirst()) ?? 0 }

        // Overflow rolls over exactly like the Dart DateTime constructor
        // (Feb 29 in a non-leap year lands on Mar 1 — pinned by G7's probe
        // of 'Mon, 29 Feb 2027 …').
        let days = daysFromCivil(year: year, month: month, day: day)
        let timeOfDay: Int64 = Int64(hour) * 3600 + Int64(minute) * 60 + Int64(second)
        var epochSeconds: Int64 = days * secondsPerDay
        epochSeconds += timeOfDay

        if isLocal {
            // Interpret the wall-clock fields in the current time zone.
            var calendar = Foundation.Calendar(identifier: .gregorian)
            calendar.timeZone = .current
            let components = DateComponents(year: Int(year), month: Int(month), day: Int(day),
                                            hour: Int(hour), minute: Int(minute), second: Int(second))
            guard let date = calendar.date(from: components) else { return nil }
            epochSeconds = Int64(date.timeIntervalSince1970.rounded())
            return Int64(date.timeIntervalSince1970 * 1000) + Int64(millisecond)
        }

        epochSeconds -= offsetSeconds
        return epochSeconds * 1000 + Int64(millisecond)
    }

    /// Howard Hinnant's `days_from_civil`: linear day count for a (possibly
    /// out-of-range) y/m/d triple — arithmetic (not lookup-table) so
    /// overflowing days/months roll forward naturally.
    private static func daysFromCivil(year yIn: Int32, month mIn: Int32, day d: Int32) -> Int64 {
        RSSDate.civilDays(year: Int64(yIn), month: Int64(mIn), day: Int64(d))
    }
}

/// RFC822 date parsing exactly as webfeed_plus does it (util/datetime.dart):
/// prefix-match `EEE, dd MMM yyyy HH:mm:ss` with intl's lenient en_US
/// weekday/month names, then interpret the LAST space-separated token as a
/// timezone via webfeed's abbreviation table or ±HH[MM] regex — an unknown
/// token silently means offset 0. Falls back to Dart ISO parsing. Both fail
/// → nil.
public enum RSSDate {

    private static let weekdayNames: Set<String> = [
        "Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat",
    ]

    private static let monthNumbers: [String: Int] = [
        "Jan": 1, "Feb": 2, "Mar": 3, "Apr": 4, "May": 5, "Jun": 6,
        "Jul": 7, "Aug": 8, "Sep": 9, "Oct": 10, "Nov": 11, "Dec": 12,
    ]

    /// webfeed_plus util/timezone.dart.
    private static let timeZoneAbbreviations: [String: Int] = [
        "EET": 120, "CET": 60, "GMT": 0, "AST": -240, "EST": -300, "EDT": -240,
        "CST": -360, "CDT": -300, "MST": -420, "MDT": -360, "PST": -480, "PDT": -420,
    ]

    /// webfeed's `parseDateTime`: RFC822 first, ISO8601 second.
    public static func parse(_ dateString: String?) -> Int64? {
        guard let dateString, !dateString.isEmpty else { return nil }
        return parseRFC822(dateString) ?? DartDate.parseToEpochMilliseconds(dateString)
    }

    static func parseRFC822(_ input: String) -> Int64? {
        // 'EEE, dd MMM yyyy HH:mm:ss' — prefix match, trailing text ignored.
        // intl parses field-by-field leniently: weekday/month must be valid
        // NAMES, numbers may overflow the calendar (rolled later), and the
        // case of the names matters. The year width is greedy: intl's `yyyy`
        // consumes the whole digit run (a typo'd 5-digit year like 20241
        // parses as that year — verified 2026-09-23); capped at 6 digits,
        // DateTime's largest representable year.
        let pattern = #"^([A-Za-z]{3}), (\d{1,2}) ([A-Za-z]{3}) (\d{1,6}) (\d{1,2}):(\d{1,2}):(\d{1,2})"#
        guard let match = input.firstMatch(of: try! NSRegularExpression(pattern: pattern)) else {
            return nil
        }
        let groups = (1...7).map { index in
            String(input[Range(match.range(at: index), in: input)!])
        }
        guard weekdayNames.contains(groups[0]),
              let month = monthNumbers[groups[2]]
        else { return nil }

        let day = Int32(groups[1]) ?? 0
        // intl lenient: a 2-digit year keeps its literal value (no windowing).
        let year = Int32(groups[3]) ?? 0
        let hour = Int32(groups[4]) ?? 0
        let minute = Int32(groups[5]) ?? 0
        let second = Int32(groups[6]) ?? 0

        // Timezone token = last space-separated chunk; unknown → 0.
        let offsetMinutes = timeZoneOffset(ofLastTokenIn: input) ?? 0

        // Lenient overflow rolls forward like the Dart DateTime constructor.
        let days = civilDays(year: Int64(year), month: Int64(month), day: Int64(day))
        let timeOfDay: Int64 = Int64(hour) * 3600 + Int64(minute) * 60 + Int64(second)
        let offset: Int64 = Int64(offsetMinutes) * 60
        let epochSeconds: Int64 = days * 86_400 + timeOfDay - offset
        return epochSeconds * 1000
    }

    /// ±HH[:MM] or an abbreviation; nil = unrecognized.
    static func timeZoneOffset(ofLastTokenIn input: String) -> Int? {
        let token = input.split(separator: " ").last.map(String.init) ?? ""
        if let known = timeZoneAbbreviations[token.uppercased()] {
            return known
        }
        let pattern = #"^([+-]?)(\d{2}):?(\d{2})$"#
        guard let match = token.firstMatch(of: try! NSRegularExpression(pattern: pattern)) else {
            return nil
        }
        let sign = String(token[Range(match.range(at: 1), in: token)!]) == "-" ? -1 : 1
        let hours = Int(token[Range(match.range(at: 2), in: token)!]) ?? 0
        let minutes = Int(token[Range(match.range(at: 3), in: token)!]) ?? 0
        return sign * (60 * hours + minutes)
    }

    /// All-Int64 civil-day arithmetic (Howard Hinnant's days_from_civil),
    /// shared by both parsers. Months outside 1…12 roll the year and days
    /// roll linearly — both mirror the Dart DateTime constructor's rollover
    /// (pinned by G7's 'Feb 29 2027' probe landing on Mar 1).
    static func civilDays(year yIn: Int64, month mIn: Int64, day dIn: Int64) -> Int64 {
        var y = yIn
        y += (mIn - 1) / 12
        let month = (mIn - 1) % 12 + 1   // normalized to 1…12
        if month <= 2 { y -= 1 }         // Jan/Feb belong to the prior era-year

        let era: Int64 = (y >= 0 ? y : y - 399) / 400
        let yoe: Int64 = y - era * 400   // [0, 399]
        let marchShifted: Int64 = month + (month > 2 ? -3 : 9)  // March = 0
        let doy: Int64 = (153 * marchShifted + 2) / 5 + dIn - 1  // [0, 365]
        let doe: Int64 = yoe * 365 + yoe / 4 - yoe / 100 + doy   // [0, 146096]
        return era * 146_097 + doe - 719_468
    }
}

extension String {
    /// Small regex helper (NSRegularExpression-backed) with named-capture-free
    /// group access.
    func firstMatch(of regex: NSRegularExpression) -> NSTextCheckingResult? {
        regex.firstMatch(in: self, range: NSRange(startIndex..., in: self))
    }
}
