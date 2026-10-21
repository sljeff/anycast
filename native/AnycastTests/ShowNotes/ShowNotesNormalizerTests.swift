import Foundation
import Testing

@testable import AnycastKit

/// ShowNotesNormalizer mapping fixtures. Every expectation is an exact
/// `ShowNotesDocument` snapshot; whitespace collapse, break absorption, and
/// index assignment are all pinned here.
@Suite
struct ShowNotesNormalizerTests {

    // MARK: - Helpers

    private func t(_ s: String) -> ShowNotesRun { .text(s) }

    private func strong(_ runs: ShowNotesRun...) -> ShowNotesRun {
        .emphasis(runs: runs, strong: true, italic: false, mono: false, strike: false)
    }

    private func italics(_ runs: ShowNotesRun...) -> ShowNotesRun {
        .emphasis(runs: runs, strong: false, italic: true, mono: false, strike: false)
    }

    private func strike(_ runs: ShowNotesRun...) -> ShowNotesRun {
        .emphasis(runs: runs, strong: false, italic: false, mono: false, strike: true)
    }

    private func mono(_ runs: ShowNotesRun...) -> ShowNotesRun {
        .emphasis(runs: runs, strong: false, italic: false, mono: true, strike: false)
    }

    private func url(_ s: String) -> URL { URL(string: s)! }

    // MARK: - Headings and paragraphs

