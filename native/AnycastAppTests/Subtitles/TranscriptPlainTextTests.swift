import Testing
@testable import Anycast

/// "Copy transcript" text: spacer rows dropped, translations beneath their
/// line, bilingual pairs separated by a blank line.
struct TranscriptPlainTextTests {

    @Test("Mono transcript is one line per row, blank spacer rows dropped")
    func mono() {
        let lines = [
            LyricLine(startMilliseconds: 0, text: "One", translation: nil),
            LyricLine(startMilliseconds: 1000, text: "Two", translation: nil),
            LyricLine(startMilliseconds: 2000, text: "", translation: nil),
        ]
        #expect(LyricDocument.plainText(lines: lines) == "One\nTwo")
    }

    @Test("Bilingual transcript puts the translation under its line")
    func bilingual() {
        let lines = [
            LyricLine(startMilliseconds: 0, text: "One", translation: "Un"),
            LyricLine(startMilliseconds: 1000, text: "Two", translation: nil),
        ]
        #expect(LyricDocument.plainText(lines: lines) == "One\nUn\n\nTwo")
    }

    @Test("Timestamp formatting")
    func timestamps() {
        #expect(LyricsTimestamp.string(milliseconds: 65_000) == "01:05")
        #expect(LyricsTimestamp.string(milliseconds: 3_725_000) == "1:02:05")
    }
}
