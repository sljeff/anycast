import Foundation
import Testing
import AnycastKit
@testable import Anycast

/// Export composition as the subtitles page performs it: stored row JSON
/// → LRC → ExportText.build → .txt. Spot-checked against the G4 golden
/// fixture (test/golden/G4_export_text.json, the byte-pinned
/// buildExportText output of pages/player.dart).
struct SubtitlesExportTextTests {

    @Test("Page export chain reproduces the G4 golden outputs")
    func exportChainMatchesGolden() throws {
        let data = try Data(contentsOf: TestRepoAssets.golden("G4_export_text.json"))
        let object = try #require(
            try JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        let cases = try #require(object["cases"] as? [String: String])

        // The stored-row form of the same segments the golden used.
        let mainRowJSON = SubtitleSegment.encode([
            SubtitleSegment(start: 0.0, end: 3.9, text: "line one"),
            SubtitleSegment(start: 4.0, end: 8.5, text: "line two"),
        ])
        let translationRowJSON = SubtitleSegment.encode([
            SubtitleSegment(start: 0.0, end: 3.9, text: "第一行"),
        ])

        let mainLyric = LRC.render(rawJSON: mainRowJSON)
        let bilingualLyric = LRC.render(rawJSON: translationRowJSON)

        func build(_ translation: String?) -> String {
            ExportText.build(
                title: "Episode 42",
                channelTitle: "Some Channel",
                mainLyric: mainLyric,
                translationLyric: translation
            )
        }

        #expect(build(bilingualLyric) == cases["full"])
        #expect(build(nil) == cases["no_translation"])
        // An all-blank stored payload renders as "" — the page passes the
        // raw string through and the builder drops the translation block.
        #expect(build(LRC.render(rawJSON: "")) == cases["empty_translation_string"])
        #expect(
            ExportText.build(
                title: nil, channelTitle: nil,
                mainLyric: mainLyric, translationLyric: nil
            ) == cases["null_title_defaults"]
        )
        #expect(
            ExportText.build(
                title: "Solo", channelTitle: "",
                mainLyric: mainLyric, translationLyric: nil
            ) == cases["empty_channel_title_only"]
        )
    }

    @Test("K21/K29: export is a .txt whose file name survives slashes")
    func exportFileName() {
        let subject = ExportText.deriveSubject(title: "EP/1: crash test", channelTitle: "Chan")
        #expect(subject == "EP/1: crash test - Chan")
        // AnycastKit's K29 sanitizer replaces each illegal character with a
        // space (visual shape preserved): '/' and ':' both become spaces.
        #expect(
            ExportText.sanitizedFileName(fromSubject: subject) == "EP 1  crash test - Chan"
        )
        // The share payload is the .txt URL (K21: .txt, never .lrc).
        let fileName = ExportText.sanitizedFileName(fromSubject: subject)
        #expect(fileName.hasSuffix(".txt") == false) // suffix added by the page
        let composed = "\(fileName).txt"
        #expect(composed == "EP 1  crash test - Chan.txt")
    }
}
