import Foundation
import AnycastKit

/// UI-facing relative-time helper with G10 golden semantics. AnycastKit's
/// `TimeFormats.formatDatetime(_:nowEpochMilliseconds:)` already ports
/// `timeago` en_short with the "now" → "just now" special case and the
/// 7-day/`M-d`/`y-M-d` routing (utils/formatters.dart formatDatetime,
/// pinned by G10) — this wrapper only supplies the UI's default clock.
nonisolated enum RelativeTimeFormatter {

    /// Formats a Unix-millisecond pubDate for card rows
    /// ("5m ago", "just now", "9-18", "2020-5-15").
    static func format(_ timestampMilliseconds: Int64, now: Date = Date()) -> String {
        let nowMilliseconds = Int64(now.timeIntervalSince1970 * 1000)
        return TimeFormats.formatDatetime(timestampMilliseconds, nowEpochMilliseconds: nowMilliseconds)
    }

    /// The shared episode meta line, "{relative date} · {duration}"
    /// ("4d ago · 30m"). Either part is dropped when unknown: no pubDate →
    /// duration only, zero/unknown duration → date only.
    static func dateAndDuration(
        pubDateMilliseconds: Int64?, durationMilliseconds: Int64?, now: Date = Date()
    ) -> String {
        var parts: [String] = []
        if let pubDateMilliseconds { parts.append(format(pubDateMilliseconds, now: now)) }
        if let durationMilliseconds, durationMilliseconds > 0 {
            parts.append(TimeFormats.formatDuration(durationMilliseconds))
        }
        return parts.joined(separator: " · ")
    }
}
