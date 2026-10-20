import CoreGraphics
import Foundation
import SwiftSoup

/// Parses raw podcast show-notes HTML into a `ShowNotesDocument`.
///
/// This is the IR layer of the new rendering pipeline; it deliberately does NOT
/// run `HtmlText.sanitizeHtml` first. Where the old sanitizer deleted whole
/// disallowed subtrees (losing their text), the normalizer unwraps presentation
/// containers and unknown tags transparently and keeps the text — that fix
/// lives only here and never changes sanitizer behavior.
///
/// General rules (details pinned by ShowNotesNormalizerTests):
/// - Whitespace collapses to single spaces; whitespace-only text nodes
///   (structural inter-tag spacing, pure `&nbsp;`) are dropped, which also
///   drives empty-block removal.
/// - `<br>`: a single one is a `lineBreak` run; two or more consecutive ones
///   are absorbed as a block boundary (splitting paragraphs) at block level,
///   and collapse to a single `lineBreak` inside a block that cannot split
///   (e.g. inside one `<p>`). Leading/trailing breaks at block edges vanish.
/// - Images are indexed in document order (0-based), including images demoted
///   to inline runs inside paragraphs/headings.
public struct ShowNotesNormalizer {

    // MARK: - Limits

    /// Hard ceiling on input size; larger inputs return an empty document so
    /// callers can fall back to plain text.
    public static let maximumInputBytes = 2 * 1024 * 1024
    /// Parsed-node ceiling; pathological inputs return an empty document.
    public static let maximumNodeCount = 50_000
    /// Nesting ceiling guarding recursive walks (a narrow-but-deep tree stays
    /// under the node cap but would overflow the recursive descent).
    static let maximumParseDepth = 1_000
    /// Deepest list nesting represented; deeper lists flatten onto depth 3.
    static let maximumListDepth = 3
    /// Deepest `blockquote` nesting represented; deeper quotes flatten into
    /// the enclosing quote's blocks.
    static let maximumQuoteDepth = 2

    public static func normalize(html: String) -> ShowNotesDocument {
        guard !html.isEmpty, html.utf8.count <= maximumInputBytes else {
            return ShowNotesDocument(blocks: [])
        }
        guard let document = try? SwiftSoup.parse(html),
              let body = document.body()
        else { return ShowNotesDocument(blocks: []) }

        let stats = nodeStats(of: body)
        guard stats.count <= maximumNodeCount, stats.maxDepth <= maximumParseDepth else {
            return ShowNotesDocument(blocks: [])
        }

        var builder = Builder()
        processBlockChildren(of: body, into: &builder)
        builder.flushParagraph()
        trimDocumentEdges(&builder.blocks)
        return ShowNotesDocument(blocks: builder.blocks)
    }

    // MARK: - Builder state

    private struct Builder {
        var blocks: [ShowNotesBlock] = []
        /// Inline content accumulated at block level; flushed as a paragraph
        /// at the next block boundary.
        var pending = InlineBuffer()
        var imageIndex = 0
        /// URL of the most recently kept image (adjacent-duplicate detection).
        /// Cleared by non-image content, not by paragraph flushes.
        var lastImageURL: URL?
        var quoteDepth = 0

        mutating func flushParagraph() {
            pending.breaks = 0
            trimTrailingSpaces(&pending.runs)
            if !pending.runs.isEmpty {
                blocks.append(.paragraph(runs: pending.runs))
            }
            pending = InlineBuffer()
        }

        /// Materializes pending `<br>`s for block-level inline content: one
        /// break becomes a `lineBreak` run (dropped at block start), two or
        /// more flush the pending content as its own paragraph (block
        /// boundary) and the breaks are absorbed.
        mutating func materializePendingBreaks() {
            guard pending.breaks > 0 else { return }
            let count = pending.breaks
            pending.breaks = 0
            if pending.runs.isEmpty { return } // leading breaks at block start
            if count == 1 {
                pending.runs.append(.lineBreak)
                lastImageURL = nil
            } else {
                flushParagraph()
            }
        }

