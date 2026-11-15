import Foundation

/// LRC rendering, byte-pinned by G3.
public enum LRC {

    /// formatLrcTime (formatters.dart:234-239): seconds → `mm:ss.mmm` with
    /// floor() on each part (positive inputs only in practice).
    public static func formatTime(_ time: Double) -> String {
        let minutes = Int((time / 60).rounded(.down))
        let seconds = Int(time.truncatingRemainder(dividingBy: 60).rounded(.down))
        let milliseconds = Int((time * 1000).truncatingRemainder(dividingBy: 1000).rounded(.down))
        return String(format: "%02d:%02d.%03d", minutes, seconds, milliseconds)
    }

    /// SubtitleModel.toLrc / TranslationModel.toLrc: two lines per segment —
    /// `[mm:ss.mmm]text` then the bare end timestamp; empty/'null' payloads
    /// render as ''. A nil text interpolates as the literal "null" in Dart
    /// string interpolation — kept byte-identical. Segments missing
    /// start/end force-unwrap-crash in Dart; skipped here (K4/K5 family).
    public static func render(segments: [SubtitleSegment]) -> String {
        var lrc = ""
        for segment in segments {
            guard let start = segment.start, let end = segment.end else { continue }
            lrc += "[\(formatTime(start))]\(segment.text ?? "null")\n"
            lrc += "[\(formatTime(end))]\n"
        }
        return lrc
    }

    /// The `toLrc` entry over a raw stored JSON column.
    public static func render(rawJSON: String?) -> String {
        guard let rawJSON, !rawJSON.isEmpty, rawJSON != "null",
              let data = rawJSON.data(using: .utf8),
              let segments = try? JSONDecoder().decode([SubtitleSegment].self, from: data)
        else { return "" }
        return render(segments: segments)
    }
}

/// Exported transcript assembly (pages/player.dart, G4). Byte-identical
/// output including the file name subject (which is ALSO the exported file
/// name — sanitize on write is the K29 fix, applied at the file-system edge,
/// never to the text itself).
public enum ExportText {

    /// `title - channelTitle`, plain `title` without a channel, "Subtitle"
    /// for untitled episodes.
    public static func deriveSubject(title: String?, channelTitle: String?) -> String {
        let title = title ?? "Subtitle"
        let channelTitle = channelTitle ?? ""
        if channelTitle.isEmpty { return title }
        return "\(title) - \(channelTitle)"
    }

    public static func build(
        title: String?,
        channelTitle: String?,
        mainLyric: String,
        translationLyric: String?
    ) -> String {
        let subject = deriveSubject(title: title, channelTitle: channelTitle)
        var buffer = "# \(subject)\n\n---\n\n"
        buffer += mainLyric + "\n"
        if let translationLyric, !translationLyric.isEmpty {
            buffer += "\n--- Translation ---\n\n" + translationLyric + "\n"
        }
        return buffer
    }

    /// K29: the exported file name must survive characters illegal in file
    /// names. Replacement keeps the visual shape; the share subject stays
    /// untouched.
    public static func sanitizedFileName(fromSubject subject: String) -> String {
        let illegal = CharacterSet(charactersIn: "/\\?%*|\"<>:")
        return subject.components(separatedBy: illegal).joined(separator: " ")
    }
}
