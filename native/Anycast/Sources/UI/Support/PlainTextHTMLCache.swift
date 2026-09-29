import Foundation
import CryptoKit
import AnycastKit

/// Input-keyed cache for `HtmlText.htmlToText` (08 §11.1: the Dart version
/// re-parsed HTML on every card build — a structural list-scroll cost). The
/// first miss computes off the main actor; every later lookup for the same
/// input string is a dictionary hit. Keys are SHA-256 digests of the HTML —
/// episode descriptions can run to megabytes, and keying by the raw string
/// would keep every entry resident twice for the cache's whole lifetime.
actor PlainTextHTMLCache {

    static let shared = PlainTextHTMLCache()

    private var storage: [String: String] = [:]
    private let limit = 4096

    /// Cached plain text for card descriptions. Never throws; `htmlToText`
    /// returns the trimmed input when parsing fails.
    func plainText(for html: String?) -> String {
        guard let html, !html.isEmpty else { return "" }
        let key = Self.digest(html)
        if let cached = storage[key] {
            return cached
        }
        let text = HtmlText.htmlToText(html)
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