        mutating func appendPendingText(_ raw: String) {
            let normalized = ShowNotesNormalizer.normalizeWhitespace(raw)
            guard !normalized.isEmpty else { return }
            materializePendingBreaks()
            var text = normalized
            if pending.runs.isEmpty || lastRunIsLineBreak(pending.runs) {
                // Leading blanks still go (block start); a TRAILING blank is
                // kept — the next inline element may need the separation
                // ("<strong>Guest:</strong> <em>Jane</em>"), and trailing
                // whitespace is trimmed once at block finalize.
                text = String(text.drop(while: { $0 == " " }))
            }
            guard !text.isEmpty else { return }
            pending.runs.append(.text(text))
            // Whitespace-only text does NOT break image adjacency;
            // real words do.
            if !text.allSatisfy({ $0 == " " }) {
                lastImageURL = nil
            }
        }

        mutating func appendPendingRuns(_ runs: [ShowNotesRun]) {
            guard !runs.isEmpty else { return }
            materializePendingBreaks()
            pending.runs.append(contentsOf: runs)
            // Non-separator content breaks adjacency for image dedup —
            // clearing only on a trailing text run let
            // <img><strong>…</strong><img> wrongly dedup the second image,
            // while pure whitespace between images must NOT break it.
            if !runs.allSatisfy(ShowNotesNormalizer.isImageDedupSeparator) {
                lastImageURL = nil
            }
        }
    }

    /// Inline content accumulator for a single block's run list.
    private struct InlineBuffer {
        var runs: [ShowNotesRun] = []
        var breaks = 0
    }

    /// SwiftSoup's `attr` throws; missing attributes read as "" here.
    static func attr(_ element: Element, _ name: String) -> String {
        (try? element.attr(name)) ?? ""
    }

    // MARK: - Tag sets

    static let deletedSubtrees: Set<String> = [
        "script", "style", "iframe", "object", "embed", "video", "audio", "svg",
    ]

    static let blockLevelTags: Set<String> = [
        "p", "h1", "h2", "h3", "h4", "h5", "h6", "h7", "h8",
        "ul", "ol", "li", "blockquote", "pre", "table", "thead", "tbody",
        "tfoot", "tr", "td", "th", "caption", "hr", "figure", "figcaption",
        "dl", "dt", "dd", "details", "summary", "div", "section", "article",
    ]

    // MARK: - Block context

    private static func processBlockChildren(of element: Element, into b: inout Builder) {
        for node in element.getChildNodes() {
            processBlockNode(node, into: &b)
        }
    }

    private static func processBlockNode(_ node: Node, into b: inout Builder) {
        if let textNode = node as? TextNode {
            b.appendPendingText(textNode.getWholeText())
            return
        }
        guard let element = node as? Element else { return } // comments, data nodes
        let tag = element.tagName()

        if deletedSubtrees.contains(tag) { return }

        if let level = headingLevel(tag) {
            b.flushParagraph()
            var buffer = InlineBuffer()
            collectChildRuns(of: element, into: &buffer, builder: &b)
            finalize(&buffer)
            if !buffer.runs.isEmpty {
                b.blocks.append(.heading(level: level, runs: buffer.runs))
            }
            return
        }

        switch tag {
        case "p":
            b.flushParagraph()
            var buffer = InlineBuffer()
            collectChildRuns(of: element, into: &buffer, builder: &b)
            finalize(&buffer)
            if !buffer.runs.isEmpty {
                b.blocks.append(.paragraph(runs: buffer.runs))
            }

        case "div", "section", "article", "figure", "details":
            processContainer(element, into: &b)

        case "figcaption", "dd":
            b.flushParagraph()
            var buffer = InlineBuffer()
            collectChildRuns(of: element, into: &buffer, builder: &b)
            finalize(&buffer)
            if !buffer.runs.isEmpty {
                b.blocks.append(.paragraph(runs: buffer.runs))
            }

        case "summary", "dt":
            b.flushParagraph()
            var buffer = InlineBuffer()
            collectChildRuns(of: element, into: &buffer, builder: &b)
            finalize(&buffer)
            if !buffer.runs.isEmpty {
                b.blocks.append(.paragraph(runs: [
                    .emphasis(runs: buffer.runs, strong: true, italic: false, mono: false, strike: false),
                ]))
            }

        case "ul":
            b.flushParagraph()
            processList(element, ordered: false, depth: 0, start: 1, into: &b)

        case "ol":
            b.flushParagraph()
            let start = Int(attr(element, "start").trimmingCharacters(in: .whitespaces)) ?? 1
            processList(element, ordered: true, depth: 0, start: start, into: &b)

        case "li":
            b.flushParagraph()
            processListItem(element, ordered: false, number: nil, depth: 0, into: &b)

        case "blockquote":
            processQuote(element, into: &b)

        case "pre":
            processPre(element, into: &b)

        case "hr":
            b.flushParagraph()
            b.blocks.append(.divider)

        case "table":
            b.flushParagraph()
            processTableSections(of: element, into: &b)

        case "dl":
            b.flushParagraph()
            processBlockChildren(of: element, into: &b)

        case "img":
            b.flushParagraph()
            if let image = makeImage(element, builder: &b) {
                b.blocks.append(.image(image))
            }

        default:
            // Unknown/other tags unwrap. Container-shaped ones (with
            // block-level children) expand transparently in block context;
            // inline-shaped ones (e.g. a bare <b>…</b> directly under body)
            // contribute their formatted runs to the pending paragraph.
            if hasBlockLevelChild(element) {
                processBlockChildren(of: element, into: &b)
            } else {
                var buffer = b.pending
                collectElementRuns(of: element, into: &buffer, builder: &b)
                b.pending = buffer
            }
        }
    }

