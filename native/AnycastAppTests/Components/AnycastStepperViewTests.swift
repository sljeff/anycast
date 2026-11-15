import UIKit
import Testing
@testable import Anycast

/// AnycastStepperView pressed feedback: a half-capsule pill that appears on
/// touch-down and disappears on release/cancel, never for a disabled half.
@MainActor
struct AnycastStepperViewTests {

    private func makeStepper() -> AnycastStepperView {
        let stepper = AnycastStepperView(
            minusLabel: "minus", plusLabel: "plus", onMinus: {}, onPlus: {}
        )
        stepper.frame = CGRect(x: 0, y: 0, width: 112, height: 36)
        stepper.layoutIfNeeded()
        return stepper
    }

    @Test("Touch-down highlights only the pressed half; touch-up clears it")
    func highlightFollowsTouch() {
        let stepper = makeStepper()
        #expect(stepper.minusHighlight.alpha == 0 && stepper.plusHighlight.alpha == 0)

        stepper.plusButton.sendActions(for: .touchDown)
        #expect(stepper.plusHighlight.alpha == 1)
        #expect(stepper.minusHighlight.alpha == 0)
        stepper.plusButton.sendActions(for: .touchUpInside)
        #expect(stepper.plusHighlight.alpha == 0)

        stepper.minusButton.sendActions(for: .touchDown)
        #expect(stepper.minusHighlight.alpha == 1)
        #expect(stepper.plusHighlight.alpha == 0)
        stepper.minusButton.sendActions(for: .touchCancel)
        #expect(stepper.minusHighlight.alpha == 0)

        stepper.minusButton.sendActions(for: .touchDown)
        stepper.minusButton.sendActions(for: .touchUpOutside)
        #expect(stepper.minusHighlight.alpha == 0)
    }

    @Test("A disabled half shows no highlight")
    func disabledHalfStaysClear() {
        let stepper = makeStepper()
        stepper.setEnabled(minus: false, plus: true)
        stepper.minusButton.sendActions(for: .touchDown)
        #expect(stepper.minusHighlight.alpha == 0)
        stepper.plusButton.sendActions(for: .touchDown)
        #expect(stepper.plusHighlight.alpha == 1)
    }

    @Test("Each pill is one half of the capsule, filled sandAlpha4, clipped to the contour")
    func pillGeometry() {
        let stepper = makeStepper()
        #expect(stepper.minusHighlight.frame == CGRect(x: 0, y: 0, width: 56, height: 36))
        #expect(stepper.plusHighlight.frame == CGRect(x: 56, y: 0, width: 56, height: 36))
        #expect(stepper.clipsToBounds)
        #expect(abs(stepper.layer.cornerRadius - 18) < 0.01)
        #expect(stepper.minusHighlight.backgroundColor == AnycastColor.sandAlpha4)
    }

    @Test("A tap still reports exactly one step")
    func tapStillSteps() {
        var minus = 0, plus = 0
        let stepper = AnycastStepperView(
            minusLabel: "minus", plusLabel: "plus", onMinus: { minus += 1 }, onPlus: { plus += 1 }
        )
        stepper.minusButton.sendActions(for: .touchDown)
        stepper.minusButton.sendActions(for: .touchUpInside)
        stepper.plusButton.sendActions(for: .touchDown)
        stepper.plusButton.sendActions(for: .touchUpInside)
        #expect(minus == 1 && plus == 1)
    }
}
