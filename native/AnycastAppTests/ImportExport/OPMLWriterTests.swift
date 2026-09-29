import Foundation
import Testing
import AnycastKit
@testable import Anycast

/// OPMLWriter parity (lib/widgets/import_export.dart:366-378): the export
/// must byte-match the Dart `opml` package output — verified by round-tripping
/// the real M0 export fixture `test/fixtures/opml/app_export.opml` (generated
/// by the shipped Dart code) and by pinning the xml-package escaping rules.
@MainActor
struct OPMLWriterTests {

    /// Rebuilds SubscriptionRows from the fixture's outline attributes
    /// (text→description, title→title, xmlUrl→rssFeedUrl) the way the DB
    /// list would feed generateOPML.
    private func fixtureRows() throws -> [SubscriptionRow] {
        let url = TestRepoAssets.repoRoot
            .appendingPathComponent("test/fixtures/opml/app_export.opml")
        let collector = OutlineAttributeCollector()
        let parser = XMLParser(data: try Data(contentsOf: url))
        parser.delegate = collector
        #expect(parser.parse())
        return collector.rows
    }

    @Test("Round-trip: writer reproduces the Dart-generated fixture byte for byte")
    func fixtureRoundTrip() throws {
        let url = TestRepoAssets.repoRoot
            .appendingPathComponent("test/fixtures/opml/app_export.opml")
        let fixture = try String(contentsOf: url, encoding: .utf8)
        let rows = try fixtureRows()

        #expect(rows.count > 10)   // a real export, not a stub
        let written = OPMLWriter.document(subscriptions: rows)
        #expect(written == fixture)
    }

    @Test("Skeleton: head title and empty body")
    func skeleton() {
        let written = OPMLWriter.document(subscriptions: [])
        #expect(written == """
            <?xml version="1.0" encoding="UTF-8"?>
            <opml version="2.0">
              <head>
                <title>Anycast Subscriptions</title>
              </head>
              <body>
              </body>
            </opml>
            """)
    }

    @Test("Attribute order text, title, type, xmlUrl (OpmlOutline.toMap)")
    func attributeOrder() {
        let row = SubscriptionRow(
            rssFeedUrl: "https://example.com/feed.xml",
            title: "Example",
            description: "An example feed"
        )
        let written = OPMLWriter.document(subscriptions: [row])
        #expect(written.contains(
            "    <outline text=\"An example feed\" title=\"Example\" type=\"rss\" xmlUrl=\"https://example.com/feed.xml\"/>"
        ))
    }

    @Test("Escaping: xml-package double-quote attribute rules")
    func escaping() {
        let row = SubscriptionRow(
            rssFeedUrl: "https://example.com/a&b\"c<d\n\r\te.xml",
            title: "T",
            description: "plain"
        )
        let written = OPMLWriter.document(subscriptions: [row])
        // & " < \n \r \t → &amp; &quot; &lt; &#xA; &#xD; &#x9;
        #expect(written.contains("xmlUrl=\"https://example.com/a&amp;b&quot;c&lt;d&#xA;&#xD;&#x9;e.xml\""))
    }

    @Test("Escaping: discouraged control codes become uppercase hex references")
    func controlCodes() {
        let row = SubscriptionRow(rssFeedUrl: "u", title: "T\u{01}\u{7F}", description: nil)
        let written = OPMLWriter.document(subscriptions: [row])
        #expect(written.contains("title=\"T&#x1;&#x7F;\""))
    }

    @Test("Nil title/description omit the attribute (K4 tolerance for the Dart force-unwrap)")
    func nilFields() {
        let row = SubscriptionRow(rssFeedUrl: "https://example.com/f", title: nil, description: nil)
        let written = OPMLWriter.document(subscriptions: [row])
        #expect(written.contains("    <outline type=\"rss\" xmlUrl=\"https://example.com/f\"/>"))
    }

    @Test("Written OPML re-parses through the AnycastKit parser")
    func reparses() throws {
        let rows = [
            SubscriptionRow(rssFeedUrl: "https://a.example/f", title: "A", description: "a"),
            SubscriptionRow(rssFeedUrl: "https://b.example/f", title: "B", description: nil),
        ]
        let entries = try OPMLParser.parse(data: Data(OPMLWriter.document(subscriptions: rows).utf8))
        #expect(entries.map(\.title) == ["A", "B"])
        #expect(entries.map(\.xmlURL) == ["https://a.example/f", "https://b.example/f"])
    }
}

/// Test-local outline reader (OPMLParser.Entry drops the text attribute, and
/// the writer parity needs description too).
private final class OutlineAttributeCollector: NSObject, XMLParserDelegate {
    var rows: [SubscriptionRow] = []

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        guard (qName ?? elementName) == "outline" else { return }
        rows.append(SubscriptionRow(
            rssFeedUrl: attributeDict["xmlUrl"],
            title: attributeDict["title"],
            description: attributeDict["text"]
        ))
    }
}