    /// True when any direct child element is block-level.
    static func hasBlockLevelChild(_ element: Element) -> Bool {
        element.children().contains { blockLevelTags.contains($0.tagName()) }
    }

    /// div/section/article/figure/details: with block-level children the
    /// container is transparent; with inline-only content it becomes its own
    /// paragraph; empty/whitespace-only content disappears. `figure` also
    /// counts a direct child `img` as block-triggering so the figure maps to
    /// an image block plus its caption paragraph.
    private static func processContainer(_ element: Element, into b: inout Builder) {
        let hasDirectImage = element.tagName() == "figure"
            && element.children().contains { $0.tagName() == "img" }
        if hasBlockLevelChild(element) || hasDirectImage {
            processBlockChildren(of: element, into: &b)
            return
        }
        b.flushParagraph()
        var buffer = InlineBuffer()
        collectChildRuns(of: element, into: &buffer, builder: &b)
        finalize(&buffer)
        if !buffer.runs.isEmpty {
            b.blocks.append(.paragraph(runs: buffer.runs))
        }
    }

    // MARK: - Lists

    private static func processList(_ element: Element, ordered: Bool, depth: Int, start: Int, into b: inout Builder) {
        var number = start
        for node in element.getChildNodes() {
            guard let child = node as? Element else { continue }
            let tag = child.tagName()
            if tag == "li" {
                processListItem(child, ordered: ordered, number: ordered ? number : nil, depth: depth, into: &b)
                if ordered { number += 1 }
            } else if tag == "ul" || tag == "ol" {
                // A list nested directly inside a list (no wrapping li).
                processList(child, ordered: tag == "ol", depth: depth + 1, start: 1, into: &b)
            } else {
                processBlockNode(child, into: &b)
            }
        }
    }

    private static func processListItem(_ element: Element, ordered: Bool, number: Int?, depth: Int, into b: inout Builder) {
        b.flushParagraph()
        let effectiveDepth = min(depth, maximumListDepth)
        var buffer = InlineBuffer()

        func emitItem() {
            finalize(&buffer)
            if !buffer.runs.isEmpty {
                b.blocks.append(.listItem(ordered: ordered, number: number, depth: effectiveDepth, runs: buffer.runs))
            }
            buffer = InlineBuffer()
        }

        for node in element.getChildNodes() {
            if let textNode = node as? TextNode {
                appendText(textNode.getWholeText(), to: &buffer, builder: &b)
                continue
            }
            guard let child = node as? Element else { continue }
            let tag = child.tagName()
            if deletedSubtrees.contains(tag) { continue }
            if tag == "ul" || tag == "ol" {
                // Nested lists break out as sibling list-item blocks, one
                // level deeper.
                emitItem()
                processList(child, ordered: tag == "ol", depth: effectiveDepth + 1, start: 1, into: &b)
            } else if blockLevelTags.contains(tag) {
                // p/div/etc. inside li merge into the item's runs; a single
                // break separates consecutive chunks.
                if !buffer.runs.isEmpty { buffer.breaks = 1 }
                collectChildRuns(of: child, into: &buffer, builder: &b)
            } else {
                collectElementRuns(of: child, into: &buffer, builder: &b)
            }
        }
        emitItem()
    }

