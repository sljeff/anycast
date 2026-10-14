import Foundation
import CryptoKit
import AnycastKit

/// Input-keyed cache for the card plain text (`DisplayText.singleLine`,
/// built on `HtmlText.htmlToText`; 08 §11.1: the Dart version
/// re-parsed HTML on every card build — a structural list-scroll cost). The
/// first miss computes off the main actor; every later lookup for the same
/// input string is a dictionary hit. Keys are SHA-256 digests of the HTML —
/// episode descriptions can run to megabytes, and keying by the raw string
/// would keep every entry resident twice for the cache's whole lifetime.
actor PlainTextHTMLCache {

    static let shared = PlainTextHTMLCache()

    private var storage: [String: String] = [:]
    private let limit = 4096

    /// Cached single-line plain text for card descriptions. Never throws;
    /// `htmlToText` returns the trimmed input when parsing fails.
    func plainText(for html: String?) -> String {
        guard let html, !html.isEmpty else { return "" }
        let key = Self.digest(html)
        if let cached = storage[key] {
            return cached
        }
        let text = DisplayText.singleLine(fromHTML: html)
        if storage.count >= limit {
            storage.removeAll(keepingCapacity: true)   // cache, safe to drop
        }
        storage[key] = text
        return text
    }

    var count: Int { storage.count }

    /// Compact, collision-safe cache key: the full SHA-256 over the UTF-8
    /// bytes (a mismatch at worst costs one re-parse, never a wrong value).
    private static func digest(_ html: String) -> String {
        SHA256.hash(data: Data(html.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }
}

/// Feeds often ship escaped or partial markup inside plain-text fields
/// (`&nbsp;`, a mid-string `<br/>`), which the Dart-parity `HtmlText` path
/// passes through verbatim. Display surfaces decode it so readers never see
/// raw markup; line breaks survive as newlines.
nonisolated enum DisplayText {

    static func clean(_ text: String) -> String {
        guard text.contains("&") || text.contains("<") else { return text }
        let breaks = text.replacingOccurrences(
            of: "<br\\s*/?>", with: "\n", options: [.regularExpression, .caseInsensitive]
        )
        let decoded = HtmlText.htmlToText("<p>\(breaks)</p>")
        return decoded.isEmpty ? text : decoded
    }

    /// Feed HTML → plain text that keeps block structure. Block ends
    /// (`</p> </div> </h1-6> </blockquote> </tr>`) become a blank line,
    /// `<br>` and `</li>` a line break, so adjacent paragraphs no longer run
    /// together ("2022.This"). Markup input collapses its source whitespace
    /// the way HTML does; plain input keeps its own line breaks. Runs of
    /// blank lines collapse to one.
    static func plainText(fromHTML html: String) -> String {
        let isMarkup = html.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("<")
        // U+2028 / U+2029 mark line / paragraph boundaries through the parse:
        // htmlToText concatenates text nodes, so the tags alone leave no trace.
        // Plain input skips the `<br>` mark because `clean` already turns a
        // stray `<br>` into "\n".
        var marked = html
        if isMarkup {
            marked = marked.replacingOccurrences(
                of: "<br\\s*/?>", with: "$0\u{2028}", options: [.regularExpression, .caseInsensitive]
            )
        }
        marked = marked
            .replacingOccurrences(
                of: "</li\\s*>", with: "$0\u{2028}", options: [.regularExpression, .caseInsensitive]
            )
            .replacingOccurrences(
                of: "</(p|div|h[1-6]|blockquote|tr)\\s*>", with: "$0\u{2029}",
                options: [.regularExpression, .caseInsensitive]
            )
        var text = clean(HtmlText.htmlToText(marked))
        if isMarkup {
            text = text.replacingOccurrences(
                of: "[\\t\\n\\r\\f\\x{0B}\\p{Zs}]+", with: " ", options: .regularExpression
            )
        } else {
            text = text
                .replacingOccurrences(of: "\r\n", with: "\n")
                .replacingOccurrences(of: "\r", with: "\n")
                .replacingOccurrences(
                    of: "[\\t\\f\\x{0B}\\p{Zs}]+", with: " ", options: .regularExpression
                )
        }
        return text
            .replacingOccurrences(of: "\u{2028}", with: "\n")
            .replacingOccurrences(of: "\u{2029}", with: "\n\n")
            .replacingOccurrences(of: " *\\n *", with: "\n", options: .regularExpression)
            .replacingOccurrences(of: "\\n{3,}", with: "\n\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The same text folded onto one line (card previews).
    static func singleLine(fromHTML html: String) -> String {
        plainText(fromHTML: html)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
