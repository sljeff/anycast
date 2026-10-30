import UIKit

/// One chapter read from the show notes.
struct EpisodeChapter: Equatable {
    let startMilliseconds: Int
    let title: String
}

/// Chapters and seekable timestamps from an episode's show notes. Feeds
/// carry no chapter data we parse yet (`podcast:chapters` / PSC need the
/// feed side), so chapters come from notes lines that start with a
/// timestamp — "(00:26:23) Act Two: …". Fewer than two such lines, or
/// starts that do not ascend, mean no chapters.
enum EpisodeChapters {

    /// Link scheme for timestamps in the notes: `anycast-seek:<ms>`.
    static let seekScheme = "anycast-seek"

    /// `h:mm:ss` or `m:ss`, not part of a longer number or clock.
    private static let timestampPattern = #"(?<![\d:])(?:(\d{1,2}):)?([0-5]?\d):([0-5]\d)(?![\d:])"#
    private static let timestampRegex = try! NSRegularExpression(pattern: timestampPattern)
    /// A line that opens with a timestamp (optionally bracketed) and has a
    /// title after an optional separator.
    private static let chapterLineRegex = try! NSRegularExpression(
        pattern: #"^\s*[\(\[]?("# + timestampPattern + #")[\)\]]?\s*[-–—:|·.]?\s*(\S.*?)\s*$"#,
        options: [.anchorsMatchLines]
    )

    static func parse(plainText: String) -> [EpisodeChapter] {
        let text = plainText as NSString
        var chapters: [EpisodeChapter] = []
        for match in chapterLineRegex.matches(in: plainText, range: NSRange(location: 0, length: text.length)) {
            guard let start = milliseconds(text.substring(with: match.range(at: 1))) else { continue }
            let title = text.substring(with: match.range(at: match.numberOfRanges - 1))
            chapters.append(EpisodeChapter(startMilliseconds: start, title: title))
        }
        guard chapters.count >= 2,
              zip(chapters, chapters.dropFirst()).allSatisfy({ $0.startMilliseconds < $1.startMilliseconds })
        else { return [] }
        return chapters
    }

    /// "26:23" / "1:02:03" → milliseconds.
    static func milliseconds(_ timestamp: String) -> Int? {
        let parts = timestamp.split(separator: ":").compactMap { Int($0) }
        guard (2...3).contains(parts.count) else { return nil }
        return parts.reduce(0) { $0 * 60 + $1 } * 1000
    }

    /// Index of the chapter playing at `positionMilliseconds`.
    static func index(at positionMilliseconds: Int, in chapters: [EpisodeChapter]) -> Int? {
        chapters.lastIndex { $0.startMilliseconds <= positionMilliseconds }
    }

    // MARK: - Per-episode cache

    private static var cachedKey: String?
    private static var cachedChapters: [EpisodeChapter] = []

    /// The chapters for the playing episode, parsed once per episode (the
    /// main page asks on every position tick).
    @MainActor
    static func chapters(description: String?, cacheKey: String?) -> [EpisodeChapter] {
        guard let cacheKey, let description, !description.isEmpty else { return [] }
        if cacheKey == cachedKey { return cachedChapters }
        cachedKey = cacheKey
        cachedChapters = parse(plainText: DisplayText.plainText(fromHTML: description))
        return cachedChapters
    }

    // MARK: - Notes links

    /// Marks every timestamp in the rendered notes as an `anycast-seek:`
    /// link, leaving existing links alone.
    static func linkingTimestamps(in attributed: NSAttributedString) -> NSAttributedString {
        let text = attributed.string as NSString
        let matches = timestampRegex.matches(in: attributed.string, range: NSRange(location: 0, length: text.length))
        guard !matches.isEmpty else { return attributed }
        let linked = NSMutableAttributedString(attributedString: attributed)
        for match in matches {
            guard attributed.attribute(.link, at: match.range.location, effectiveRange: nil) == nil,
                  let target = milliseconds(text.substring(with: match.range)),
                  let url = URL(string: "\(seekScheme):\(target)")
            else { continue }
            linked.addAttribute(.link, value: url, range: match.range)
        }
        return linked
    }

    /// Distinct timestamps in `text`, in reading order (AI replies cite
    /// moments as "2:29:50 to 2:31:29").
    static func timestamps(in text: String) -> [Int] {
        let ns = text as NSString
        var seen: [Int] = []
        for match in timestampRegex.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            if let target = milliseconds(ns.substring(with: match.range)), !seen.contains(target) {
                seen.append(target)
            }
        }
        return seen
    }

    /// The seek target of an `anycast-seek:` link.
    static func seekTarget(of url: URL) -> Int? {
        guard url.scheme == seekScheme else { return nil }
        return Int(url.absoluteString.dropFirst(seekScheme.count + 1))
    }
}
