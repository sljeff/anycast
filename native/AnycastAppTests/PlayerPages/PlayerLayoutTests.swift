import UIKit
import Testing
@testable import Anycast

/// M3 review regression guards: the custom player controls live inside
/// vertical `.fill` stacks, so a control without an intrinsic height absorbs
/// all spare space (PlayerProgressBarView against a plain-UIView sibling).
@MainActor
struct PlayerLayoutTests {

    @Test("Progress bar stays at its 60 pt design height against flexible siblings")
    func progressBarHeight() {
        let bar = PlayerProgressBarView()
        let stack = UIStackView(arrangedSubviews: [UIView(), bar, UIView()])
        stack.axis = .vertical
        stack.frame = CGRect(x: 0, y: 0, width: 320, height: 400)
        stack.layoutIfNeeded()
        // 40 pt bar + the 20 pt label band below it — the .fill stack must
        // not stretch the control to absorb the siblings' slack.
        #expect(bar.bounds.height == 60)
    }

    @Test("Progress bar time labels sit in the band below the bar")
    func progressBarLabels() {
        let bar = PlayerProgressBarView()
        bar.frame = CGRect(x: 0, y: 0, width: 320, height: 60)
        bar.layoutIfNeeded()
        let labels = bar.subviews.compactMap { $0 as? UILabel }
        #expect(labels.count == 2)
        for label in labels {
            #expect(label.frame.minY >= 24, "label must sit below the bar")
            #expect(label.frame.maxY <= 60, "label must stay inside the control")
        }
    }
}
