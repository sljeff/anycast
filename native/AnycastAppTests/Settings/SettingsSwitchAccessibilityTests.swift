import UIKit
import Testing
@testable import Anycast

/// The switch row folds its real UISwitch into the cell-level
/// accessibility element, so activation must drive the switch:
/// VoiceOver and Switch Control double-taps route through
/// `accessibilityActivate`, and a tap anywhere on the row (`didSelectItemAt`)
/// calls the same `toggle()`.
@MainActor
struct SettingsSwitchAccessibilityTests {

    @Test("accessibilityActivate toggles the underlying switch")
    func activateTogglesSwitch() {
        let cell = SettingsSwitchListCell(frame: .zero)
        cell.setOn(true, animated: false)
        var reported: Bool?
        cell.onSwitchChanged = { reported = $0 }

        #expect(cell.accessibilityActivate() == true)
        #expect(cell.isOn == false, "activation must flip the switch")
        #expect(reported == false, "activation must report the change like a real toggle")

        #expect(cell.accessibilityActivate() == true)
        #expect(cell.isOn == true, "a second activation flips back")
    }

    @Test("toggle() — the row-tap path — flips with the same report as a real toggle")
    func rowTapToggles() {
        let cell = SettingsSwitchListCell(frame: .zero)
        cell.setOn(false, animated: false)
        var reports: [Bool] = []
        cell.onSwitchChanged = { reports.append($0) }

        cell.toggle()
        cell.toggle()

        #expect(reports == [true, false])
        #expect(cell.isOn == false)
    }
}
