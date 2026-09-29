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

    /// Plain date for Detail rows (formatDate: `M-d` / `y-M-d`).
    static func formatDate(_ timestampMilliseconds: Int64, now: Date = Date()) -> String {
        let nowMilliseconds = Int64(now.timeIntervalSince1970 * 1000)
        return TimeFormats.formatDate(timestampMilliseconds, nowEpochMilliseconds: nowMilliseconds)
    }
}
