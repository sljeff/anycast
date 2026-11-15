import Testing
import UIKit
import AnycastKit
@testable import Anycast

/// Plain-text feed fields with stray markup render without raw tags or entities.
struct DisplayTextTests {

    @Test("Entities decode and <br/> becomes a line break")
    func decodesStrayMarkup() {
        #expect(DisplayText.clean("Dia's mother&nbsp;surprises") == "Dia's mother\u{00A0}surprises")
        #expect(DisplayText.clean("How about us? <br/><br/>It seems simple")
                == "How about us? \n\nIt seems simple")
        #expect(DisplayText.clean("Tom &amp; Jerry") == "Tom & Jerry")
    }

    @Test("Text without markup passes through unchanged")
    func plainPassthrough() {
        #expect(DisplayText.clean("Just words, 100% plain.") == "Just words, 100% plain.")
        #expect(DisplayText.clean("") == "")
    }

    @Test("Block ends become blank lines and <br>/<li> line breaks")
    func plainTextKeepsBlockStructure() {
        let paragraphs = "<p>Ends in 2022.</p><p>This one</p>"
        #expect(DisplayText.plainText(fromHTML: paragraphs) == "Ends in 2022.\n\nThis one")
        #expect(DisplayText.singleLine(fromHTML: paragraphs) == "Ends in 2022. This one")
        #expect(DisplayText.plainText(fromHTML: "<ul><li>a</li><li>b</li></ul>") == "a\nb")
        #expect(DisplayText.plainText(fromHTML: "<p>line<br>break</p>") == "line\nbreak")
    }

    @Test("Markup collapses source whitespace; empty paragraphs collapse")
    func plainTextCollapsesMarkupWhitespace() {
        #expect(DisplayText.plainText(fromHTML: "<p>a\n   b</p>") == "a b")
        #expect(DisplayText.plainText(fromHTML: "<p>one</p><p></p><p><br></p><p>two</p>") == "one\n\ntwo")
        #expect(DisplayText.plainText(fromHTML: "<p>Tom&nbsp;&amp;&nbsp;Jerry</p>") == "Tom & Jerry")
    }

    @Test("Plain input keeps its own line breaks; real mid-string tags are read as markup")
    func plainTextKeepsPlainInputBreaks() {
        #expect(DisplayText.plainText(fromHTML: "Listen to <em>Planet Money</em> today")
                == "Listen to Planet Money today")
        #expect(DisplayText.plainText(fromHTML: "Para one.\n\n\n\nPara two.\nLine.")
                == "Para one.\n\nPara two.\nLine.")
        #expect(DisplayText.plainText(fromHTML: "") == "")
        #expect(DisplayText.singleLine(fromHTML: "") == "")
    }

    @Test("Paragraph sentinels (U+2028/2029) are not matched by the horizontal-space class")
    func sentinelsAreNotHorizontalSpace() {
        #expect("\u{2028}\u{2029}".replacingOccurrences(
            of: "[\\t\\f\\x{0B}\\p{Zs}]+", with: " ", options: .regularExpression
        ) == "\u{2028}\u{2029}")
    }

    @Test("Angle brackets in prose never lose content")
    func angleBracketProseIsLossless() {
        #expect(DisplayText.clean("for x<y values") == "for x<y values")
        #expect(DisplayText.clean("Tickets at <event> sold out") == "Tickets at <event> sold out")
        #expect(DisplayText.clean("Use <?xml version=\"1.0\"?> header")
                == "Use <?xml version=\"1.0\"?> header")
        #expect(DisplayText.clean("values <x> and <y>") == "values <x> and <y>")
        #expect(DisplayText.clean("I <3 podcasts") == "I <3 podcasts")
    }

    @Test("Markup other than <br> stays literal instead of being stripped")
    func nonBreakMarkupStaysLiteral() {
        #expect(DisplayText.clean("hi <b>there</b> friend") == "hi <b>there</b> friend")
        #expect(DisplayText.clean("escaped &lt;b&gt; decodes once") == "escaped <b> decodes once")
    }
}

/// Episode text whose field starts as plain prose and carries HTML mid-string
/// (NPR, shapes copied from the live feeds) or escaped tags. Every surface
/// shows clean text, and angle brackets in prose survive.
@MainActor
struct EpisodeMarkupTextTests {

    /// What the player and Detail sheet paint for a description.
    private func notes(_ html: String) async -> NSAttributedString {
        let store = ShowNotesStore()
        let style = ShowNotesStyle()
        let traits = UITraitCollection()
        if case .text(let plain) = HtmlText.displayPayload(for: html) {
            return store.attributedFallback(
                plain: DisplayText.plainText(fromHTML: plain), style: style, traits: traits
            )
        }
        return await store.attributedString(html: html, style: style, traits: traits)
    }

