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
