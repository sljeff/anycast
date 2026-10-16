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
}
