import Foundation
import Testing
import AnycastKit
@testable import Anycast

/// Stepper step math (restrained 2.0 Settings direction, 2026-10-21): the
/// choice lists behind the in-row steppers, exact/nearest positioning for
/// stored values, clamped neighbouring steps, and the range-end flags that
/// disable a stepper half.
@MainActor
struct SettingsPickerMappingTests {

    private let stepperRows: [SettingsPageModel.Row] = [
        .autoRefreshInterval, .maxFeedEpisodes, .maxHistoryEpisodes, .cacheLimit,
    ]

    // MARK: - Choice lists

    @Test("Choice lists per stepper row; non-stepper rows have none")
    func choiceLists() {
        #expect(SettingsPageModel.stepperChoices(for: .autoRefreshInterval) == [60, 180, 300, 600, 1800])
        #expect(SettingsPageModel.stepperChoices(for: .maxFeedEpisodes) == [50, 100, 200, 300])
        #expect(SettingsPageModel.stepperChoices(for: .maxHistoryEpisodes) == [50, 100, 200, 300])
        #expect(SettingsPageModel.stepperChoices(for: .cacheLimit) == [5, 10, 20, 50, 100])
        #expect(SettingsPageModel.cacheLimitChoices == [5, 10, 20, 50, 100])
        for row in [SettingsPageModel.Row.account, .country, .enableTranslation, .targetLanguage,
                    .importExport, .history, .contactEmail, .privacyPolicy, .termsOfUse] {
            #expect(SettingsPageModel.stepperChoices(for: row) == nil)
            #expect(SettingsPageModel.stepperAccessibilityLabels(for: row) == nil)
        }
    }

    @Test("Each stepper row reads its own stored value and has accessibility labels")
    func stepperValueSource() {
        var settings = AppSettings.defaults(localeIdentifier: "en_US")
        settings.autoRefreshInterval = 600
        settings.maxFeedEpisodes = 200
        settings.maxHistoryEpisodes = 300
        settings.maxCacheCount = 50
        #expect(SettingsPageModel.stepperValue(for: .autoRefreshInterval, settings: settings) == 600)
        #expect(SettingsPageModel.stepperValue(for: .maxFeedEpisodes, settings: settings) == 200)
        #expect(SettingsPageModel.stepperValue(for: .maxHistoryEpisodes, settings: settings) == 300)
        #expect(SettingsPageModel.stepperValue(for: .cacheLimit, settings: settings) == 50)
        #expect(SettingsPageModel.stepperValue(for: .account, settings: settings) == nil)

        #expect(SettingsPageModel.stepperAccessibilityLabels(for: .autoRefreshInterval)?.decrease
            == "Shorter auto refresh interval")
        #expect(SettingsPageModel.stepperAccessibilityLabels(for: .autoRefreshInterval)?.increase
            == "Longer auto refresh interval")
        #expect(SettingsPageModel.stepperAccessibilityLabels(for: .maxFeedEpisodes)?.decrease
            == "Lower inbox limit")
        #expect(SettingsPageModel.stepperAccessibilityLabels(for: .maxHistoryEpisodes)?.increase
            == "Raise history limit")
        #expect(SettingsPageModel.stepperAccessibilityLabels(for: .cacheLimit)?.decrease
            == "Lower cache limit")
    }

    // MARK: - Position and stepping

    @Test("Exact match positions on its index; a stray value on the nearest choice")
    func choiceIndex() {
        let episodes = SettingsCodec.maxEpisodesChoices
        for (index, value) in episodes.enumerated() {
            #expect(SettingsPageModel.choiceIndex(of: value, in: episodes) == index)
        }
        #expect(SettingsPageModel.choiceIndex(of: 120, in: episodes) == 1)
        #expect(SettingsPageModel.choiceIndex(of: 190, in: episodes) == 2)
        #expect(SettingsPageModel.choiceIndex(of: 150, in: episodes) == 1, "tie goes to the lower choice")
        #expect(SettingsPageModel.choiceIndex(of: 0, in: episodes) == 0)
        #expect(SettingsPageModel.choiceIndex(of: 9_999, in: episodes) == 3)

        let seconds = SettingsCodec.autoRefreshChoicesSeconds
        #expect(SettingsPageModel.choiceIndex(of: 90, in: seconds) == 0)
        #expect(SettingsPageModel.choiceIndex(of: 700, in: seconds) == 3)
    }

    @Test("Steps move to the neighbouring choice and clamp at the ends")
    func stepping() {
        let choices = SettingsPageModel.cacheLimitChoices
        #expect(SettingsPageModel.steppedValue(from: 20, .increase, in: choices) == 50)
        #expect(SettingsPageModel.steppedValue(from: 20, .decrease, in: choices) == 10)
        #expect(SettingsPageModel.steppedValue(from: 5, .decrease, in: choices) == 5)
        #expect(SettingsPageModel.steppedValue(from: 100, .increase, in: choices) == 100)
        // A stray value steps from its nearest choice (12 → 10).
        #expect(SettingsPageModel.steppedValue(from: 12, .increase, in: choices) == 20)
        #expect(SettingsPageModel.steppedValue(from: 12, .decrease, in: choices) == 5)
    }

    @Test("Min/max flags disable the matching half for every row's list")
    func rangeFlags() {
        for row in stepperRows {
            guard let choices = SettingsPageModel.stepperChoices(for: row) else {
                Issue.record("\(row) has no choices")
                continue
            }
            let first = choices[0]
            let last = choices[choices.count - 1]
            #expect(!SettingsPageModel.canDecrease(from: first, in: choices), "\(row) at minimum")
            #expect(SettingsPageModel.canIncrease(from: first, in: choices))
            #expect(SettingsPageModel.canDecrease(from: last, in: choices))
            #expect(!SettingsPageModel.canIncrease(from: last, in: choices), "\(row) at maximum")
            for value in choices.dropFirst().dropLast() {
                #expect(SettingsPageModel.canDecrease(from: value, in: choices))
                #expect(SettingsPageModel.canIncrease(from: value, in: choices))
            }
            // Out-of-range stored values land on the ends.
            #expect(!SettingsPageModel.canDecrease(from: 0, in: choices))
            #expect(!SettingsPageModel.canIncrease(from: 1_000_000, in: choices))
        }
    }

    @Test("Defaults from the canonical fresh row sit on a choice")
    func defaultPositions() {
        let defaults = AppSettings.defaults(localeIdentifier: "en_US")
        for row in stepperRows {
            guard let choices = SettingsPageModel.stepperChoices(for: row),
                  let value = SettingsPageModel.stepperValue(for: row, settings: defaults) else {
                Issue.record("\(row) missing choices or value")
                continue
            }
            #expect(choices.contains(value), "\(row) default \(value) is a choice")
        }
    }

    // MARK: - Display

    @Test("Row display strings")
    func display() {
        #expect(SettingsPageModel.autoRefreshDisplay(seconds: 300) == "5 min")
        #expect(SettingsPageModel.autoRefreshDisplay(seconds: 60) == "1 min")
        #expect(SettingsPageModel.autoRefreshDisplay(seconds: 1800) == "30 min")
        #expect(SettingsPageModel.episodesDisplay(count: 100) == "100 episodes")
    }
}
