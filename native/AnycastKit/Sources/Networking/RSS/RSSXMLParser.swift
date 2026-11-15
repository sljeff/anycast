import Foundation

/// XML pull-parser producing exactly the fields webfeed_plus's RssFeed
/// exposes to parseFeedResponse (G7). Matching rules mirrored from the
/// webfeed_plus source:
/// - Root must be `<rss>` or `<rdf:RDF>`; anything else is a parse failure
///   (→ feed skipped, like RssFeed.parse throwing).
/// - Namespaced elements match by their LITERAL written prefix
///   (`itunes:duration`), not the resolved namespace.
/// - Field elements are DIRECT children of channel/item; first occurrence
///   wins (findElements(...).firstOrNull).
/// - `innerText` concatenates all descendant text (CDATA included).
/// - The Dart xml package tolerates undefined entities (`&nbsp;` becomes
///   literal text and parsing continues); Foundation's XMLParser aborts the
///   whole document instead. `escapingUndefinedEntities` pre-escapes such
///   `&` so both worlds yield the same literal text.
final class RSSXMLParser: NSObject, XMLParserDelegate {

    struct Feed {
        var title: String?
        var description: String?
        var link: String?
        var imageURL: String?
        var iTunesImageHref: String?
        var iTunesAuthor: String?
        var iTunesOwnerEmail: String?
        var categories: [String] = []
        var items: [Item] = []
    }

    struct Item {
        var title: String?
        var description: String?
        var pubDateEpochMilliseconds: Int64?
        /// The first `<enclosure>` element's `url` attribute — nil both when
        /// the element is absent AND when it lacks a url. `hasEnclosure`
        /// distinguishes the two: Dart's `RssEnclosure.parse` yields a
        /// non-null object whenever the element exists, and
        /// `item.enclosure == null` (not `url == null`) is what skips an
        /// episode.
        var enclosureURL: String?
        var hasEnclosure = false
        var iTunesSummary: String?
        var iTunesDurationMilliseconds: Int64?
        var iTunesImageHref: String?
        /// webfeed's `findElements(...).firstOrNull` binds on the FIRST
        /// element even when its content fails to parse — so "seen" and
        /// "non-nil" are different states.
        var seen: Set<String> = []
    }

    private enum TextSink {
        case channelTitle, channelDescription, channelLink
        case channelCategory
        case imageURL
        case iTunesAuthor, iTunesOwnerEmail
        case itemTitle, itemDescription, itemPubDate
        case iTunesSummary, iTunesDuration
    }

    private struct TextTarget {
        let endDepth: Int
        let sink: TextSink
        var buffer: String
    }

    private var feed = Feed()
    private var currentItem: Item?
    private var stack: [String] = []
    private var rootIsRDF = false
    private var parseFailed = false
    private var textTargets: [TextTarget] = []

    static func parse(data: Data) -> Feed? {
        let delegate = RSSXMLParser()
        let parser = XMLParser(data: escapingUndefinedEntities(data))
        parser.delegate = delegate
        parser.shouldResolveExternalEntities = false
        guard parser.parse(), !delegate.parseFailed else { return nil }
        return delegate.feed
    }