    private func linkTargets(in text: NSAttributedString) -> [String] {
        var targets: [String] = []
        text.enumerateAttribute(.link, in: NSRange(location: 0, length: text.length)) { value, _, _ in
            if let url = value as? URL { targets.append(url.absoluteString) }
            if let string = value as? String { targets.append(string) }
        }
        return targets
    }

    nonisolated private static let cleaned: [(input: String, card: String, notes: String)] = [
        (
            "Light is the answer.<br/><br/>For years, <em>candles</em> ruled.",
            "Light is the answer. For years, candles ruled.",
            "Light is the answer.\nFor years, candles ruled."
        ),
        (
            "Hosts: <a href=\"https://www.wmot.org/people/chloe-kimes\"target=\"_blank\"   >Chloe Kimes</a> and more",
            "Hosts: Chloe Kimes and more",
            "Hosts: Chloe Kimes and more"
        ),
        (
            "Listen to &lt;em&gt;Planet Money&lt;/em&gt;&lt;br/&gt;&lt;a href=&quot;https://n.pr/x&quot;&gt;link&lt;/a&gt;",
            "Listen to Planet Money link",
            "Listen to Planet Money\u{2028}link"
        ),
        (
            "<p>&lt;em&gt;Hi&lt;/em&gt; there</p>",
            "Hi there",
            "Hi there"
        ),
        (
            "Note<br><font color=\"#000000\" face=\"Open Sans, sans-serif\"><em>Read this</em></font>",
            "Note Read this",
            "Note\u{2028}Read this"
        ),
        (
            "Intro:<br/><br/><ul class=\"rte2-style-ul\"><li>One</li><li>Two</li></ul>",
            "Intro: One Two",
            "Intro:\n•\tOne\n•\tTwo"
        ),
    ]

    @Test("Card text drops tags on escaped and unescaped input", arguments: Self.cleaned)
    func cardText(_ sample: (input: String, card: String, notes: String)) {
        #expect(DisplayText.singleLine(fromHTML: sample.input) == sample.card)
    }

    @Test("Player and Detail paint no tags on escaped and unescaped input", arguments: Self.cleaned)
    func notesText(_ sample: (input: String, card: String, notes: String)) async {
        #expect(await notes(sample.input).string == sample.notes)
    }

    @Test("Mid-string links stay tappable, escaped or not")
    func linksSurvive() async {
        #expect(linkTargets(in: await notes("See <a href=\"https://n.pr/x\">this</a>")) == ["https://n.pr/x"])
        #expect(linkTargets(in: await notes("See &lt;a href=&quot;https://n.pr/x&quot;&gt;this&lt;/a&gt;")) == ["https://n.pr/x"])
    }

    @Test("Plain-field line breaks survive next to mid-string tags")
    func keepsLinesAroundTags() {
        #expect(DisplayText.plainText(fromHTML: "Line one\n<em>Line two</em>\n\nPara")
                == "Line one\nLine two\n\nPara")
    }

    @Test("Prose brackets beside real tags are kept")
    func proseBesideTags() async {
        let samples: [(String, String)] = [
            ("for x<y values <em>today</em>", "for x<y values today"),
            ("I <3 <a href=\"https://x.y\">this</a>", "I <3 this"),
            ("Emma <<AY-oh-win>> Smith<br>Next", "Emma <<AY-oh-win>> Smith\nNext"),
            ("Tickets at <event> sold out<br/>Doors at <8pm", "Tickets at <event> sold out\nDoors at <8pm"),
        ]
        for (input, expected) in samples {
            #expect(DisplayText.plainText(fromHTML: input) == expected)
            let painted = await notes(input).string.replacingOccurrences(of: "\u{2028}", with: "\n")
            #expect(painted == expected)
        }
    }

    @Test("Bracketed prose that only resembles a tag stays literal")
    func tagLookalikesStayLiteral() async {
        for prose in [
            "for x<y values",
            "Use the <em> tag for emphasis",
            "values <i> and <b>",
            "a<b and c>d",
            "a closing </a> alone",
            "escaped &lt;b&gt; alone",
        ] {
            let expected = prose.replacingOccurrences(of: "&lt;", with: "<")
                .replacingOccurrences(of: "&gt;", with: ">")
            #expect(DisplayText.plainText(fromHTML: prose) == expected)
            #expect(await notes(prose).string == expected)
        }
    }
}
