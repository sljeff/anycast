import Foundation
import Testing
@testable import Anycast

/// ImportInstructions content parity (lib/widgets/import_export.dart:251-333,
/// 03 §2.15): the five ExpansionTile sections with byte-exact titles and
/// step text — including the Chinese 小宇宙 copy.
@MainActor
struct FeedsImportInstructionsTests {

    @Test("Exactly five sections with the Dart titles in order")
    func sectionTitles() {
        #expect(ImportInstructionsContent.sections.count == 5)
        #expect(ImportInstructionsContent.sections.map(\.title) == [
            "Castro",
            "Overcast",
            "Pocket Casts",
            "小宇宙",
            "Other Apps using OPML",
        ])
    }

    @Test("Castro steps verbatim")
    func castro() {
        #expect(ImportInstructionsContent.sections[0].text == "1. Open Castro.\n"
            + "2. Tap the Settings icon on the top left.\n"
            + "3. Scroll down to \"User Data\" and tap it.\n"
            + "4. Click \"Export Subscriptions\"\n"
            + "5. Share to \"Anycast\"")
    }

    @Test("Overcast steps verbatim")
    func overcast() {
        #expect(ImportInstructionsContent.sections[1].text == "1. Open Overcast.\n"
            + "2. Tap the Settings icon on the top left.\n"
            + "3. Scroll down to \"Export OPML\" and tap it.\n"
            + "4. Share to \"Anycast\"")
    }

    @Test("Pocket Casts steps verbatim")
    func pocketCasts() {
        #expect(ImportInstructionsContent.sections[2].text == "1. Open Pocket Casts -> Profile\n"
            + "2. Tap Settings icon on the top right\n"
            + "3. Scroll down to \"Export Podcasts\"\n"
            + "4. Click \"Export Podcasts\"\n"
            + "5. Share to \"Anycast\"")
    }

    @Test("小宇宙 steps verbatim (the Chinese-copy exception, 03 §8)")
    func xiaoyuzhou() {
        #expect(ImportInstructionsContent.sections[3].text == "1. 打开小宇宙 -> 订阅\n"
            + "2. 点击右上角 \"我的订阅\"\n"
            + "3. 点击右上角的分享按钮\n"
            + "4. 选中所有想要导入的频道\n"
            + "5. 点击 \"导出 OPML\"\n"
            + "6. 分享到 \"Anycast\"")
    }

    @Test("Other Apps steps verbatim")
    func otherApps() {
        #expect(ImportInstructionsContent.sections[4].text == "1. Find your OPML file\n"
            + "2. Share to \"Anycast\"")
    }

    @Test("Step line counts (5/4/5/6/2)")
    func lineCounts() {
        let counts = ImportInstructionsContent.sections.map { $0.lines.count }
        #expect(counts == [5, 4, 5, 6, 2])
    }

    @Test("Sheet header title")
    func headerTitle() {
        #expect(ImportInstructionsContent.headerTitle == "Import OPML from")
    }

    @Test("Every step line is numbered and non-empty")
    func numberedLines() {
        for section in ImportInstructionsContent.sections {
            for (index, line) in section.lines.enumerated() {
                #expect(line.hasPrefix("\(index + 1). "))
                #expect(!line.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }
}
