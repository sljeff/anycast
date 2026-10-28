import Testing
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

    @Test("Plain input keeps its own line breaks; non-break markup stays literal")
    func plainTextKeepsPlainInputBreaks() {
        #expect(DisplayText.plainText(fromHTML: "Listen to <em>Planet Money</em> today")
                == "Listen to <em>Planet Money</em> today")
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
