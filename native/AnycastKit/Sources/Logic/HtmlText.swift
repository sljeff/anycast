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
    /// (K39 parity with Dart's text output). The walk is iterative: feed
    /// depth is untrusted and these stacks are 512 KB where this runs
    /// (card-cache parsing, ingest), too small for a recursion per level.
    private static func collectTextNodes(_ element: Element, into output: inout String) {
        var stack: [Node] = element.getChildNodes().reversed()
        while let node = stack.popLast() {
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
                stack.append(contentsOf: child.getChildNodes().reversed())
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

    /// `sanitizeChildren` descends recursively, one frame per nesting level,
    /// so feed depth must be bounded before that walk runs (this path also
    /// serves off-main parsing on 512 KB stacks). Deeper trees return "" and
    /// take the caller's plain-text fallback (`displayPayload`).
    static let maximumTreeDepth = 64

    /// sanitize_html parses a FRAGMENT (never a full document), filters, and
    /// re-serializes. `id`/`class` are always dropped (the app passes no
    /// allowElementId/allowClassName).
    public static func sanitizeHtml(_ html: String) -> String {
        guard let document = try? SwiftSoup.parseBodyFragment(html),
              let body = document.body()
        else { return "" }
        guard ShowNotesNormalizer.nodeStats(of: body).maxDepth <= maximumTreeDepth else {
            return ""
        }
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

    /// https/http/mailto/schemeless allowed (Dart `_validLink`). The scheme
    /// rules live in `ShowNotesURLPolicy` (shared with the show-notes IR
    /// pipeline); behavior here is unchanged.
    static func isPermittedLink(_ url: String) -> Bool {
        ShowNotesURLPolicy.isPermittedLink(url)
    }

    /// https/http/schemeless allowed (Dart `_validUrl`).
    static func isPermittedURL(_ url: String) -> Bool {
        ShowNotesURLPolicy.isPermittedImageURL(url)
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
        let repaired = repairEmbeddedMarkup(html)
        if repaired.dartTrimmed().hasPrefix("<") {
            let sanitized = sanitizeHtml(repaired).dartTrimmed()
            if sanitized.isEmpty {
                return .text(htmlToText(repaired))
            }
            return .html(sanitized)
        }
        return .text(repaired)
    }

    // MARK: - Embedded markup repair

    /// Tags that count as markup on their own, without a closing tag.
    private static let standaloneTags: Set<String> = ["br", "hr", "wbr"]

    /// Presentational tags the sanitizer would delete with their text; the
    /// repair drops the tag and keeps the text.
    private static let unwrappedTags: Set<String> = ["font", "u", "center"]

    private static let embeddedTagExpression: NSRegularExpression = {
        let opening = "(?:<|&(?:amp;)*(?:lt|#0*60|#[xX]0*3[cC]);)"
        let closing = "(?:>|&(?:amp;)*(?:gt|#0*62|#[xX]0*3[eE]);)"
        let escapedQuote = "&(?:amp;)*(?:quot|apos|#0*3[49]|#[xX]0*2[27]);"
        let value = "(?:\"[^\"<]{0,4096}\"|'[^'<]{0,4096}'"
            + "|\(escapedQuote).{0,4096}?\(escapedQuote)"
            + "|(?:(?!\(closing))[^\\s\"'<>]){1,4096})"
        let attribute = "[a-zA-Z_:][-\\w:.]*\\s*=\\s*\(value)"
        return try! NSRegularExpression(
            pattern: "\(opening)(/?)([a-zA-Z][a-zA-Z0-9]*)"
                + "((?:\\s+\(attribute)(?:\\s*\(attribute))*)?)\\s*(/?)\(closing)"
        )
    }()

    private struct EmbeddedTag {
        let range: Range<String.Index>
        let name: String
        let attributes: String
        let isClosing: Bool
        let selfCloses: Bool
        var isEscaped: Bool
    }

    /// Feeds put real HTML inside fields that open as plain prose (NPR:
    /// `Light is the answer.<br/><br/>For <em>years</em>`), or escape it
    /// (`&lt;em&gt;`). The display routing only recognizes a leading `<`, so
    /// that markup would reach the reader verbatim.
    ///
    /// Returns display-ready source. A field that already opens with `<` only
    /// has its escaped tags restored. A field that opens as prose and holds a
    /// real tag becomes a `<body>` document: every other `<` is escaped, so the
    /// parser cannot swallow prose (`x<y`), and its line breaks become `<br>`.
    /// Anything else comes back unchanged.
    ///
    /// A real tag has a name the sanitizer knows, plus one of: a standalone
    /// name (`br`), `name=value` attributes, or a matching closing tag.
    /// `<event>`, `<3` and a lone `<em>` therefore stay literal. Display only:
    /// ingest stays on `htmlToText` (G5 parity).
    public static func repairEmbeddedMarkup(_ text: String) -> String {
        let isDocument = text.dartTrimmed().hasPrefix("<")
        if isDocument ? !text.contains("&") : !(text.contains("<") || text.contains("&")) {
            return text
        }
        let tags = realEmbeddedTags(in: text)
        guard !tags.isEmpty else { return text }

        var output = ""
        var cursor = text.startIndex
        if isDocument {
            for tag in tags where tag.isEscaped {
                output += text[cursor..<tag.range.lowerBound]
                output += markup(for: tag)
                cursor = tag.range.upperBound
            }
            output += text[cursor...]
            return output
        }
        for tag in tags {
            output += escapedProse(text[cursor..<tag.range.lowerBound])
            output += markup(for: tag)
            cursor = tag.range.upperBound
        }
        output += escapedProse(text[cursor...])
        return "<body>\(output)</body>"
    }

    private static func realEmbeddedTags(in text: String) -> [EmbeddedTag] {
        let fullRange = NSRange(text.startIndex..., in: text)
        let candidates: [EmbeddedTag] = embeddedTagExpression.matches(in: text, range: fullRange).compactMap { match in
            guard let range = Range(match.range, in: text),
                  let closing = Range(match.range(at: 1), in: text),
                  let name = Range(match.range(at: 2), in: text),
                  let attributes = Range(match.range(at: 3), in: text),
                  let selfClosing = Range(match.range(at: 4), in: text)
            else { return nil }
            let lowered = text[name].lowercased()
            guard allowedElements.contains(lowered) || unwrappedTags.contains(lowered) else { return nil }
            return EmbeddedTag(
                range: range,
                name: lowered,
                attributes: String(text[attributes]),
                isClosing: !closing.isEmpty,
                selfCloses: !selfClosing.isEmpty,
                isEscaped: text[range].hasPrefix("&")
            )
        }

        var isReal = [Bool](repeating: false, count: candidates.count)
        var unclosed: [String: [Int]] = [:]
        for (index, tag) in candidates.enumerated() {
            if tag.isClosing {
                if let opener = unclosed[tag.name]?.popLast() {
                    isReal[opener] = true
                    isReal[index] = true
                }
            } else if standaloneTags.contains(tag.name) {
                isReal[index] = true
            } else {
                if !tag.attributes.isEmpty { isReal[index] = true }
                unclosed[tag.name, default: []].append(index)
            }
        }
        return zip(candidates, isReal).filter(\.1).map(\.0)
    }

    private static func markup(for tag: EmbeddedTag) -> String {
        if unwrappedTags.contains(tag.name) { return "" }
        var attributes = tag.attributes
        if tag.isEscaped {
            attributes = attributes
                .replacingOccurrences(
                    of: "&(?:amp;)*(?:quot|#0*34|#[xX]0*22);", with: "\"", options: .regularExpression
                )
                .replacingOccurrences(
                    of: "&(?:amp;)*(?:apos|#0*39|#[xX]0*27);", with: "'", options: .regularExpression
                )
        }
        return "<\(tag.isClosing ? "/" : "")\(tag.name)\(attributes)\(tag.selfCloses ? "/" : "")>"
    }

    private static func escapedProse(_ prose: Substring) -> String {
        prose
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: "\r\n", with: "<br>")
            .replacingOccurrences(of: "\r", with: "<br>")
            .replacingOccurrences(of: "\n", with: "<br>")
    }
}
