import Foundation

/// `timeago` 3.7.1 with the `en_short` message set, ported message-for-message
/// (docs/migration/05 K22: the English short strings stay exactly as shipped).
/// The threshold ladder is timeago's own (lib/src/timeago.dart), including
/// its half-away-from-zero rounding.
public enum TimeAgo {

    /// - Parameters:
    ///   - dateEpochMilliseconds: the timestamp being described.
    ///   - clockEpochMilliseconds: "now" — injectable so golden tests pin the
    ///     same reference instant the exporter used.
    public static func format(
        dateEpochMilliseconds: Int64,
        clockEpochMilliseconds: Int64
    ) -> String {
        var elapsed = clockEpochMilliseconds - dateEpochMilliseconds

        // allowFromNow is false in the shipped call site: a future date keeps
        // its negative elapsed and lands in the <45 s branch ("now").
        let allowFromNow = false
        var prefix = ""
        var suffix = ""
        if allowFromNow && elapsed < 0 {
            elapsed = abs(elapsed)
        } else {
            prefix = ""    // en_short prefixAgo
            suffix = ""    // en_short suffixAgo
        }
        _ = prefix
        _ = suffix

        let seconds = Double(elapsed) / 1000
        let minutes = seconds / 60
        let hours = minutes / 60
        let days = hours / 24
        let months = days / 30
        let years = days / 365

        func roundHalfAwayFromZero(_ value: Double) -> Int {
            value < 0 ? Int((value - 0.5).rounded(.up)) : Int((value + 0.5).rounded(.down))
        }

        let result: String
        if seconds < 45 {
            result = "now"                                   // lessThanOneMinute
        } else if seconds < 90 {
            result = "1m"                                    // aboutAMinute
        } else if minutes < 45 {
            result = "\(roundHalfAwayFromZero(minutes))m"
        } else if minutes < 90 {
            result = "~1h"                                   // aboutAnHour
        } else if hours < 24 {
            result = "\(roundHalfAwayFromZero(hours))h"
        } else if hours < 48 {
            result = "~1d"                                   // aDay
        } else if days < 30 {
            result = "\(roundHalfAwayFromZero(days))d"
        } else if days < 60 {
            result = "~1mo"                                  // aboutAMonth
        } else if days < 365 {
            result = "\(roundHalfAwayFromZero(months))mo"
        } else if years < 2 {
            result = "~1y"                                   // aboutAYear
        } else {
            result = "\(roundHalfAwayFromZero(years))y"
        }
        return result
    }
}

/// The formatter family from utils/formatters.dart, pinned by G10. All
/// duration math uses Dart `Duration` integer semantics (truncating
/// `inMinutes`, `inHours`, and `remainder` — not floating point).
public enum TimeFormats {

    // MARK: Calendar display (local-time components, like Dart DateTime)

    /// formatDatetime: within 7 days → timeago en_short ("now" special-cased
    /// to "just now"); same year → `M-d`; else `y-M-d`.
    public static func formatDatetime(
        _ timestampMilliseconds: Int64,
        nowEpochMilliseconds: Int64
    ) -> String {
        let components = localComponents(timestampMilliseconds)
        let nowComponents = localComponents(nowEpochMilliseconds)

        if timestampMilliseconds > nowEpochMilliseconds - 7 * 86_400_000 {
            let ago = TimeAgo.format(
                dateEpochMilliseconds: timestampMilliseconds,
                clockEpochMilliseconds: nowEpochMilliseconds
            )
            return ago == "now" ? "just now" : "\(ago) ago"
        }
        if components.year == nowComponents.year {
            return "\(components.month)-\(components.day)"
        }
        return "\(components.year)-\(components.month)-\(components.day)"
    }

