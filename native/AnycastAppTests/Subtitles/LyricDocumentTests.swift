import Foundation
import Testing
import AnycastKit
@testable import Anycast

/// LyricDocument: the flutter_lyric 3.0.2 LRC port (parse + active-line
/// binary search), pinned against the Dart grammar that
/// `SubtitleModel.toLrc()` / `TranslationModel.toLrc()` emit.
struct LyricDocumentTests {

    // MARK: - Parse (LrcParser port)

    @Test("toLrc-shaped documents keep the end-timestamp spacer lines")
    func parsesToLrcShape() {
        // What SubtitleModel.toLrc emits for one segment (01 §6.2).
        let main = "[00:00.000]line one\n[00:03.900]\n[00:04.000]line two\n[00:08.500]\n"
        let lines = LyricDocument.parse(mainLRC: main, translationLRC: nil)

        #expect(lines.count == 4)
        #expect(lines[0] == LyricLine(startMilliseconds: 0, text: "line one", translation: nil))
        #expect(lines[1] == LyricLine(startMilliseconds: 3_900, text: "", translation: nil))
        #expect(lines[2] == LyricLine(startMilliseconds: 4_000, text: "line two", translation: nil))
        #expect(lines[3] == LyricLine(startMilliseconds: 8_500, text: "", translation: nil))
    }

    @Test("Translation aligns by exact millisecond key (no tolerance)")
    func translationAlignment() {
        let main = "[00:00.000]hello\n[00:03.900]\n[00:04.000]world\n[00:08.500]\n"

        // Same stamps: every main line carries its translation; the empty
        // end-spacers in the translation LRC are skipped ('' filter), so
        // they never mask a real translation.
        let matching = "[00:00.000]你好\n[00:03.900]\n[00:04.000]世界\n[00:08.500]\n"
        let aligned = LyricDocument.parse(mainLRC: main, translationLRC: matching)
        #expect(aligned[0].translation == "你好")
        #expect(aligned[1].translation == nil)
        #expect(aligned[2].translation == "世界")

        // One millisecond off: NO alignment — the LRC parser has no
        // tolerance (that path exists only for QRC).
        let off = "[00:00.001]你好\n"
        let unaligned = LyricDocument.parse(mainLRC: main, translationLRC: off)
        #expect(unaligned[0].translation == nil)
    }

    @Test("'//' and empty translation texts are dropped, multiple stamps split")
    func translationFiltersAndMultiStamp() {
        let main = "[00:01.000][00:05.000]repeat\n"
        let translation = "[00:01.000]//\n[00:05.000]second\n"
        let lines = LyricDocument.parse(mainLRC: main, translationLRC: translation)

        #expect(lines.count == 2)
        #expect(lines[0] == LyricLine(startMilliseconds: 1_000, text: "repeat", translation: nil))
        #expect(lines[1] == LyricLine(startMilliseconds: 5_000, text: "repeat", translation: "second"))
    }

    @Test("Fraction padding/truncation and minute overflow")
    func stampPrecision() {
        // .5 → 500 ms (padRight), .1234 → 123 ms (truncate), minutes 62.
        let main = "[00:00.5]a\n[00:01.1234]b\n[01:02.000]c\n[62:00.000]d\n"
        let lines = LyricDocument.parse(mainLRC: main, translationLRC: nil)
        let stamps = lines.map(\.startMilliseconds)
        #expect(stamps == [500, 1_123, 62_000, 3_720_000])
    }

    @Test("ID tag lines are skipped; unsorted lines are sorted by start")
    func tagsAndSorting() {
        let main = "[ti:ignored]\n[00:10.000]later\n[00:02.000]earlier\n[ar:also ignored]\n"
        let lines = LyricDocument.parse(mainLRC: main, translationLRC: nil)
        #expect(lines.map(\.text) == ["earlier", "later"])
        #expect(lines.map(\.startMilliseconds) == [2_000, 10_000])
    }

    @Test("Full Dart pipeline: segments → toLrc → loadLyric alignment")
    func segmentsThroughRenderAndParse() {
        // Mirrors the Dart chain: SubtitleModel.toLrc() +
        // TranslationModel.toLrc() → loadLyric(main, translationLyric:).
        let segments = [
            SubtitleSegment(start: 0.0, end: 2.5, text: "first"),
            SubtitleSegment(start: 2.5, end: 6.75, text: "second"),
        ]
        let translationSegments = [
            SubtitleSegment(start: 0.0, end: 2.5, text: "第一"),
            SubtitleSegment(start: 2.5, end: 6.75, text: "第二"),
        ]
        let main = LRC.render(segments: segments)
        let translation = LRC.render(segments: translationSegments)
        let lines = LyricDocument.parse(mainLRC: main, translationLRC: translation)

        #expect(lines.count == 4)
        #expect(lines[0].text == "first")
        #expect(lines[0].translation == "第一")
        // End spacer of segment 1 sits between the two content lines.
        #expect(lines[1].text == "")
        #expect(lines[1].startMilliseconds == 2_500)
        #expect(lines[2].text == "second")
        #expect(lines[2].translation == "第二")
    }

    // MARK: - Active line lookup (getIndexByProgress port)

    @Test("Position → active line across gaps, exacts and the last line")
    func activeLineLookup() {
        let lines = LyricDocument.parse(
            mainLRC: "[00:00.000]a\n[00:10.000]b\n[00:20.000]c\n",
            translationLRC: nil
        )
        // stamps: 0, 10_000, 20_000
        #expect(LyricDocument.activeLineIndex(lines: lines, positionMilliseconds: -100) == 0)
        #expect(LyricDocument.activeLineIndex(lines: lines, positionMilliseconds: 0) == 0)
        #expect(LyricDocument.activeLineIndex(lines: lines, positionMilliseconds: 5_000) == 0)
        #expect(LyricDocument.activeLineIndex(lines: lines, positionMilliseconds: 10_000) == 1)
        #expect(LyricDocument.activeLineIndex(lines: lines, positionMilliseconds: 19_999) == 1)
        // After the last stamp the last line stays active.
        #expect(LyricDocument.activeLineIndex(lines: lines, positionMilliseconds: 120_000) == 2)
        // Empty document is index 0, never a crash.
        #expect(LyricDocument.activeLineIndex(lines: [], positionMilliseconds: 1_000) == 0)
    }

    @Test("Lookup with toLrc spacers: the blank end-line becomes active in gaps")
    func activeLineWithSpacers() {
        // toLrc of one 0–3.9 s segment: [0]text, [3.9]"".
        let lines = LyricDocument.parse(
            mainLRC: "[00:00.000]text\n[00:03.900]\n",
            translationLRC: nil
        )
        #expect(LyricDocument.activeLineIndex(lines: lines, positionMilliseconds: 1_000) == 0)
        // Past the end stamp the blank spacer is the active line (Dart
        // behavior: the model contains it).
        #expect(LyricDocument.activeLineIndex(lines: lines, positionMilliseconds: 4_000) == 1)
    }

    @Test("Duplicate stamps resolve to a valid index")
    func duplicateStamps() {
        let lines = LyricDocument.parse(
            mainLRC: "[00:01.000][00:01.000]twin\n[00:02.000]next\n",
            translationLRC: nil
        )
        let index = LyricDocument.activeLineIndex(lines: lines, positionMilliseconds: 1_000)
        #expect(lines.indices.contains(index))
        #expect(lines[index].startMilliseconds == 1_000)
    }
}
