import Foundation

/// parseOPML (pages/feeds.dart:199-226): walk EVERY <outline> recursively
/// (G6); `xmlUrl` attribute required, `title` falling back to `text`; an
/// entry missing either is skipped. Parse failures surface as errors to the
/// caller (UI shows "no valid links" on empty results).
public enum OPMLParser {

    public struct Entry: Equatable, Sendable {
        public var title: String
        public var xmlURL: String

        public init(title: String, xmlURL: String) {
            self.title = title
            self.xmlURL = xmlURL
        }
    }

    public static func parse(data: Data) throws -> [Entry] {
        let delegate = OutlineCollector()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        guard parser.parse() else {
            throw parser.parserError ?? CocoaError(.propertyListReadCorrupt)
        }
        return delegate.entries
    }

    public static func parse(fileURL: URL) throws -> [Entry] {
        try parse(data: try Data(contentsOf: fileURL))
    }

    private final class OutlineCollector: NSObject, XMLParserDelegate {
        var entries: [Entry] = []

        func parser(
            _ parser: XMLParser,
            didStartElement elementName: String,
            namespaceURI: String?,
            qualifiedName qName: String?,
            attributes attributeDict: [String: String] = [:]
        ) {
            let name = qName ?? elementName
            guard name == "outline",
                  let xmlURL = attributeDict["xmlUrl"],
                  // title falls back to text; an EMPTY title is still a title
                  // (getAttribute semantics — only absence skips).
                  let title = attributeDict["title"] ?? attributeDict["text"]
            else { return }
            entries.append(Entry(title: title, xmlURL: xmlURL))
        }
    }
}