    @Test("h1-h8 keep their level verbatim")
    func headingLevels() {
        let doc = ShowNotesNormalizer.normalize(html: "<h1>Big</h1><h4>Mid</h4><h8>Deep</h8>")
        #expect(doc.blocks == [
            .heading(level: 1, runs: [t("Big")]),
            .heading(level: 4, runs: [t("Mid")]),
            .heading(level: 8, runs: [t("Deep")]),
        ])
    }

    @Test("Empty headings vanish")
    func emptyHeading() {
        let doc = ShowNotesNormalizer.normalize(html: "<h2></h2><h3> </h3><p>x</p>")
        #expect(doc.blocks == [.paragraph(runs: [t("x")])])
    }

    @Test("Paragraphs carry inline emphasis runs")
    func paragraphWithEmphasis() {
        let doc = ShowNotesNormalizer.normalize(
            html: "<p>Body <b>bold</b> and <i>ital</i> and <s>gone</s> and <strong>st</strong></p>"
        )
        #expect(doc.blocks == [.paragraph(runs: [
            t("Body "),
            strong(t("bold")),
            t(" and "),
            italics(t("ital")),
            t(" and "),
            strike(t("gone")),
            t(" and "),
            strong(t("st")),
        ])])
    }

    @Test("Bare text nodes wrap into a paragraph")
    func bareText() {
        let doc = ShowNotesNormalizer.normalize(html: "Hello listeners")
        #expect(doc.blocks == [.paragraph(runs: [t("Hello listeners")])])
    }

    @Test("Inline formatting directly at block level keeps its runs")
    func bareInlineElement() {
        let doc = ShowNotesNormalizer.normalize(html: "<b>hi</b> there")
        #expect(doc.blocks == [.paragraph(runs: [strong(t("hi")), t(" there")])])
    }

    @Test("Whitespace collapses; nbsp becomes a space")
    func whitespaceCollapse() {
        let doc = ShowNotesNormalizer.normalize(html: "<p>a&nbsp;b   c\n\td</p>")
        #expect(doc.blocks == [.paragraph(runs: [t("a b c d")])])
    }

    // MARK: - Containers (div/section/article)

    @Test("div with block children expands transparently")
    func divTransparent() {
        let doc = ShowNotesNormalizer.normalize(html: "<div><p>a</p><p>b</p></div>")
        #expect(doc.blocks == [
            .paragraph(runs: [t("a")]),
            .paragraph(runs: [t("b")]),
        ])
    }

    @Test("div with inline-only content becomes one paragraph")
    func divInlineOnly() {
        let doc = ShowNotesNormalizer.normalize(html: "<div>plain <i>ital</i></div>")
        #expect(doc.blocks == [.paragraph(runs: [t("plain "), italics(t("ital"))])])
    }

    @Test("Empty, whitespace-only and nbsp-only divs are deleted")
    func emptyDivs() {
        #expect(ShowNotesNormalizer.normalize(html: "<div></div><div>  </div><div>&nbsp;</div>").isEmpty)
    }

    @Test("section/article behave like div")
    func sectionArticle() {
        let doc = ShowNotesNormalizer.normalize(html: "<section><article>words</article></section>")
        #expect(doc.blocks == [.paragraph(runs: [t("words")])])
    }

    // MARK: - Transparent inline wrappers

    @Test("span/font/center/u unwrap while keeping text")
    func transparentWrappers() {
        let doc = ShowNotesNormalizer.normalize(
            html: "<p>keep<span style=\"color:red\"> this</span>ed</p>"
        )
        #expect(doc.blocks == [.paragraph(runs: [t("keep"), t(" this"), t("ed")])])

        let centered = ShowNotesNormalizer.normalize(html: "<center>mid</center>")
        #expect(centered.blocks == [.paragraph(runs: [t("mid")])])

        let tagged = ShowNotesNormalizer.normalize(html: "<p><u>u</u><font size=\"3\">f</font></p>")
        #expect(tagged.blocks == [.paragraph(runs: [t("u"), t("f")])])
    }

    @Test("abbr/cite/dfn/time/bdo/mark/small unwrap while keeping text")
    func moreTransparentWrappers() {
        let doc = ShowNotesNormalizer.normalize(
            html: "<p><abbr title=\"x\">HTML</abbr> by <cite>src</cite> "
                + "at <time>10:00</time> <dfn>term</dfn>"
                + "<bdo dir=\"ltr\">l</bdo><mark>m</mark><small>s</small></p>"
        )
        #expect(doc.blocks == [.paragraph(runs: [
            t("HTML"),
            t(" by "),
            t("src"),
            t(" at "),
            t("10:00"),
            t(" "),   // inline separation survives between tags
            t("term"),
            t("l"),
            t("m"),
            t("s"),
        ])])
    }

    @Test("Whitespace between inline tags is kept — words never fuse")
    func inlineSeparation() {
        let doc = ShowNotesNormalizer.normalize(
            html: "<p><strong>Guest:</strong> <em>Jane</em></p>"
                + "<p><span>foo</span> <span>bar</span></p>"
        )
        let plain = Self.flattenedText(of: doc)
        #expect(plain.contains("Guest: Jane"), "fused: \(plain)")
        #expect(plain.contains("foo bar"), "fused: \(plain)")
    }

    @Test("An image between two same images is NOT deduped")
    func imageDedupBrokenByEmphasis() {
        let doc = ShowNotesNormalizer.normalize(
            html: "<p><img src=\"https://e.example/a.png\">"
                + "<strong>mid</strong>"
                + "<img src=\"https://e.example/a.png\"></p>"
        )
        #expect(Self.imageCount(in: doc) == 2, "emphasis between images breaks adjacency")
    }

    /// Concatenated text of every run, ignoring nesting.
    private static func flattenedText(of doc: ShowNotesDocument) -> String {
        var out = ""
        func walk(_ runs: [ShowNotesRun]) {
            for run in runs {
                switch run {
                case .text(let s): out += s
                case .emphasis(let inner, _, _, _, _): walk(inner)
                case .link(_, let inner): walk(inner)
                case .superscript(let inner), .subscript(let inner): walk(inner)
                case .image, .lineBreak: break
                }
            }
        }
        for block in doc.blocks {
            switch block {
            case .heading(_, let runs), .paragraph(let runs):
                walk(runs)
            case .listItem(_, _, _, let runs):
                walk(runs)
            case .quote(let inner):
                for b in inner {
                    if case .paragraph(let runs) = b { walk(runs) }
                }
            case .codeBlock, .image, .divider: break
            }
        }
        return out
    }

    private static func imageCount(in doc: ShowNotesDocument) -> Int {
        var count = 0
        for block in doc.blocks {
            switch block {
            case .image: count += 1
            case .paragraph(let runs), .heading(_, let runs), .listItem(_, _, _, let runs):
                for run in runs {
                    if case .image = run { count += 1 }
                }
            default: break
            }
        }
        return count
    }

    @Test("Unknown tags unwrap and preserve text")
    func unknownTags() {
        let inline = ShowNotesNormalizer.normalize(html: "<p><foobar>kept</foobar></p>")
        #expect(inline.blocks == [.paragraph(runs: [t("kept")])])

        let block = ShowNotesNormalizer.normalize(html: "<myblock><p>kept</p></myblock>")
        #expect(block.blocks == [.paragraph(runs: [t("kept")])])
    }

    // MARK: - Line breaks

    @Test("Single br becomes a lineBreak run")
    func singleBreak() {
        let doc = ShowNotesNormalizer.normalize(html: "<p>line1<br>line2</p>")
        #expect(doc.blocks == [.paragraph(runs: [t("line1"), .lineBreak, t("line2")])])
    }

    @Test("Two consecutive brs at block level split into separate paragraphs")
    func doubleBreakBoundary() {
        let doc = ShowNotesNormalizer.normalize(html: "para1<br><br>para2")
        #expect(doc.blocks == [
            .paragraph(runs: [t("para1")]),
            .paragraph(runs: [t("para2")]),
        ])
    }

    @Test("Two brs inside one paragraph collapse to a single lineBreak")
    func doubleBreakInsideParagraph() {
        let doc = ShowNotesNormalizer.normalize(html: "<p>a<br><br>b</p>")
        #expect(doc.blocks == [.paragraph(runs: [t("a"), .lineBreak, t("b")])])
    }

    @Test("Leading and trailing brs at block edges are deleted")
    func edgeBreaks() {
        let doc = ShowNotesNormalizer.normalize(html: "<p><br>lead</p><p>tail<br></p>")
        #expect(doc.blocks == [
            .paragraph(runs: [t("lead")]),
            .paragraph(runs: [t("tail")]),
        ])
    }

    // MARK: - Lists

    @Test("ul items are unordered with nil numbers")
    func unorderedList() {
        let doc = ShowNotesNormalizer.normalize(html: "<ul><li>one</li><li>two</li></ul>")
        #expect(doc.blocks == [
            .listItem(ordered: false, number: nil, depth: 0, runs: [t("one")]),
            .listItem(ordered: false, number: nil, depth: 0, runs: [t("two")]),
        ])
    }

    @Test("ol numbers continue from the start attribute")
    func orderedStart() {
        let doc = ShowNotesNormalizer.normalize(html: "<ol start=\"3\"><li>x</li><li>y</li></ol>")
        #expect(doc.blocks == [
            .listItem(ordered: true, number: 3, depth: 0, runs: [t("x")]),
            .listItem(ordered: true, number: 4, depth: 0, runs: [t("y")]),
        ])
    }

    @Test("Invalid ol start falls back to 1")
    func orderedInvalidStart() {
        let doc = ShowNotesNormalizer.normalize(html: "<ol start=\"abc\"><li>x</li></ol>")
        #expect(doc.blocks == [
            .listItem(ordered: true, number: 1, depth: 0, runs: [t("x")]),
        ])
    }

    @Test("Nested lists gain depth")
    func nestedLists() {
        let doc = ShowNotesNormalizer.normalize(html: "<ul><li>a<ul><li>b</li></ul></li></ul>")
        #expect(doc.blocks == [
            .listItem(ordered: false, number: nil, depth: 0, runs: [t("a")]),
            .listItem(ordered: false, number: nil, depth: 1, runs: [t("b")]),
        ])
    }

    @Test("List depth is capped at 3; deeper items flatten onto depth 3")
    func listDepthCap() {
        let doc = ShowNotesNormalizer.normalize(
            html: "<ul><li>1<ul><li>2<ul><li>3<ul><li>4</li></ul></li></ul></li></ul></li></ul>"
        )
        #expect(doc.blocks == [
            .listItem(ordered: false, number: nil, depth: 0, runs: [t("1")]),
            .listItem(ordered: false, number: nil, depth: 1, runs: [t("2")]),
            .listItem(ordered: false, number: nil, depth: 2, runs: [t("3")]),
            .listItem(ordered: false, number: nil, depth: 3, runs: [t("4")]),
        ])
    }

    @Test("p elements inside li merge into the item runs")
    func liWithParagraphs() {
        let doc = ShowNotesNormalizer.normalize(html: "<ul><li><p>a</p><p>b</p></li></ul>")
        #expect(doc.blocks == [
            .listItem(ordered: false, number: nil, depth: 0, runs: [t("a"), .lineBreak, t("b")]),
        ])
    }

    @Test("li keeps inline emphasis in its runs")
    func liInlineRuns() {
        let doc = ShowNotesNormalizer.normalize(html: "<ul><li>item with <b>b</b></li></ul>")
        #expect(doc.blocks == [
            .listItem(ordered: false, number: nil, depth: 0, runs: [t("item with "), strong(t("b"))]),
        ])
    }

    // MARK: - Tables

    @Test("Rows become paragraphs; cells join with middle dot; empty cells skip; caption is a paragraph")
    func tableFlatten() {
        let doc = ShowNotesNormalizer.normalize(
            html: "<table><caption>Cap</caption><tr><td>A</td><td>B</td></tr><tr><td>C</td><td></td></tr></table>"
        )
        #expect(doc.blocks == [
            .paragraph(runs: [t("Cap")]),
            .paragraph(runs: [t("A"), t(" · "), t("B")]),
            .paragraph(runs: [t("C")]),
        ])
    }

    @Test("th cells behave like td")
    func tableHeaderCells() {
        let doc = ShowNotesNormalizer.normalize(html: "<table><tr><th>H1</th><th>H2</th></tr></table>")
        #expect(doc.blocks == [.paragraph(runs: [t("H1"), t(" · "), t("H2")])])
    }

    @Test("Nested tables flatten recursively into the cell")
    func nestedTable() {
        let doc = ShowNotesNormalizer.normalize(
            html: "<table><tr><td><table><tr><td>in</td></tr></table></td></tr></table>"
        )
        #expect(doc.blocks == [.paragraph(runs: [t("in")])])
    }

    // MARK: - Quotes

    @Test("blockquote wraps blocks")
    func quote() {
        let doc = ShowNotesNormalizer.normalize(html: "<blockquote><p>q</p></blockquote>")
        #expect(doc.blocks == [.quote(blocks: [.paragraph(runs: [t("q")])])])
    }

    @Test("Bare text inside a quote becomes a paragraph")
    func quoteBareText() {
        let doc = ShowNotesNormalizer.normalize(html: "<blockquote>quoted</blockquote>")
        #expect(doc.blocks == [.quote(blocks: [.paragraph(runs: [t("quoted")])])])
    }

    @Test("Quote nesting caps at two levels; the third flattens")
    func quoteDepthCap() {
        let doc = ShowNotesNormalizer.normalize(
            html: "<blockquote><blockquote><blockquote>deep</blockquote></blockquote></blockquote>"
        )
        #expect(doc.blocks == [
            .quote(blocks: [.quote(blocks: [.paragraph(runs: [t("deep")])])]),
        ])
    }

    // MARK: - Preformatted and code

    @Test("pre preserves whitespace, expands tabs to 4 spaces, drops edge blank lines")
    func preformatted() {
        let doc = ShowNotesNormalizer.normalize(html: "<pre>\nline1\n\ttabbed\n</pre>")
        #expect(doc.blocks == [.codeBlock(text: "line1\n    tabbed")])
    }

    @Test("pre does not parse inline markup")
    func preIgnoresInline() {
        let doc = ShowNotesNormalizer.normalize(html: "<pre><b>bold</b> stays</pre>")
        #expect(doc.blocks == [.codeBlock(text: "bold stays")])
    }

    @Test("code/tt/kbd/samp map to mono emphasis")
    func inlineCode() {
        let doc = ShowNotesNormalizer.normalize(html: "<p>use <code>let x</code> and <kbd>Ctrl</kbd></p>")
        #expect(doc.blocks == [.paragraph(runs: [
            t("use "),
            mono(t("let x")),
            t(" and "),
            mono(t("Ctrl")),
        ])])
    }

    // MARK: - sup/sub/q

    @Test("sup and sub map to superscript/subscript runs")
    func supSub() {
        let doc = ShowNotesNormalizer.normalize(html: "<p>x<sup>2</sup> and y<sub>1</sub></p>")
        #expect(doc.blocks == [.paragraph(runs: [
            t("x"),
            .superscript(runs: [t("2")]),
            t(" and y"),
            .subscript(runs: [t("1")]),
        ])])
    }

    @Test("q wraps its text in curly quotes")
    func quoted() {
        let doc = ShowNotesNormalizer.normalize(html: "<p>he said <q>hi</q>.</p>")
        #expect(doc.blocks == [.paragraph(runs: [
            t("he said "),
            t("\u{201C}"),
            t("hi"),
            t("\u{201D}"),
            t("."),
        ])])
    }

    // MARK: - Links

    @Test("Absolute http/https/mailto links survive as link runs")
    func permittedLinks() {
        let doc = ShowNotesNormalizer.normalize(
            html: "<p><a href=\"https://example.com/page\">go</a> "
                + "<a href=\"http://example.org\">h</a> "
                + "<a href=\"mailto:a@b.co\">mail</a></p>"
        )
        #expect(doc.blocks == [.paragraph(runs: [
            .link(url: url("https://example.com/page"), runs: [t("go")]),
            t(" "),
            .link(url: url("http://example.org"), runs: [t("h")]),
            t(" "),
            .link(url: url("mailto:a@b.co"), runs: [t("mail")]),
        ])])
    }

    @Test("Relative, anchor, protocol-relative, javascript:, data: and file: links keep only text")
    func impermittedLinks() {
        let cases: [(String, String)] = [
            ("/about", "rel"),
            ("#top", "anchor"),
            ("//cdn.example.com/x", "protoRel"),
            ("javascript:alert(1)", "js"),
            ("data:text/html;base64,x", "data"),
            ("file:///etc/hosts", "file"),
        ]
        for (href, label) in cases {
            let doc = ShowNotesNormalizer.normalize(html: "<p><a href=\"\(href)\">\(label)</a></p>")
            #expect(doc.blocks == [.paragraph(runs: [t(label)])], "href=\(href)")
        }
    }

    @Test("Links with empty text are dropped entirely")
    func emptyLink() {
        let doc = ShowNotesNormalizer.normalize(html: "<p><a href=\"https://example.com\"> </a>after</p>")
        #expect(doc.blocks == [.paragraph(runs: [t("after")])])
    }

    // MARK: - Images

    @Test("Images keep alt and declared width/height, indexed from 0 in document order")
    func imageAttributes() {
        let doc = ShowNotesNormalizer.normalize(
            html: "<p><img src=\"https://example.com/pic.png\" alt=\"photo\" width=\"100\" height=\"50\"> "
                + "and <img src=\"https://example.com/pic2.png\" width=\"100px\"></p>"
        )
        #expect(doc.blocks == [.paragraph(runs: [
            .image(ShowNotesImage(
                url: url("https://example.com/pic.png"),
                alt: "photo",
                declaredSize: CGSize(width: 100, height: 50),
                index: 0
            )),
            t(" and "),
            .image(ShowNotesImage(
                url: url("https://example.com/pic2.png"),
                alt: nil,
                declaredSize: nil,   // single-dimension declarations are not a size
                index: 1
            )),
        ])])
    }

    @Test("Declared width or height <= 2 is a tracking pixel and is dropped")
    func trackingPixels() {
        #expect(ShowNotesNormalizer
            .normalize(html: "<p><img src=\"https://e.example/t.gif\" width=\"1\" height=\"1\"></p>")
            .isEmpty)
        #expect(ShowNotesNormalizer
            .normalize(html: "<p><img src=\"https://e.example/t2.gif\" height=\"1\"></p>")
            .isEmpty)
    }

    @Test("Adjacent images with the same URL deduplicate")
    func adjacentDuplicateImages() {
        let doc = ShowNotesNormalizer.normalize(
            html: "<img src=\"https://example.com/dup.png\">\n<img src=\"https://example.com/dup.png\">"
        )
        #expect(doc.blocks == [
            .image(ShowNotesImage(url: url("https://example.com/dup.png"), alt: nil, declaredSize: nil, index: 0)),
        ])
    }

    @Test("Adjacent duplicate images also deduplicate as inline runs")
    func adjacentDuplicateInlineImages() {
        let doc = ShowNotesNormalizer.normalize(
            html: "<p><img src=\"https://example.com/d.png\"> <img src=\"https://example.com/d.png\"></p>"
        )
        #expect(doc.blocks == [.paragraph(runs: [
            .image(ShowNotesImage(url: url("https://example.com/d.png"), alt: nil, declaredSize: nil, index: 0)),
        ])])
    }

    @Test("Relative image URLs are dropped")
    func relativeImageDropped() {
        #expect(ShowNotesNormalizer
            .normalize(html: "<p><img src=\"/local.png\" alt=\"gone\"></p>")
            .isEmpty)
    }

    @Test("Inline images inside headings still receive document-order indices")
    func inlineImageIndex() {
        let doc = ShowNotesNormalizer.normalize(html: "<h2><img src=\"https://example.com/i.png\"></h2>")
        #expect(doc.blocks == [.heading(level: 2, runs: [
            .image(ShowNotesImage(url: url("https://example.com/i.png"), alt: nil, declaredSize: nil, index: 0)),
        ])])
    }

    @Test("Percent dimensions do not count as a declared size")
    func percentSize() {
        let doc = ShowNotesNormalizer.normalize(
            html: "<img src=\"https://example.com/p.png\" width=\"50%\" height=\"20%\">"
        )
        #expect(doc.blocks == [
            .image(ShowNotesImage(url: url("https://example.com/p.png"), alt: nil, declaredSize: nil, index: 0)),
        ])
    }

    // MARK: - hr / figure / details / dl

    @Test("hr becomes a divider block")
    func divider() {
        let doc = ShowNotesNormalizer.normalize(html: "<p>a</p><hr><p>b</p>")
        #expect(doc.blocks == [
            .paragraph(runs: [t("a")]),
            .divider,
            .paragraph(runs: [t("b")]),
        ])
    }

    @Test("figure maps to image block plus caption paragraph")
    func figureWithCaption() {
        let doc = ShowNotesNormalizer.normalize(
            html: "<figure><img src=\"https://example.com/f.png\" alt=\"cap\"><figcaption>The caption</figcaption></figure>"
        )
        #expect(doc.blocks == [
            .image(ShowNotesImage(url: url("https://example.com/f.png"), alt: "cap", declaredSize: nil, index: 0)),
            .paragraph(runs: [t("The caption")]),
        ])
    }

    @Test("details expands; summary becomes a strong paragraph")
    func detailsSummary() {
        let doc = ShowNotesNormalizer.normalize(html: "<details><summary>More</summary><p>body</p></details>")
        #expect(doc.blocks == [
            .paragraph(runs: [strong(t("More"))]),
            .paragraph(runs: [t("body")]),
        ])
    }

    @Test("dl: dt is a strong paragraph, dd a plain paragraph")
    func definitionList() {
        let doc = ShowNotesNormalizer.normalize(html: "<dl><dt>Term</dt><dd>Def</dd></dl>")
        #expect(doc.blocks == [
            .paragraph(runs: [strong(t("Term"))]),
            .paragraph(runs: [t("Def")]),
        ])
    }

    // MARK: - Deletions

    @Test("script/style/iframe/object/embed/video/audio/svg subtrees are deleted")
    func deletedSubtrees() {
        let doc = ShowNotesNormalizer.normalize(
            html: "<p>a<script>evil()</script>b</p>"
                + "<style>.x{}</style>"
                + "<iframe src=\"https://e.example/f\"></iframe>"
                + "<object data=\"o\"></object><embed src=\"e\">"
                + "<video src=\"v.mp4\"></video><audio src=\"a.mp3\"></audio>"
                + "<svg><text>v</text></svg>"
                + "tail"
        )
        #expect(doc.blocks == [
            .paragraph(runs: [t("a"), t("b")]),
            .paragraph(runs: [t("tail")]),
        ])
    }

    @Test("Comments are deleted")
    func comments() {
        let doc = ShowNotesNormalizer.normalize(html: "<p>a<!-- hidden -->b</p>")
        #expect(doc.blocks == [.paragraph(runs: [t("a"), t("b")])])
    }

    @Test("Presentational attributes are ignored")
    func attributesIgnored() {
        let doc = ShowNotesNormalizer.normalize(
            html: "<p align=\"center\" style=\"color:red\" class=\"c\" id=\"i\" color=\"blue\">x</p>"
        )
        #expect(doc.blocks == [.paragraph(runs: [t("x")])])
    }

    // MARK: - Empty-block folding

    @Test("Consecutive empty paragraphs collapse")
    func emptyParagraphs() {
        let doc = ShowNotesNormalizer.normalize(html: "<p></p><p> </p><p>&nbsp;</p><p>real</p>")
        #expect(doc.blocks == [.paragraph(runs: [t("real")])])
    }

    @Test("Document edges: leading and trailing blank blocks are removed")
    func documentEdges() {
        let doc = ShowNotesNormalizer.normalize(html: "<p> </p><p>keep</p><p></p>")
        #expect(doc.blocks == [.paragraph(runs: [t("keep")])])
    }

    // MARK: - Input limits

    @Test("Empty and whitespace-only inputs produce empty documents")
    func emptyInput() {
        #expect(ShowNotesNormalizer.normalize(html: "").isEmpty)
        #expect(ShowNotesNormalizer.normalize(html: "   \n\t ").isEmpty)
    }

    @Test("Inputs over 2MB return an empty document")
    func oversizeInput() {
        let huge = String(repeating: "a", count: ShowNotesNormalizer.maximumInputBytes + 1)
        #expect(ShowNotesNormalizer.normalize(html: huge).isEmpty)
    }

    @Test("Abnormally large parse trees return an empty document")
    func tooManyNodes() {
        let many = String(repeating: "<p>x</p>", count: 25_100)   // 50,200 nodes > 50k
        #expect(ShowNotesNormalizer.normalize(html: many).isEmpty)
    }

    @Test("Nesting past the parse-depth ceiling returns an empty document")
    func tooDeep() {
        let deep = String(repeating: "<div>", count: ShowNotesNormalizer.maximumParseDepth + 1)
            + "core" + String(repeating: "</div>", count: ShowNotesNormalizer.maximumParseDepth + 1)
        #expect(ShowNotesNormalizer.normalize(html: deep).isEmpty)
    }

    @Test("Nesting within the parse-depth ceiling keeps the text")
    func deepButLegalNestingKeepsText() {
        // Divs unwrap presentationally, so the payload survives as a plain
        // paragraph while the walk still descends the full depth.
        let depth = ShowNotesNormalizer.maximumParseDepth / 2
        let html = String(repeating: "<div>", count: depth) + "deep quote"
            + String(repeating: "</div>", count: depth)
        let plain = Self.flattenedText(of: ShowNotesNormalizer.normalize(html: html))
        #expect(plain.contains("deep quote"))
    }
}
