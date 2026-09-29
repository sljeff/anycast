import Foundation

/// One rendered lyric line: a start timestamp, the main text, and the
/// translation aligned by exact millisecond (flutter_lyric `LyricLine`).
struct LyricLine: Equatable {
    let startMilliseconds: Int
    let text: String
    let translation: String?
}

/// Port of the flutter_lyric 3.0.2 LRC path used by the player
/// (core/lyric_parse.dart `LrcParser` + core/lyric_controller.dart
/// `getIndexByProgress`). The Dart app feeds `SubtitleModel.toLrc()` /
/// `TranslationModel.toLrc()` strings in, so this parser is pinned to that
/// grammar:
/// - a line may carry one or more `[mm:ss(.fff)?]` stamps; the stamps are
///   stripped and the remainder is the text;
/// - a leading `[tag:value]` (non-digit tag) is an ID tag, not a line;
/// - translation lines are collected into a ms → text map first, skipping
///   empty and `//` texts; a main line's translation is the EXACT-ms map
///   lookup (no tolerance — the QRC tolerance path never runs for LRC);
/// - lines are sorted by start ascending;
/// - the main LRC's bare `[end]` spacer lines stay in the model as
///   empty-text lines (the Dart render keeps them as blank rows).
enum LyricDocument {

    static func parse(mainLRC: String, translationLRC: String?) -> [LyricLine] {
        let translationMap = extractTranslationMap(translationLRC)

        var lines: [LyricLine] = []
        for rawLine in mainLRC.split(separator: "\n", omittingEmptySubsequences: false).map(String.init) {
            if Self.isIDTagLine(rawLine) { continue }
            guard let extracted = extractStamps(rawLine) else { continue }
            for milliseconds in extracted.stamps {
                lines.append(LyricLine(
                    startMilliseconds: milliseconds,
                    text: extracted.text,
                    translation: translationMap[milliseconds]
                ))
            }
        }
        return lines.sorted { $0.startMilliseconds < $1.startMilliseconds }
    }

    /// `getIndexByProgress`: binary search for the last line whose start is
    /// <= position; before the first line (or empty model) the answer is 0.
    static func activeLineIndex(lines: [LyricLine], positionMilliseconds: Int) -> Int {
        guard !lines.isEmpty else { return 0 }
        var left = 0
        var right = lines.count - 1
        var result = -1
        while left <= right {
            let mid = left + ((right - left) >> 1)
            let start = lines[mid].startMilliseconds
            if positionMilliseconds == start {
                return mid
            } else if positionMilliseconds < start {
                right = mid - 1
            } else {
                result = mid
                left = mid + 1
            }
        }
        return result < 0 ? 0 : result
    }

    // MARK: - Parsing internals (Dart LrcParser)

    /// `^\[(\D*?):(.*?)\]` — a leading tag whose name holds no digits.
    private static func isIDTagLine(_ line: String) -> Bool {
        guard let tagExpression else { return false }
        return tagExpression.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) != nil
    }

    /// `\[(\d{1,}):(\d{2})(?:\.(\d{1,}))?\]` — all stamps of one line.
    private static func extractStamps(_ line: String) -> (stamps: [Int], text: String)? {
        guard let regularExpression else { return nil }
        let nsLine = line as NSString
        let matches = regularExpression.matches(in: line, range: NSRange(location: 0, length: nsLine.length))
        guard !matches.isEmpty else { return nil }

        var stamps: [Int] = []
        var removedRanges: [NSRange] = []
        for match in matches {
            // Dart int.parse: minutes may exceed 59 (Duration overflows);
            // garbage would throw there and crash — here it drops the stamp.
            guard let minutes = Int(nsLine.substring(with: match.range(at: 1))),
                  let seconds = Int(nsLine.substring(with: match.range(at: 2)))
            else { continue }
            var fraction = match.range(at: 3).location == NSNotFound
                ? "0"
                : nsLine.substring(with: match.range(at: 3))
            if fraction.count > 3 { fraction = String(fraction.prefix(3)) }
            while fraction.count < 3 { fraction += "0" }
            let milliseconds = Int(fraction) ?? 0
            stamps.append(minutes * 60_000 + seconds * 1_000 + milliseconds)
            removedRanges.append(match.range)
        }
        guard !stamps.isEmpty else { return nil }

        var text = line
        // Dart removes each matched token via replaceAll — same set of
        // ranges, applied from the back to keep indices stable.
        for range in removedRanges.sorted(by: { $0.location > $1.location }) {
            if let swiftRange = Range(range, in: text) {
                text.removeSubrange(swiftRange)
            }
        }
        return (stamps, text)
    }

    /// `extractTranslationMap`: ms → text, skipping `""` and `"//"`.
    private static func extractTranslationMap(_ lrc: String?) -> [Int: String] {
        guard let lrc else { return [:] }
        var map: [Int: String] = [:]
        for rawLine in lrc.split(separator: "\n", omittingEmptySubsequences: false).map(String.init) {
            guard let extracted = extractStamps(rawLine) else { continue }
            guard !["", "//"].contains(extracted.text) else { continue }
            for stamp in extracted.stamps {
                map[stamp] = extracted.text
            }
        }
        return map
    }

    private static let tagExpression = try? NSRegularExpression(
        pattern: #"^\[(\D*?):(.*?)\]"#
    )

    private static let regularExpression = try? NSRegularExpression(
        pattern: #"\[(\d{1,}):(\d{2})(?:\.(\d{1,}))?\]"#
    )
}
