import Foundation
import Testing
@testable import Anycast

/// Chapters read from show notes and the notes' seekable timestamps
/// (EpisodeChapters): line-leading timestamps become chapters only when
/// there are at least two and they ascend.
@MainActor
struct EpisodeChaptersTests {

    private let notes = """
    We discover what we believe might be the original recipe for Coca-Cola.

    (00:00:00) Act One: The formula for Coca-Cola is one of the most jealously guarded trade secrets. (26 minutes)

    (00:26:23) Act Two: Jake Halpern tells this story about document expert John Reznikoff.
    """

    @Test("Bracketed h:mm:ss lines become chapters with their titles")
    func parsesBracketedLines() {
        let chapters = EpisodeChapters.parse(plainText: notes)
        #expect(chapters.map(\.startMilliseconds) == [0, (26 * 60 + 23) * 1000])
        #expect(chapters.first?.title.hasPrefix("Act One: The formula") == true)
        #expect(chapters.last?.title.hasPrefix("Act Two: Jake Halpern") == true)
    }

    @Test("m:ss starts, dash separators and square brackets parse too")
    func parsesOtherForms() {
        let chapters = EpisodeChapters.parse(plainText: "0:00 - Intro\n[12:05] News\n1:02:03 – Interview")
        #expect(chapters.map(\.startMilliseconds) == [0, 725_000, 3_723_000])
        #expect(chapters.map(\.title) == ["Intro", "News", "Interview"])
    }

    @Test("One timestamp, or starts out of order, mean no chapters")
    func rejectsWeakLists() {
        #expect(EpisodeChapters.parse(plainText: "(00:10:00) Only one").isEmpty)
        #expect(EpisodeChapters.parse(plainText: "10:00 Later\n05:00 Earlier").isEmpty)
        #expect(EpisodeChapters.parse(plainText: "Mentioned at 10:00 and 20:00 mid-sentence.").isEmpty)
    }

    @Test("The playing chapter is the last one started")
    func currentIndex() {
        let chapters = EpisodeChapters.parse(plainText: notes)
        #expect(EpisodeChapters.index(at: 1_000, in: chapters) == 0)
        #expect(EpisodeChapters.index(at: (26 * 60 + 23) * 1000, in: chapters) == 1)
        #expect(EpisodeChapters.index(at: 0, in: []) == nil)
    }

    @Test("Timestamps in the notes become seek links; real links are left alone")
    func linksTimestamps() throws {
        let text = NSMutableAttributedString(string: "Start at (00:26:23), or see 12:05 on the site.")
        let site = (text.string as NSString).range(of: "12:05")
        let webURL = try #require(URL(string: "https://example.com"))
        text.addAttribute(.link, value: webURL, range: site)

        let linked = EpisodeChapters.linkingTimestamps(in: text)
        let stamp = (linked.string as NSString).range(of: "00:26:23")
        let url = try #require(linked.attribute(.link, at: stamp.location, effectiveRange: nil) as? URL)
        #expect(EpisodeChapters.seekTarget(of: url) == (26 * 60 + 23) * 1000)
        #expect(linked.attribute(.link, at: site.location, effectiveRange: nil) as? URL == webURL)
        #expect(EpisodeChapters.seekTarget(of: webURL) == nil)
    }

    @Test("AI replies: cited moments in reading order, each once")
    func replyTimestamps() {
        let reply = "They discuss it from 2:29:50 to 2:31:29, and again at 12:40 (and 2:29:50)."
        #expect(EpisodeChapters.timestamps(in: reply) == [8_990_000, 9_089_000, 760_000])
        #expect(EpisodeChapters.timestamps(in: "Version 1.2.3, nothing timed.").isEmpty)
    }
}
