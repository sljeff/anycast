import UIKit
import Testing
@testable import Anycast

/// M3 review regression guards: the custom player controls live inside
/// vertical `.fill` stacks, so a control without an intrinsic height either
/// collapses to zero (PlayerValueSlider in the settings block) or absorbs
/// all spare space (PlayerProgressBarView against a plain-UIView sibling).
@MainActor
struct PlayerLayoutTests {

    @Test("Value slider keeps its 48 pt capsule height in a vertical stack")
    func sliderHeight() {
        let slider = PlayerValueSlider(
            spec: .init(
                values: PlayerSliderMath.stops(min: 0.5, max: 2, divisions: 6),
                tickStyle: .allWhite
            ),
            initialIndex: 0,
            thumbText: PlayerSliderMath.speedThumbText
        )
        let label = UILabel()
        label.text = "SPEED"
        let block = UIStackView(arrangedSubviews: [label, slider])
        block.axis = .vertical
        block.spacing = 8
        block.frame = CGRect(x: 0, y: 0, width: 320, height: 200)
        block.layoutIfNeeded()
        #expect(slider.bounds.height == 48)
    }

    @Test("Progress bar stays at its 60 pt design height against flexible siblings")
    func progressBarHeight() {
        let bar = PlayerProgressBarView()
        let stack = UIStackView(arrangedSubviews: [UIView(), bar, UIView()])
        stack.axis = .vertical
        stack.frame = CGRect(x: 0, y: 0, width: 320, height: 400)
        stack.layoutIfNeeded()
        // 40 pt bar + the 20 pt label band above it — the .fill stack must
        // not stretch the control to absorb the siblings' slack.
        #expect(bar.bounds.height == 60)
    }

    @Test("Progress bar time labels sit in the band above the bar")
    func progressBarLabels() {
        let bar = PlayerProgressBarView()
        bar.frame = CGRect(x: 0, y: 0, width: 320, height: 60)
        bar.layoutIfNeeded()
        let labels = bar.subviews.compactMap { $0 as? UILabel }
        #expect(labels.count == 2)
        for label in labels {
            #expect(label.frame.maxY <= 24, "label must sit above the 40 pt bar")
        }
    }
}
