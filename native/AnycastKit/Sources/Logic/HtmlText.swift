import Foundation
import SwiftSoup

/// The two HTML paths from utils/formatters.dart / rss_fetcher.dart, pinned
/// by G5:
/// - `htmlToText`: strip markup to raw text — the Dart `html` package's
///   `body.text` concatenates text-node contents verbatim, INCLUDING the
///   contents of `<script>`/`<style>` (the Dart parser stores them as text
///   nodes — verified against Dart: `a<script>var x=1;</script><style>.y{}
///   </style>b` → `avar x=1;.y{}b`, K39), then trims. No whitespace
///   normalization, no inter-tag spacing.
/// - `sanitizeHtml`: the sanitize_html 2.1.0 GitHub-style whitelist (tag
///   list, attribute list, URL scheme validators for href/src/cite), then
///   fragment re-serialization.
public enum HtmlText {

    // MARK: - htmlToText (rss_fetcher.dart:165-185)

    /// Nil → ''; not starting with '<' (after trim) → as-is; otherwise the
    /// concatenated text of <body>, trimmed. Parse failures return the
    /// original trimmed input.
    public static func htmlToText(_ html: String?) -> String {
        guard let html else { return "" }
        let trimmed = html.dartTrimmed()
        guard trimmed.hasPrefix("<") else { return trimmed }

        guard let document = try? SwiftSoup.parse(Self.stripBogusComments(html)),
              let body = document.body()
        else { return trimmed }

        var collected = ""
        collectTextNodes(body, into: &collected)
        return collected.dartTrimmed()
    }

    /// HTML5 "bogus comment" preprocessing, matching the Dart html parser
    /// (and the html5 spec): a `<!` that is not `<!--` opens a comment that
    /// runs to the first `>`. This is what makes `<![CDATA[<p …>` behave as
    /// pinned by the G5 corpus: the CDATA marker plus the following open
    /// tag vanish and the remainder parses as markup (SwiftSoup instead
    /// treats `<![CDATA[` as a section running to `]]>`). Real `<!--…-->`
    /// comments and doctypes pass through for the parser to drop.
    static func stripBogusComments(_ html: String) -> String {
        var output = ""
        var scanner = Substring(html)
        while let open = scanner.range(of: "<!") {
            output += scanner[..<open.lowerBound]
            let afterMarker = scanner[open.upperBound...]
            if afterMarker.hasPrefix("--") || afterMarker.hasPrefix("doctype") || afterMarker.hasPrefix("DOCTYPE") {
                output += "<!"
                scanner = afterMarker
                continue
            }
            if let close = afterMarker.firstIndex(of: ">") {
                scanner = afterMarker[afterMarker.index(after: close)...]
            } else {
                scanner = afterMarker[afterMarker.endIndex...]
            }
        }
        output += scanner
        return output
    }

    /// Document-order concatenation of text-node contents — no separator
    /// injection, no normalization (matches the Dart html package's
    /// `body.text`). SwiftSoup models `<script>`/`<style>` contents as
    /// DataNodes instead of TextNodes, so they are folded in explicitly
    /// (K39 parity with Dart's text output).
    private static func collectTextNodes(_ element: Element, into output: inout String) {
        for node in element.getChildNodes() {
            if let textNode = node as? TextNode {
                output += textNode.getWholeText()
            } else if let child = node as? Element {
                let tag = child.tagName().lowercased()
                if tag == "script" || tag == "style" {
                    for sub in child.getChildNodes() {
                        if let dataNode = sub as? DataNode {
                            output += dataNode.getWholeData()
                        }
                    }
                }
                collectTextNodes(child, into: &output)
            }
        }
    }

    // MARK: - sanitizeHtml (sanitize_html 2.1.0, GFM-style rules)

    static let allowedElements: Set<String> = [
        "h1", "h2", "h3", "h4", "h5", "h6", "h7", "h8", "br", "b", "i",
        "strong", "em", "a", "pre", "code", "img", "tt", "div", "ins", "del",
        "sup", "sub", "p", "ol", "ul", "table", "thead", "tbody", "tfoot",
        "blockquote", "dl", "dt", "dd", "kbd", "q", "samp", "var", "hr",
        "ruby", "rt", "rp", "li", "tr", "td", "th", "s", "strike", "summary",
        "details", "caption", "figure", "figcaption", "abbr", "bdo", "cite",
        "dfn", "mark", "small", "span", "time", "wbr",
    ]