    // MARK: - Quotes

    private static func processQuote(_ element: Element, into b: inout Builder) {
        b.flushParagraph()
        if b.quoteDepth >= maximumQuoteDepth {
            // Third-level (or deeper) quotes flatten into the enclosing one.
            processBlockChildren(of: element, into: &b)
            return
        }
        b.quoteDepth += 1
        let start = b.blocks.count
        processBlockChildren(of: element, into: &b)
        b.flushParagraph()
        let inner = Array(b.blocks[start...])
        b.blocks.removeSubrange(start...)
        b.quoteDepth -= 1
        if !inner.isEmpty {
            b.blocks.append(.quote(blocks: inner))
        }
    }

    // MARK: - Preformatted text

    private static func processPre(_ element: Element, into b: inout Builder) {
        b.flushParagraph()
        let text = trimmedEdgeBlanks(preformattedText(of: element))
        guard !text.isEmpty else { return }
        b.blocks.append(.codeBlock(text: text))
    }

    /// Tab-expanded, CR-normalized raw text of a `pre` subtree (interior
    /// whitespace preserved, nothing inside is parsed as inline markup).
    static func preformattedText(of element: Element) -> String {
        wholeText(of: element)
            .replacingOccurrences(of: "\t", with: "    ")
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
    }

    /// Drops leading/trailing blank (empty or space-only) lines; interior
    /// lines are untouched.
    static func trimmedEdgeBlanks(_ text: String) -> String {
        var lines = text.components(separatedBy: "\n")
        while let first = lines.first, first.allSatisfy({ $0 == " " }) {
            lines.removeFirst()
        }
        while let last = lines.last, last.allSatisfy({ $0 == " " }) {
            lines.removeLast()
        }
        return lines.joined(separator: "\n")
    }

    /// Raw text of a subtree (whitespace preserved): text nodes verbatim,
    /// `<br>` as newline, elements recursed, script/style skipped.
    private static func wholeText(of element: Element) -> String {
        var output = ""
        for node in element.getChildNodes() {
            if let textNode = node as? TextNode {
                output += textNode.getWholeText()
            } else if let child = node as? Element {
                let tag = child.tagName()
                if tag == "script" || tag == "style" { continue }
                if tag == "br" { output += "\n"; continue }
                output += wholeText(of: child)
            }
        }
        return output
    }

    // MARK: - Tables

    /// Walks table sections; each `tr` becomes one paragraph with non-empty
    /// cell contents joined by " · "; `caption` becomes a paragraph in
    /// document order. colspan/rowspan are ignored.
    private static func processTableSections(of element: Element, into b: inout Builder) {
        for node in element.getChildNodes() {
            guard let child = node as? Element else { continue }
            let tag = child.tagName()
            switch tag {
            case "tr":
                emitTableRow(child, into: &b)
            case "thead", "tbody", "tfoot":
                processTableSections(of: child, into: &b)
            case "caption":
                var buffer = InlineBuffer()
                collectChildRuns(of: child, into: &buffer, builder: &b)
                finalize(&buffer)
                if !buffer.runs.isEmpty {
                    b.blocks.append(.paragraph(runs: buffer.runs))
                }
            case "colgroup", "col", "script", "style":
                continue
            default:
                continue
            }
        }
    }

    private static func emitTableRow(_ row: Element, into b: inout Builder) {
        let runs = tableRowRuns(row, builder: &b)
        if !runs.isEmpty {
            b.blocks.append(.paragraph(runs: runs))
        }
    }

    /// Degraded table flattening when a table appears where only runs are
    /// possible (a nested table inside a cell, or inside a list item): rows
    /// and cells all join with " · ".
    private static func flattenTableToRuns(_ element: Element, into buffer: inout InlineBuffer, builder: inout Builder) {
        for node in element.getChildNodes() {
            guard let child = node as? Element else { continue }
            let tag = child.tagName()
            switch tag {
            case "tr":
                appendRuns(tableRowRuns(child, builder: &builder), to: &buffer, builder: &builder)
            case "thead", "tbody", "tfoot":
                flattenTableToRuns(child, into: &buffer, builder: &builder)
            case "caption":
                var caption = InlineBuffer()
                collectChildRuns(of: child, into: &caption, builder: &builder)
                finalize(&caption)
                appendRuns(caption.runs, to: &buffer, builder: &builder)
            default:
                continue
            }
        }
    }