    /// formatDate: same year → `M-d`, else `y-M-d`.
    public static func formatDate(
        _ timestampMilliseconds: Int64,
        nowEpochMilliseconds: Int64
    ) -> String {
        let components = localComponents(timestampMilliseconds)
        let nowComponents = localComponents(nowEpochMilliseconds)
        if components.year == nowComponents.year {
            return "\(components.month)-\(components.day)"
        }
        return "\(components.year)-\(components.month)-\(components.day)"
    }

    private struct YMD {
        var year: Int, month: Int, day: Int
    }

    private static func localComponents(_ epochMilliseconds: Int64) -> YMD {
        let date = Date(timeIntervalSince1970: TimeInterval(epochMilliseconds) / 1000)
        var calendar = Foundation.Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        return YMD(
            year: calendar.component(.year, from: date),
            month: calendar.component(.month, from: date),
            day: calendar.component(.day, from: date)
        )
    }

    // MARK: Durations (milliseconds in, Dart Duration math out)

    private static func inMinutes(_ ms: Int64) -> Int64 { ms / 60_000 }
    private static func inSeconds(_ ms: Int64) -> Int64 { ms / 1000 }
    private static func inHours(_ ms: Int64) -> Int64 { ms / 3_600_000 }

    /// formatDuration: 0 → ""; <100 minutes → `{n}m`; else `{h}h {m}m`.
    public static func formatDuration(_ milliseconds: Int64) -> String {
        if milliseconds == 0 { return "" }
        if inMinutes(milliseconds) < 100 {
            return "\(inMinutes(milliseconds))m"
        }
        return "\(inHours(milliseconds))h \(inMinutes(milliseconds) % 60)m"
    }

    /// formatRemainingTime: clamped remaining; "… remaining" once playback
    /// has started. Zero total duration → "".
    public static func formatRemainingTime(
        durationMilliseconds: Int64,
        playedMilliseconds: Int64
    ) -> String {
        if inSeconds(durationMilliseconds) == 0 { return "" }
        var remaining = durationMilliseconds - playedMilliseconds
        if remaining < 0 { remaining = 0 }
        let remainingText: String
        if inMinutes(remaining) < 100 {
            remainingText = "\(inMinutes(remaining))m"
        } else {
            remainingText = "\(inHours(remaining))h \(inMinutes(remaining) % 60)m"
        }
        return inSeconds(playedMilliseconds) > 0 ? "\(remainingText) remaining" : remainingText
    }

    /// getPlayedAndTotalTime (models/playlist_episode.dart:160-164):
    /// `mm:ss / mm:ss` with unbounded minute counts (no hour rollover).
    public static func getPlayedAndTotalTime(
        playedMilliseconds: Int64,
        durationMilliseconds: Int64
    ) -> String {
        func clock(_ ms: Int64) -> String {
            let minutes = inMinutes(ms)
            let seconds = inSeconds(ms) % 60
            return "\(minutes):\(String(format: "%02d", seconds))"
        }
        return "\(clock(playedMilliseconds)) / \(clock(durationMilliseconds))"
    }

    /// formatCountdown: ≤0 → "OFF"; exactly 60 minutes → "1h"; else the
    /// minute-remainder clock `mm:ss`.
    public static func formatCountdown(_ milliseconds: Int64) -> String {
        if inSeconds(milliseconds) <= 0 { return "OFF" }
        if inMinutes(milliseconds) == 60 { return "1h" }
        let minutes = inMinutes(milliseconds) % 60
        let seconds = inSeconds(milliseconds) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    /// formatTime: `hh:mm:ss` — hours are `inHours % 60` in the original
    /// (a quirk; ported as-is).
    public static func formatTime(_ milliseconds: Int64) -> String {
        let hours = inHours(milliseconds) % 60
        let minutes = inMinutes(milliseconds) % 60
        let seconds = inSeconds(milliseconds) % 60
        return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
    }

    /// urlToDomain: Uri.host; unparseable URLs yield "" (the K4 crash family
    /// fix: never throw).
    public static func urlToDomain(_ url: String) -> String {
        URL(string: url)?.host ?? ""
    }
}
