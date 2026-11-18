import Foundation
import Testing
@testable import AnycastKit

/// Episode description source: a markup `<description>` wins over
/// `itunes:summary` (which some hosts publish tag-stripped, gluing
/// paragraphs together); otherwise the Dart order — summary, then
/// description — is kept.
struct PodcastFeedParserTests {

    private func episodeDescription(item: String) -> String? {
        let xml = """
        <rss version="2.0" xmlns:itunes="http://www.itunes.com/dtds/podcast-1.0.dtd">\
        <channel><title>t</title>\
        <item><title>e</title><enclosure url="https://example.com/e.mp3" type="audio/mpeg" length="1"/>\
        \(item)</item>\
        </channel></rss>
        """
        let parsed = PodcastFeedParser.parse(
            rssFeedUrl: "https://example.com/feed.xml",
            xmlData: Data(xml.utf8),
            nowEpochMilliseconds: 0
        )
        return parsed?.feedEpisodes.first?.description
    }

    @Test("markup description wins over a tag-stripped summary")
    func markupDescriptionPreferred() {
        // The Moth (Amperwave): summary is the description minus its tags.
        let description = episodeDescription(item: """
        <description><![CDATA[ <p>Atlantic Public Media.</p><p>Storytellers:</p><p>Kristy</p> ]]></description>\
        <itunes:summary>Atlantic Public Media.Storytellers:Kristy</itunes:summary>
        """)
        #expect(description == "<p>Atlantic Public Media.</p><p>Storytellers:</p><p>Kristy</p>")
    }

    @Test("plain description keeps the summary first")
    func plainDescriptionKeepsSummary() {
        let description = episodeDescription(item: """
        <description>Short teaser &lt;br/&gt; text</description>\
        <itunes:summary> Full summary\n\nSecond paragraph </itunes:summary>
        """)
        #expect(description == "Full summary\n\nSecond paragraph")
    }

    @Test("summary alone is used")
    func summaryOnly() {
        #expect(episodeDescription(item: "<itunes:summary>Only summary</itunes:summary>") == "Only summary")
    }

    @Test("description alone is used, markup or plain")
    func descriptionOnly() {
        #expect(episodeDescription(item: "<description><![CDATA[<p>Only</p>]]></description>") == "<p>Only</p>")
        #expect(episodeDescription(item: "<description>Plain only</description>") == "Plain only")
    }

    @Test("neither field leaves the description nil")
    func neither() {
        #expect(episodeDescription(item: "") == nil)
    }

    // MARK: - Stored rows are never rewritten

    private func feed(pubDate: String, description: String, summary: String) -> Data {
        Data("""
        <rss version="2.0" xmlns:itunes="http://www.itunes.com/dtds/podcast-1.0.dtd">\
        <channel><title>t</title>\
        <item><title>e</title><enclosure url="https://example.com/e.mp3" type="audio/mpeg" length="1"/>\
        <pubDate>\(pubDate)</pubDate>\
        <description><![CDATA[\(description)]]></description>\
        <itunes:summary>\(summary)</itunes:summary></item>\
        </channel></rss>
        """.utf8)
    }

    @Test("a refresh never re-emits an already-stored episode, so its stored description stays as saved")
    func refreshLeavesStoredEpisodeAlone() throws {
        let url = "https://example.com/feed.xml"
        let data = feed(pubDate: "Mon, 01 Jan 2024 00:00:00 GMT",
                        description: "<p>A.</p><p>B.</p>", summary: "A.B.")
        let parsed = try #require(PodcastFeedParser.parse(
            rssFeedUrl: url, xmlData: data, nowEpochMilliseconds: 0))
        let episodePubDate = try #require(parsed.feedEpisodes.first?.pubDate)

        // The user already stored this episode with the old glued text.
        let stored = SubscriptionRow(id: 1, rssFeedUrl: url, lastUpdated: episodePubDate)
        let result = SaveNewEpisodes.compute(fetched: [parsed], local: [stored])

        #expect(result.feedEpisodes.isEmpty)
        #expect(result.subscriptions.isEmpty)
    }

    @Test("only genuinely newer episodes are emitted, with the new description rule")
    func refreshEmitsOnlyNewerEpisodes() throws {
        let url = "https://example.com/feed.xml"
        let data = feed(pubDate: "Mon, 01 Jan 2024 00:00:00 GMT",
                        description: "<p>A.</p><p>B.</p>", summary: "A.B.")
        let parsed = try #require(PodcastFeedParser.parse(
            rssFeedUrl: url, xmlData: data, nowEpochMilliseconds: 0))
        let episodePubDate = try #require(parsed.feedEpisodes.first?.pubDate)

        let stored = SubscriptionRow(id: 1, rssFeedUrl: url, lastUpdated: episodePubDate - 1)
        let result = SaveNewEpisodes.compute(fetched: [parsed], local: [stored])

        #expect(result.feedEpisodes.map(\.description) == ["<p>A.</p><p>B.</p>"])
    }
}
