import UIKit
import Testing
@testable import Anycast

/// The v2 Inbox category strip model + view (09 §3.2).
@MainActor
struct CategoryStripTests {

    @Test("Chips dedupe case-insensitively, sort, and always lead with all")
    func chipDerivation() {
        let chips = CategoryStripModel.chips(
            categories: ["technology, business", "", "Technology", " arts ", "business,history"]
        )
        #expect(chips.map(\.label) == ["all", "Arts", "Business", "History", "Technology"])
        #expect(chips.map(\.value) == [nil, "arts", "business", "history", "technology"])
        #expect(chips[0].icon != nil, "the all chip carries an icon")
        #expect(chips.dropFirst().allSatisfy { $0.icon == nil })
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

        guard let techButton = strip.subviews.first?.subviews.first(where: {
            ($0 as? UIButton)?.accessibilityIdentifier == "category-tech"
        }) as? UIButton else {
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

    /// The 09 §3.2 selected variant (V0.5 correction): goldAlpha7 fill +
    /// sandAlpha4 1 pt stroke + sand1 content; unselected sandAlpha2 fill
    /// with onSurfaceVariant content. Color values are asserted with an
    /// explicit dark resolution (09 §9a: named colors resolve against the
    /// current trait outside the installed dark base).
    @Test("Selected chip paints the goldAlpha7/sandAlpha4/sand1 variant")
    func selectedChipColors() {
        let dark = UITraitCollection(userInterfaceStyle: .dark)
        let strip = CategoryStripView()
        strip.frame = CGRect(x: 0, y: 0, width: 440, height: CategoryStripView.chipHeight)
        strip.configure(categories: ["tech", "arts"], selected: "tech")

        let buttons = strip.subviews.first?.subviews.compactMap { $0 as? UIButton } ?? []
        #expect(buttons.count == 3, "all + tech + arts")
        guard let tech = buttons.first(where: { $0.accessibilityIdentifier == "category-tech" }),
              let all = buttons.first(where: { $0.accessibilityIdentifier == "category-all" })
        else {
            Issue.record("strip buttons not found"); return
        }

        #expect(
            tech.backgroundColor?.resolvedColor(with: dark)
                == AnycastColor.goldAlpha7.resolvedColor(with: dark),
            "selected fill must be goldAlpha7"
        )
        // The stroke runs through layer.borderColor — compare the raw
        // CGColors (a UIColor(cgColor:) re-wrap bakes the CURRENT trait
        // and loses the dynamic pair, §9a).
        #expect(
            tech.layer.borderColor == AnycastColor.sandAlpha4.cgColor,
            "selected stroke must be sandAlpha4"
        )
        #expect(tech.layer.borderWidth == 1)
        #expect(
            tech.titleColor(for: .normal)?.resolvedColor(with: dark)
                == AnycastColor.sand1.resolvedColor(with: dark),
            "selected content must be sand1"
        )

        #expect(
            all.backgroundColor?.resolvedColor(with: dark)
                == AnycastColor.sandAlpha2.resolvedColor(with: dark),
            "unselected fill must be sandAlpha2"
        )
        #expect(all.layer.borderWidth == 0 || all.layer.borderColor == nil)
        #expect(
            all.titleColor(for: .normal)?.resolvedColor(with: dark)
                == Theme.onSurfaceVariant.resolvedColor(with: dark),
            "unselected content must be onSurfaceVariant"
        )
    }
}