    private static func tableRowRuns(_ row: Element, builder: inout Builder) -> [ShowNotesRun] {
        var runs: [ShowNotesRun] = []
        for cell in row.children() {
            let tag = cell.tagName()
            guard tag == "td" || tag == "th" else { continue }
            var cellBuffer = InlineBuffer()
            collectChildRuns(of: cell, into: &cellBuffer, builder: &builder)
            finalize(&cellBuffer)
            guard !cellBuffer.runs.isEmpty else { continue }
            if !runs.isEmpty { runs.append(.text(" · ")) }
            runs.append(contentsOf: cellBuffer.runs)
        }
        return runs
    }

    // MARK: - Inline (run) collection

    private static func collectChildRuns(
        of element: Element,
        into buffer: inout InlineBuffer,
        builder: inout Builder,
        inLink: Bool = false
    ) {
        for node in element.getChildNodes() {
            if let textNode = node as? TextNode {
                appendText(textNode.getWholeText(), to: &buffer, builder: &builder)
            } else if let child = node as? Element {
                collectElementRuns(of: child, into: &buffer, builder: &builder, inLink: inLink)
            }
        }
    }

    private static func collectElementRuns(
        of element: Element,
        into buffer: inout InlineBuffer,
        builder: inout Builder,
        inLink: Bool = false
    ) {
        let tag = element.tagName()
        if deletedSubtrees.contains(tag) { return }

        func wrap(_ make: ([ShowNotesRun]) -> ShowNotesRun) {
            var child = InlineBuffer()
            collectChildRuns(of: element, into: &child, builder: &builder, inLink: inLink)
            finalize(&child)
            guard !child.runs.isEmpty else { return }
            appendRuns([make(child.runs)], to: &buffer, builder: &builder)
        }

        switch tag {
        case "br":
            buffer.breaks += 1

        case "wbr":
            return

        case "img":
            if let image = makeImage(element, builder: &builder) {
                appendRuns([.image(image)], to: &buffer, builder: &builder)
            }

        case "a":
            collectLinkRuns(of: element, into: &buffer, builder: &builder, inLink: inLink)

        case "strong", "b":
            wrap { .emphasis(runs: $0, strong: true, italic: false, mono: false, strike: false) }
        case "em", "i":
            wrap { .emphasis(runs: $0, strong: false, italic: true, mono: false, strike: false) }
        case "s", "strike", "del":
            wrap { .emphasis(runs: $0, strong: false, italic: false, mono: false, strike: true) }
        case "code", "tt", "kbd", "samp":
            wrap { .emphasis(runs: $0, strong: false, italic: false, mono: true, strike: false) }
        case "sup":
            wrap { .superscript(runs: $0) }
        case "sub":
            wrap { .subscript(runs: $0) }

        case "q":
            var child = InlineBuffer()
            collectChildRuns(of: element, into: &child, builder: &builder, inLink: inLink)
            finalize(&child)
            guard !child.runs.isEmpty else { return }
            var quoted: [ShowNotesRun] = [.text("\u{201C}")]
            quoted.append(contentsOf: child.runs)
            quoted.append(.text("\u{201D}"))
            appendRuns(quoted, to: &buffer, builder: &builder)

        case "pre":
            // Degraded path (pre inside a paragraph/heading/list item): mono
            // run of the preserved text.
            let text = trimmedEdgeBlanks(preformattedText(of: element))
            if !text.isEmpty {
                appendRuns(
                    [.emphasis(runs: [.text(text)], strong: false, italic: false, mono: true, strike: false)],
                    to: &buffer,
                    builder: &builder
                )
            }

        case "hr":
            buffer.breaks = max(buffer.breaks, 1)

        case "ul", "ol":
            // Degraded path: a list somewhere only runs are possible. Items
            // survive as text chunks separated by line breaks (no numbering).
            for item in listItems(of: element) {
                var itemBuffer = InlineBuffer()
                collectChildRuns(of: item, into: &itemBuffer, builder: &builder)
                finalize(&itemBuffer)
                if !itemBuffer.runs.isEmpty {
                    if !buffer.runs.isEmpty { buffer.breaks = max(buffer.breaks, 1) }
                    appendRuns(itemBuffer.runs, to: &buffer, builder: &builder)
                }
            }

        case "table":
            flattenTableToRuns(element, into: &buffer, builder: &builder)

        default:
            // Block elements unwrapped into a run context merge with a single
            // break separator (e.g. p/div inside li). Inline-transparent and
            // unknown tags (span/font/center/u/abbr/cite/dfn/time/bdo/mark/
            // small/ins/var/ruby/…) simply keep their children.
            if blockLevelTags.contains(tag), !buffer.runs.isEmpty {
                buffer.breaks = max(buffer.breaks, 1)
            }
            collectChildRuns(of: element, into: &buffer, builder: &builder)
        }
    }