    /// Escapes every `&` that does not begin a well-formed entity reference
    /// (`&amp;`-style predefined names, `&#123;`, `&#x1F;`) so XMLParser
    /// reports the literal text the Dart xml package would produce for
    /// undefined entities and stray ampersands. CDATA sections are copied
    /// verbatim — entities are not recognized there in either world.
    /// Comments are left to the scanner: their content is never surfaced.
    static func escapingUndefinedEntities(_ data: Data) -> Data {
        let bytes = [UInt8](data)
        let amp = UInt8(ascii: "&"), semicolon = UInt8(ascii: ";")
        let hash = UInt8(ascii: "#"), lt = UInt8(ascii: "<")
        let ampEscaped = [UInt8]("&amp;".utf8)
        let cdataStart = [UInt8]("<![CDATA[".utf8)
        var out = [UInt8]()
        out.reserveCapacity(bytes.count)
        var i = 0

        func isNameByte(_ b: UInt8) -> Bool {
            (b >= UInt8(ascii: "a") && b <= UInt8(ascii: "z"))
                || (b >= UInt8(ascii: "A") && b <= UInt8(ascii: "Z"))
                || (b >= UInt8(ascii: "0") && b <= UInt8(ascii: "9"))
        }

        while i < bytes.count {
            // Copy CDATA sections through untouched.
            if bytes[i] == lt, bytes.count - i >= 9,
               Array(bytes[i..<(i + 9)]) == cdataStart {
                var j = i + 9
                out.append(contentsOf: bytes[i..<j])
                while j < bytes.count {
                    out.append(bytes[j])
                    if bytes[j] == UInt8(ascii: ">"), j >= 2,
                       bytes[j - 1] == UInt8(ascii: "]"), bytes[j - 2] == UInt8(ascii: "]") {
                        j += 1
                        break
                    }
                    j += 1
                }
                i = j
                continue
            }

            if bytes[i] == amp {
                // Reference must be `&name;` or `&#digits;`/`&#xHEX;` within a
                // short window; only the five predefined names are valid XML.
                var j = i + 1
                var name = [UInt8]()
                while j < bytes.count, j - i <= 10, bytes[j] != semicolon,
                      isNameByte(bytes[j]) || (bytes[j] == hash && j == i + 1) {
                    name.append(bytes[j])
                    j += 1
                }
                let wellFormed = j < bytes.count
                    && bytes[j] == semicolon
                    && !name.isEmpty
                    && (name[0] == hash
                        || name == [UInt8]("amp".utf8)
                        || name == [UInt8]("apos".utf8)
                        || name == [UInt8]("gt".utf8)
                        || name == [UInt8]("lt".utf8)
                        || name == [UInt8]("quot".utf8))
                if wellFormed {
                    out.append(contentsOf: bytes[i...j])
                    i = j + 1
                } else {
                    out.append(contentsOf: ampEscaped)
                    i += 1
                }
                continue
            }

            out.append(bytes[i])
            i += 1
        }
        return Data(out)
    }

    // MARK: - Structure

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        let name = qName ?? elementName
        stack.append(name)

        if stack.count == 1 {
            rootIsRDF = (name == "rdf:RDF")
            if name != "rss" && name != "rdf:RDF" {
                parseFailed = true
                parser.abortParsing()
            }
            return
        }

        let parent = stack[stack.count - 2]
        let directChildOfRoot = stack.count == 2

        // Items: children of <channel> (RSS 2.0) or of the RDF root.
        if name == "item", currentItem == nil,
           parent == "channel" || (rootIsRDF && directChildOfRoot) {
            currentItem = Item()
            return
        }

        // Item fields: direct children of the current <item>.
        if currentItem != nil, parent == "item" {
            let seen = currentItem?.seen ?? []
            func first(_ field: String) -> Bool {
                if seen.contains(field) { return false }
                currentItem?.seen.insert(field)
                return true
            }
            switch name {
            case "title" where first("title"):
                beginText(.itemTitle)
            case "description" where first("description"):
                beginText(.itemDescription)
            case "pubDate" where first("pubDate"):
                beginText(.itemPubDate)
            case "enclosure" where first("enclosure"):
                currentItem?.enclosureURL = attributeDict["url"]
                currentItem?.hasEnclosure = true
            case "itunes:summary" where first("itunes:summary"):
                beginText(.iTunesSummary)
            case "itunes:duration" where first("itunes:duration"):
                beginText(.iTunesDuration)
            case "itunes:image" where first("itunes:image"):
                currentItem?.iTunesImageHref = attributeDict["href"]
            default:
                break
            }
            return
        }

