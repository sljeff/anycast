import UIKit
import Testing
@testable import Anycast

/// UIKit-level onboarding pieces: the interest flow layout's wrapping.
@MainActor
struct OnboardingComponentsTests {

    // MARK: - Flow layout wrapping

    @Test("A chip wider than the row wraps and grows the row's height")
    func flowLayoutWrapsOversizedChip() {
        let longTitle = String(repeating: "Design ", count: 30)
        let chip = OnboardingChipButton(title: longTitle)
        let layout = OnboardingFlowLayoutView(items: [chip])
        layout.frame = CGRect(x: 0, y: 0, width: 200, height: 100)
        layout.layoutIfNeeded()

        // A single-line chip is the 44 pt minimum; a wrapped one must be
        // taller than that, and no wider than the row.
        #expect(layout.intrinsicContentSize.height > 44)
        #expect(chip.bounds.height > 44)
        #expect(chip.bounds.width <= 200)
    }

    @Test("Chips that fit stay on single-line height")
    func flowLayoutSingleLine() {
        let layout = OnboardingFlowLayoutView(items: [
            OnboardingChipButton(title: "Tech"),
            OnboardingChipButton(title: "News"),
        ])
        layout.frame = CGRect(x: 0, y: 0, width: 320, height: 100)
        layout.layoutIfNeeded()

        #expect(layout.intrinsicContentSize.height > 0)
        #expect(layout.intrinsicContentSize.height < 60)
    }
}