    static let alwaysAllowedAttributes: Set<String> = [
        "abbr", "accept", "accept-charset", "accesskey", "action", "align",
        "alt", "aria-describedby", "aria-hidden", "aria-label",
        "aria-labelledby", "axis", "border", "cellpadding", "cellspacing",
        "char", "charoff", "charset", "checked", "clear", "cols", "colspan",
        "color", "compact", "coords", "datetime", "dir", "disabled",
        "enctype", "for", "frame", "headers", "height", "hreflang", "hspace",
        "ismap", "label", "lang", "maxlength", "media", "method", "multiple",
        "name", "nohref", "noshade", "nowrap", "open", "prompt", "readonly",
        "rel", "rev", "rows", "rowspan", "rules", "scope", "selected",
        "shape", "size", "span", "start", "summary", "tabindex", "target",
        "title", "type", "usemap", "valign", "value", "vspace", "width",
        "itemprop",
    ]

    /// sanitize_html parses a FRAGMENT (never a full document), filters, and
    /// re-serializes. `id`/`class` are always dropped (the app passes no
    /// allowElementId/allowClassName).
    public static func sanitizeHtml(_ html: String) -> String {
        guard let document = try? SwiftSoup.parseBodyFragment(html),
              let body = document.body()
        else { return "" }
        // Pretty-printing injects indentation and collapses internal
        // whitespace — the Dart serializer emits raw text nodes. Callers
        // apply the shipped `.trim()` themselves (renderHtml).
        _ = try? document.outputSettings().prettyPrint(pretty: false)
        sanitizeChildren(of: body)
        let serialized = (try? body.html()) ?? ""
        // Dart's serializer escapes only & < > in text; SwiftSoup also
        // escapes quotes/apostrophes. Output-side replacement is exact:
        // the parser decoded the input entities, so every remaining
        // &quot;/&#39; in the output is SwiftSoup's own re-escaping.
        return serialized
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&apos;", with: "'")
    }

    private static func sanitizeChildren(of parent: Element) {
        for child in parent.children().reversed() {
            let tagName = child.tagName().lowercased()
            if !allowedElements.contains(tagName) {
                try? child.remove()   // the whole subtree goes with it
                continue
            }
            filterAttributes(of: child, tagName: tagName)
            sanitizeChildren(of: child)
        }
    }

    private static func filterAttributes(of element: Element, tagName: String) {
        guard let attributes = element.getAttributes() else { return }
        for attribute in attributes {
            let name = attribute.getKey().lowercased()
            if name == "id" || name == "class" {
                try? element.removeAttr(name)
                continue
            }
            if !isAttributeAllowed(tagName: tagName, attributeName: name, value: attribute.getValue()) {
                try? element.removeAttr(name)
            }
        }
    }

    private static func isAttributeAllowed(tagName: String, attributeName: String, value: String) -> Bool {
        if alwaysAllowedAttributes.contains(attributeName) { return true }

        switch (tagName, attributeName) {
        case ("a", "href"):
            return isPermittedLink(value)
        case ("img", "src"), ("img", "longdesc"):
            return isPermittedURL(value)
        case ("div", "itemscope"), ("div", "itemtype"):
            return true
        case ("blockquote", "cite"), ("del", "cite"), ("ins", "cite"), ("q", "cite"):
            return isPermittedURL(value)
        default:
            return false
        }
    }

    /// https/http/mailto/schemeless allowed (Dart `_validLink`).
    static func isPermittedLink(_ url: String) -> Bool {
        permittedSchemes(url, allowed: ["https", "http", "mailto"])
    }

    /// https/http/schemeless allowed (Dart `_validUrl`).
    static func isPermittedURL(_ url: String) -> Bool {
        permittedSchemes(url, allowed: ["https", "http"])
    }

    private static func permittedSchemes(_ url: String, allowed: [String]) -> Bool {
        guard let parsed = URL(string: url) else { return false }
        guard let scheme = parsed.scheme?.lowercased() else { return true } // no scheme
        return allowed.contains(scheme)
    }

    // MARK: - renderHtml decision (formatters.dart:152-180)

    /// The routing rule: empty → nothing; starts with '<' → sanitized HTML
    /// (falling back to plain text when sanitization empties it); otherwise
    /// plain text. Returned as the display payload; rendering itself is UI
    /// (M3).
    public enum DisplayPayload: Equatable {
        case empty
        case html(String)
        case text(String)
    }

    public static func displayPayload(for html: String) -> DisplayPayload {
        if html.isEmpty { return .empty }
        if html.dartTrimmed().hasPrefix("<") {
            let sanitized = sanitizeHtml(html).dartTrimmed()
            if sanitized.isEmpty {
                return .text(htmlToText(html))
            }
            return .html(sanitized)
        }
        return .text(html)
    }
}