        // Channel fields: direct children of <channel>.
        if parent == "channel" {
            switch name {
            case "title" where feed.title == nil: beginText(.channelTitle)
            case "description" where feed.description == nil: beginText(.channelDescription)
            case "link" where feed.link == nil: beginText(.channelLink)
            case "category": beginText(.channelCategory)
            case "itunes:author" where feed.iTunesAuthor == nil: beginText(.iTunesAuthor)
            case "itunes:image" where feed.iTunesImageHref == nil:
                feed.iTunesImageHref = attributeDict["href"]
            default: break
            }
            return
        }

        // <image><url> — under <channel> or under the RDF root.
        if name == "url", parent == "image", feed.imageURL == nil {
            beginText(.imageURL)
        }
        // <itunes:owner><itunes:email>.
        if name == "itunes:email", parent == "itunes:owner", feed.iTunesOwnerEmail == nil {
            beginText(.iTunesOwnerEmail)
        }
    }

    private func beginText(_ sink: TextSink) {
        textTargets.append(TextTarget(endDepth: stack.count, sink: sink, buffer: ""))
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        appendText(string)
    }

    func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
        appendText(String(decoding: CDATABlock, as: UTF8.self))
    }

    private func appendText(_ string: String) {
        for index in textTargets.indices {
            textTargets[index].buffer += string
        }
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        var remaining: [TextTarget] = []
        for target in textTargets {
            if target.endDepth == stack.count {
                finishText(target.sink, text: target.buffer)
            } else if target.endDepth > stack.count {
                // Element closed early (malformed); drop the target.
            } else {
                remaining.append(target)
            }
        }
        textTargets = remaining

        if (qName ?? elementName) == "item", currentItem != nil {
            if let item = currentItem {
                feed.items.append(item)
            }
            currentItem = nil
        }

        stack.removeLast()
    }

    func parser(_ parser: XMLParser, parseErrorOccurred parseError: Error) {
        parseFailed = true
    }

    // MARK: - Field finalization

    private func finishText(_ sink: TextSink, text: String) {
        switch sink {
        case .channelTitle: feed.title = text
        case .channelDescription: feed.description = text
        case .channelLink: feed.link = text
        case .channelCategory: feed.categories.append(text)
        case .imageURL: feed.imageURL = text
        case .iTunesAuthor: feed.iTunesAuthor = text
        case .iTunesOwnerEmail: feed.iTunesOwnerEmail = text
        case .itemTitle: currentItem?.title = text
        case .itemDescription: currentItem?.description = text
        case .itemPubDate: currentItem?.pubDateEpochMilliseconds = RSSDate.parse(text)
        case .iTunesSummary: currentItem?.iTunesSummary = text
        case .iTunesDuration:
            currentItem?.iTunesDurationMilliseconds = RSSXMLParser.parseITunesDuration(text)
        }
    }

    /// webfeed_plus Itunes._parseDuration: split on ':', take the LAST three
    /// parts as h/m/s; non-integer parts (including fractional seconds like
    /// "72.5") fall back to 0; an empty element means nil (no duration).
    /// Dart `int.tryParse` tolerates surrounding whitespace (" 3600" parses
    /// to 3600); Swift's `Int` does not, so parts are trimmed first.
    static func parseITunesDuration(_ string: String) -> Int64? {
        guard !string.isEmpty else { return nil }
        let parts = string.split(separator: ":", omittingEmptySubsequences: false)
        func intPart(_ part: Substring) -> Int { Int(String(part).dartTrimmed()) ?? 0 }
        var hours = 0, minutes = 0, seconds = 0
        if parts.count > 2 { hours = intPart(parts[parts.count - 3]) }
        if parts.count > 1 { minutes = intPart(parts[parts.count - 2]) }
        seconds = intPart(parts[parts.count - 1])
        return Int64(hours * 3_600 + minutes * 60 + seconds) * 1000
    }
}
