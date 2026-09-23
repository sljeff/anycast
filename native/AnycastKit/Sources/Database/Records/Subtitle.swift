import Foundation
import GRDB

// MARK: - subtitle

/// One timed line of a transcript/translation. Stored as a JSON array in the
/// `subtitle`/`translation` TEXT column: `{"start": seconds, "end": seconds,
/// "text": string}` — seconds are doubles (docs/migration/01 §1 table 7/9).
public struct SubtitleSegment: Codable, Sendable, Equatable {
    public var start: Double?
    public var end: Double?
    public var text: String?

    public init(start: Double? = nil, end: Double? = nil, text: String? = nil) {
        self.start = start
        self.end = end
        self.text = text
    }
}

public struct SubtitleRow: Codable, Sendable, Equatable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "subtitle"
    public var id: Int64?
    public var enclosureUrl: String?
    public var status: String?
    /// JSON array of segments — kept raw on the row; decode via `segments`.
    public var subtitle: String?
    public var language: String?
    /// Built by the creator, never written (always NULL in shipped data).
    public var summary: String?

    public init(id: Int64? = nil, enclosureUrl: String? = nil, status: String? = nil,
                subtitle: String? = nil, language: String? = nil, summary: String? = nil) {
        self.id = id
        self.enclosureUrl = enclosureUrl
        self.status = status
        self.subtitle = subtitle
        self.language = language
        self.summary = summary
    }

    public var segments: [SubtitleSegment]? {
        guard let subtitle, !subtitle.isEmpty, subtitle != "null",
              let data = subtitle.data(using: .utf8)
        else { return nil }
        return try? JSONDecoder().decode([SubtitleSegment].self, from: data)
    }
}

extension SubtitleSegment {
    /// JSON encoding used when persisting subtitle/translation payloads.
    ///
    /// Byte-parity with Dart `jsonEncode` is a write-back requirement, not
    /// cosmetics: Dart writes whole doubles as `130.0`, and a rolled-back
    /// Flutter build reading `130` gets an `int` where a `double` is
    /// expected — a runtime TypeError (docs/migration/05 §2.4). Key order
    /// matches the Dart map literal (start, end, text); non-ASCII stays raw
    /// UTF-8 like Dart's encoder.
    public static func encode(_ segments: [SubtitleSegment]) -> String {
        let parts = segments.map { segment -> String in
            var fields: [String] = []
            if let start = segment.start {
                fields.append("\"start\":\(dartDouble(start))")
            }
            if let end = segment.end {
                fields.append("\"end\":\(dartDouble(end))")
            }
            if let text = segment.text {
                fields.append("\"text\":\(dartString(text))")
            }
            return "{\(fields.joined(separator: ","))}"
        }
        return "[\(parts.joined(separator: ","))]"
    }

    /// Dart `double.toString()`: integral values keep a trailing `.0`;
    /// otherwise the shortest round-trip form (same family of algorithm as
    /// Swift's default `String(Double)`).
    private static func dartDouble(_ value: Double) -> String {
        if value.isNaN || value.isInfinite {
            // jsonEncode throws on these in Dart; we never persist them.
            return "0.0"
        }
        if value == value.rounded(), abs(value) < 1e15 {
            return String(format: "%.1f", value)
        }
        return String(value)
    }

    /// JSON string escaping matching Dart's encoder: quotes, backslash and
    /// control characters escaped; everything else (including non-ASCII and
    /// `/`) emitted raw.
    private static func dartString(_ value: String) -> String {
        var out = "\""
        for scalar in value.unicodeScalars {
            switch scalar {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case "\n": out += "\\n"
            case "\r": out += "\\r"
            case "\t": out += "\\t"
            default:
                if scalar.value < 0x20 {
                    out += String(format: "\\u%04x", scalar.value)
                } else {
                    out.unicodeScalars.append(scalar)
                }
            }
        }
        return out + "\""
    }
}
