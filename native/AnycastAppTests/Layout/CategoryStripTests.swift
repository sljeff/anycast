import UIKit
import Testing
@testable import Anycast

/// The Inbox category strip model + view (09 §3.2; UI kit text chips).
@MainActor
struct CategoryStripTests {

    @Test("Chips dedupe case-insensitively, sort, and always lead with all")
    func chipDerivation() {
        let chips = CategoryStripModel.chips(
            categories: ["technology, business", "", "Technology", " arts ", "business,history"]
        )
        #expect(chips.map(\.label) == ["All", "Arts", "Business", "History", "Technology"])
        #expect(chips.map(\.value) == [nil, "arts", "business", "history", "technology"])
    }

    @Test("Empty or blank categories collapse to the single all chip")
    func emptyCategories() {
        #expect(CategoryStripModel.chips(categories: []).count == 1)
        #expect(CategoryStripModel.chips(categories: ["", " , "]).count == 1)
    }

    @Test("Selecting a missing value resets to all; callbacks carry the value")
    func selection() {
        final class Log { var values: [String?] = [] }
        let strip = CategoryStripView()
        strip.frame = CGRect(x: 0, y: 0, width: 440, height: CategoryStripView.chipHeight)
        strip.configure(categories: ["tech", "arts"], selected: nil)
        let log = Log()
        strip.onSelect = { log.values.append($0) }

        guard let techButton = Self.buttons(in: strip).first(where: {
            $0.accessibilityIdentifier == "category-tech"
        }) else {
            Issue.record("category-tech button not found"); return
        }
        techButton.sendActions(for: .touchUpInside)
        #expect(strip.currentSelection == "tech")
        #expect(log.values.count == 1 && log.values[0] == "tech")

        // Silent select with an absent value falls back to all, no callback.
        strip.select("missing", animated: false)
        #expect(strip.currentSelection == nil)
        #expect(log.values.count == 1)
    }

    /// UI kit text chips: selection reads through brightness alone — full
    /// ink for the selected label, sandAlpha8 for the rest, no fill.
    @Test("Selected chip is full ink; the others sandAlpha8; no chip fill")
    func selectedChipColors() {
        let dark = UITraitCollection(userInterfaceStyle: .dark)
        let strip = CategoryStripView()
        strip.frame = CGRect(x: 0, y: 0, width: 440, height: CategoryStripView.chipHeight)
        strip.configure(categories: ["tech", "arts"], selected: "tech")

        let buttons = Self.buttons(in: strip)
        #expect(buttons.count == 3, "all + tech + arts")
        guard let tech = buttons.first(where: { $0.accessibilityIdentifier == "category-tech" }),
              let all = buttons.first(where: { $0.accessibilityIdentifier == "category-all" })
        else {
            Issue.record("strip buttons not found"); return
        }
        #expect(
            tech.configuration?.baseForegroundColor?.resolvedColor(with: dark)
                == Theme.onSurface.resolvedColor(with: dark),
            "selected label must be full ink"
        )
        #expect(
            all.configuration?.baseForegroundColor?.resolvedColor(with: dark)
                == AnycastColor.sandAlpha8.resolvedColor(with: dark),
            "unselected label must be sandAlpha8"
        )
        #expect(tech.accessibilityTraits.contains(.selected))
        #expect(!all.accessibilityTraits.contains(.selected))
        #expect(tech.backgroundColor == nil || tech.backgroundColor == .clear)
    }

    private static func buttons(in view: UIView) -> [UIButton] {
        view.subviews.flatMap { subview -> [UIButton] in
            (subview as? UIButton).map { [$0] } ?? buttons(in: subview)
        }
    }
}