    /// Collects `li` elements of a list, descending through wrappers.
    private static func listItems(of element: Element) -> [Element] {
        var items: [Element] = []
        for child in element.children() {
            let tag = child.tagName()
            if tag == "li" {
                items.append(child)
            } else {
                items.append(contentsOf: listItems(of: child))
            }
        }
        return items
    }

    private static func collectLinkRuns(
        of element: Element,
        into buffer: inout InlineBuffer,
        builder: inout Builder,
        inLink: Bool
    ) {
        var child = InlineBuffer()
        collectChildRuns(of: element, into: &child, builder: &builder, inLink: true)
        finalize(&child)
        // Empty-text links are dropped entirely.
        guard !child.runs.isEmpty else { return }
        if !inLink, let url = ShowNotesURLPolicy.absoluteLinkURL(attr(element, "href")) {
            appendRuns([.link(url: url, runs: child.runs)], to: &buffer, builder: &builder)
        } else {
            // Relative/anchor/javascript:/data: links (and links nested in a
            // link) keep only their text.
            appendRuns(child.runs, to: &buffer, builder: &builder)
        }
    }

    // MARK: - Inline append primitives

    /// True for runs that do NOT break adjacent-image dedup: images and
    /// whitespace-only text.
    private static func isImageDedupSeparator(_ run: ShowNotesRun) -> Bool {
        switch run {
        case .image:
            return true
        case .text(let string):
            return string.allSatisfy { $0 == " " }
        default:
            return false
        }
    }


    /// Text into a local run buffer: collapse whitespace, drop leading spaces
    /// at buffer start / after a line break. Whitespace-ONLY text is KEPT
    /// when the buffer already has runs — it is the separation between
    /// adjacent inline elements ("<strong>a:</strong> <em>b</em>"); trailing
    /// blanks are trimmed at buffer finalize. A single pending break
    /// materializes as `lineBreak`; multiple pending breaks also collapse to
    /// one here (this buffer cannot split blocks).
    private static func appendText(_ raw: String, to buffer: inout InlineBuffer, builder: inout Builder) {
        let normalized = normalizeWhitespace(raw)
        guard !normalized.isEmpty else { return }
        materializeBreaks(&buffer, builder: &builder)
        var text = normalized
        if buffer.runs.isEmpty || lastRunIsLineBreak(buffer.runs) {
            text = String(text.drop(while: { $0 == " " }))
        }
        guard !text.isEmpty else { return }
        buffer.runs.append(.text(text))
        // Whitespace-only text does NOT break image adjacency; real words do.
        if !text.allSatisfy({ $0 == " " }) {
            builder.lastImageURL = nil
        }
    }

    private static func appendRuns(_ runs: [ShowNotesRun], to buffer: inout InlineBuffer, builder: inout Builder) {
        guard !runs.isEmpty else { return }
        materializeBreaks(&buffer, builder: &builder)
        buffer.runs.append(contentsOf: runs)
        // Non-separator content breaks image-dedup adjacency (see the
        // Builder.appendPendingRuns twin).
        if !runs.allSatisfy(isImageDedupSeparator) {
            builder.lastImageURL = nil
        }
    }

    private static func materializeBreaks(_ buffer: inout InlineBuffer, builder: inout Builder) {
        guard buffer.breaks > 0 else { return }
        buffer.breaks = 0
        if buffer.runs.isEmpty { return } // leading breaks deleted
        buffer.runs.append(.lineBreak)
        builder.lastImageURL = nil
    }

    /// End of a run buffer: discard trailing (unmaterialized) breaks and trim
    /// trailing spaces of the final text run.
    private static func finalize(_ buffer: inout InlineBuffer) {
        buffer.breaks = 0
        trimTrailingSpaces(&buffer.runs)
    }

