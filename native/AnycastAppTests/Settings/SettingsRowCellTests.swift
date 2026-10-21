import UIKit
import Testing
@testable import Anycast

/// Row and sheet metrics of the restrained 2.0 Settings direction
/// (2026-10-21): the 56 pt minimum row, stepper range-end enabling, and the
/// option sheet's content-fitting detent.
@MainActor
struct SettingsRowCellTests {

    private func fittingHeight(_ cell: UICollectionViewListCell, width: CGFloat = 358) -> CGFloat {
        cell.frame = CGRect(x: 0, y: 0, width: width, height: 100)
        cell.layoutIfNeeded()
        return cell.contentView.systemLayoutSizeFitting(
            CGSize(width: width, height: UIView.layoutFittingCompressedSize.height),
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel
        ).height
    }

    @Test("Plain rows are at least 56 tall; a subtitle grows the row")
    func minimumHeight() {
        let cell = SettingsRowCell(frame: .zero)
        cell.configure(title: "Account", showsChevron: true)
        #expect(fittingHeight(cell) >= 56)

        let withSubtitle = SettingsSwitchListCell(frame: .zero)
        withSubtitle.configure(title: "Subtitle Translation", subtitle: "Translate generated text")
        #expect(fittingHeight(withSubtitle) >= 56)
    }

    @Test("Stepper rows stay 56 tall and mirror the range flags onto the halves")
    func stepperRow() {
        let cell = SettingsStepperRowCell(frame: .zero)
        cell.configure(
            title: "Cache Limit", value: "5 episodes",
            labels: (decrease: "Lower cache limit", increase: "Raise cache limit"),
            canDecrease: false, canIncrease: true
        )
        #expect(fittingHeight(cell) == 56)
        let elements = cell.accessibilityElements?.compactMap { $0 as? UIButton } ?? []
        #expect(elements.map(\.accessibilityLabel) == ["Lower cache limit", "Raise cache limit"])
        #expect(elements.map(\.isEnabled) == [false, true])
        #expect(cell.isAccessibilityElement == false)

        cell.configure(
            title: "Cache Limit", value: "100 episodes",
            labels: (decrease: "Lower cache limit", increase: "Raise cache limit"),
            canDecrease: true, canIncrease: false
        )
        let reconfigured = cell.accessibilityElements?.compactMap { $0 as? UIButton } ?? []
        #expect(reconfigured.map(\.isEnabled) == [true, false])
    }

    @Test("Stepper halves report their direction")
    func stepperTaps() {
        let cell = SettingsStepperRowCell(frame: .zero)
        cell.configure(
            title: "Inbox Limit", value: "100 episodes",
            labels: (decrease: "Lower inbox limit", increase: "Raise inbox limit"),
            canDecrease: true, canIncrease: true
        )
        var steps: [SettingsPageModel.StepDirection] = []
        cell.onStep = { steps.append($0) }
        let buttons = cell.accessibilityElements?.compactMap { $0 as? UIButton } ?? []
        buttons.first?.sendActions(for: .touchUpInside)
        buttons.last?.sendActions(for: .touchUpInside)
        #expect(steps == [.decrease, .increase])
    }

    @Test("Option sheet detent: at least 350, at most 72% of the maximum, otherwise content")
    func optionSheetDetent() {
        // Few rows → the 350 floor.
        #expect(SettingsOptionSheetViewController.detentHeight(rowCount: 3, maximum: 800) == 350)
        // Many rows → the 72% cap.
        #expect(SettingsOptionSheetViewController.detentHeight(rowCount: 49, maximum: 800)
            == 800 * SettingsOptionSheetViewController.maximumDetentFraction)
        // In between → title block + rows × 52.
        let height = SettingsOptionSheetViewController.detentHeight(rowCount: 8, maximum: 2_000)
        #expect(height > 350 && height < 2_000 * 0.72)
        let titleBlock = height - 8 * SettingsOptionSheetViewController.rowHeight
        #expect(titleBlock >= 28 + 12 + 28)
    }
}
