import Foundation
import Testing
import AnycastKit
@testable import Anycast

/// T7 picker semantics (G9 / 05 §6.3 Settings P1): the three CupertinoPicker
/// value↔index mappings, their preselection behavior for the current value,
/// and the row display strings.
@MainActor
struct SettingsPickerMappingTests {

    // MARK: - Auto refresh interval (settings.dart:307-341)

    @Test("Choices are 1/3/5/10/30 minutes in seconds")
    func autoRefreshChoices() {
        #expect(SettingsCodec.autoRefreshChoicesSeconds == [60, 180, 300, 600, 1800])
        #expect((0..<5).map(SettingsPageModel.autoRefreshLabel)
            == ["1 min", "3 min", "5 min", "10 min", "30 min"])
    }

    @Test("Value ↔ index: minutes.indexOf(interval ~/ 60), miss falls to row 0")
    func autoRefreshIndex() {
        #expect(SettingsPageModel.autoRefreshPickerIndex(seconds: 60) == 0)
        #expect(SettingsPageModel.autoRefreshPickerIndex(seconds: 180) == 1)
        #expect(SettingsPageModel.autoRefreshPickerIndex(seconds: 300) == 2)
        #expect(SettingsPageModel.autoRefreshPickerIndex(seconds: 600) == 3)
        #expect(SettingsPageModel.autoRefreshPickerIndex(seconds: 1800) == 4)
        // 90s → minutes 1 → a valid entry (indexOf finds 1 min); 45s →
        // minutes 0 → indexOf miss → clamps to row 0.
        #expect(SettingsPageModel.autoRefreshPickerIndex(seconds: 90) == 0)
        #expect(SettingsPageModel.autoRefreshPickerIndex(seconds: 45) == 0)
        // Round trip: selecting a row persists minutes × 60.
        for index in 0..<5 {
            #expect(SettingsPageModel.autoRefreshSeconds(at: index)
                == SettingsCodec.autoRefreshChoicesSeconds[index])
        }
    }

    @Test("Row display shows interval ~/ 60 (G9 300 caliber → '5 min')")
    func autoRefreshDisplay() {
        #expect(SettingsPageModel.autoRefreshDisplay(seconds: 300) == "5 min")
        #expect(SettingsPageModel.autoRefreshDisplay(seconds: 60) == "1 min")
        #expect(SettingsPageModel.autoRefreshDisplay(seconds: 1800) == "30 min")
    }

    // MARK: - Episode caps (settings.dart:345-443)

    @Test("Choices are 50/100/200/300 with the value ~/ 100 preselection")
    func maxEpisodesIndex() {
        #expect(SettingsCodec.maxEpisodesChoices == [50, 100, 200, 300])
        #expect((0..<4).map(SettingsPageModel.maxEpisodesLabel) == ["50", "100", "200", "300"])

        // The shipped preselection divides by 100 (not indexOf): 150 lands
        // on the "100" row exactly like the Dart FixedExtentScrollController.
        #expect(SettingsPageModel.maxEpisodesPickerIndex(count: 50) == 0)
        #expect(SettingsPageModel.maxEpisodesPickerIndex(count: 100) == 1)
        #expect(SettingsPageModel.maxEpisodesPickerIndex(count: 150) == 1)
        #expect(SettingsPageModel.maxEpisodesPickerIndex(count: 200) == 2)
        #expect(SettingsPageModel.maxEpisodesPickerIndex(count: 300) == 3)
        // Out-of-list values clamp onto a valid row.
        #expect(SettingsPageModel.maxEpisodesPickerIndex(count: 10) == 0)
        #expect(SettingsPageModel.maxEpisodesPickerIndex(count: 9_999) == 3)

        for index in 0..<4 {
            #expect(SettingsPageModel.maxEpisodesCount(at: index)
                == SettingsCodec.maxEpisodesChoices[index])
        }
        #expect(SettingsPageModel.maxEpisodesDisplay(count: 100) == "100")
        #expect(SettingsPageModel.maxEpisodesDisplay(count: 300) == "300")
    }

    @Test("Defaults from the canonical fresh row preselect their rows")
    func defaultPreselection() {
        let defaults = AppSettings.defaults(localeIdentifier: "en_US")
        // autoRefreshInterval default 300 (docs/migration/01 §2 caliber).
        #expect(SettingsPageModel.autoRefreshPickerIndex(seconds: defaults.autoRefreshInterval) == 2)
        #expect(SettingsPageModel.maxEpisodesPickerIndex(count: defaults.maxFeedEpisodes) == 1)
        #expect(SettingsPageModel.maxEpisodesPickerIndex(count: defaults.maxHistoryEpisodes) == 1)
    }
}