    // MARK: - Images

    private static func makeImage(_ element: Element, builder: inout Builder) -> ShowNotesImage? {
        guard let url = ShowNotesURLPolicy.absoluteImageURL(attr(element, "src")) else { return nil }
        let declaredWidth = parseLength(attr(element, "width"))
        let declaredHeight = parseLength(attr(element, "height"))
        // Declared width or height <= 2 px is a tracking pixel: drop.
        if let w = declaredWidth, w <= 2 { return nil }
        if let h = declaredHeight, h <= 2 { return nil }
        // Adjacent duplicate (no intervening content): keep only the first.
        if builder.lastImageURL == url { return nil }
        var declaredSize: CGSize?
        if let w = declaredWidth, let h = declaredHeight, w > 0, h > 0 {
            declaredSize = CGSize(width: w, height: h)
        }
        let alt = attr(element, "alt").trimmingCharacters(in: .whitespacesAndNewlines)
        let image = ShowNotesImage(
            url: url,
            alt: alt.isEmpty ? nil : alt,
            declaredSize: declaredSize,
            index: builder.imageIndex
        )
        builder.imageIndex += 1
        builder.lastImageURL = url
        return image
    }

    /// "100", "100px" → 100; percentages and non-numeric values → nil.
    private static func parseLength(_ raw: String) -> CGFloat? {
        var value = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if value.hasSuffix("px") { value = String(value.dropLast(2)) }
        if value.hasSuffix("%") { return nil }
        guard let number = Double(value), number.isFinite else { return nil }
        return CGFloat(number)
    }

    // MARK: - Text helpers

    /// Collapses every whitespace run (including `&nbsp;`, tabs, newlines) to
    /// a single space.
    static func normalizeWhitespace(_ text: String) -> String {
        var output = ""
        output.reserveCapacity(text.count)
        var lastWasSpace = false
        for character in text {
            if character.isWhitespace {
                if !lastWasSpace {
                    output.append(" ")
                    lastWasSpace = true
                }
            } else {
                output.append(character)
                lastWasSpace = false
            }
        }
        return output
    }

    static func trimTrailingSpaces(_ runs: inout [ShowNotesRun]) {
        guard let last = runs.last, case .text(let text) = last else { return }
        var view = Substring(text)
        while view.last == " " { view = view.dropLast() }
        if view.isEmpty {
            runs.removeLast()
        } else if view.count != text.count {
            runs[runs.count - 1] = .text(String(view))
        }
    }

    static func lastRunIsLineBreak(_ runs: [ShowNotesRun]) -> Bool {
        if case .lineBreak = runs.last { return true }
        return false
    }

    /// "h1"–"h8" → 1–8; nil otherwise.
    static func headingLevel(_ tag: String) -> Int? {
        guard tag.count == 2, tag.first == "h",
              let digit = tag.last, let level = digit.wholeNumberValue
        else { return nil }
        return (1...8).contains(level) ? level : nil
    }

    // MARK: - Document edges

    /// Defensive final pass: drop leading/trailing blank blocks (paragraphs
    /// with no runs, empty quotes/code blocks). Inner handling normally makes
    /// this a no-op.
    static func trimDocumentEdges(_ blocks: inout [ShowNotesBlock]) {
        func isBlank(_ block: ShowNotesBlock) -> Bool {
            switch block {
            case .paragraph(let runs): return runs.isEmpty
            case .quote(let inner): return inner.isEmpty
            case .codeBlock(let text): return text.isEmpty
            default: return false
            }
        }
        while blocks.first.map(isBlank) == true { blocks.removeFirst() }
        while blocks.last.map(isBlank) == true { blocks.removeLast() }
    }

    // MARK: - Input stats

    /// Iterative node count + max depth (recursion-proof).
    static func nodeStats(of body: Element) -> (count: Int, maxDepth: Int) {
        var count = 0
        var maxDepth = 0
        var stack: [(node: Node, depth: Int)] = body.getChildNodes().map { ($0, 1) }
        while let (node, depth) = stack.popLast() {
            count += 1
            maxDepth = max(maxDepth, depth)
            if let element = node as? Element {
                stack.append(contentsOf: element.getChildNodes().map { ($0, depth + 1) })
            }
        }
        return (count, maxDepth)
    }
}
