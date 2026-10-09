import UIKit
import Testing
@testable import Anycast

@MainActor
struct PodcastSectionBarTests {

    @Test("Podcast sections expose Inbox and Subscriptions and retain selection")
    func selectionAndAccessibility() {
        let bar = PodcastSectionBar(frame: CGRect(x: 0, y: 0, width: 343, height: 60))
        bar.layoutIfNeeded()
        var selected: Int?
        bar.onSelect = { selected = $0 }

        let subscriptions = bar.subviews.compactMap { $0 as? UIButton }
            .first { $0.accessibilityIdentifier == "podcast-section-1" }
        #expect(subscriptions?.accessibilityLabel == "Subscriptions")
        subscriptions?.sendActions(for: .touchUpInside)
        #expect(selected == 1)
        #expect(subscriptions?.accessibilityTraits.contains(.selected) == true)
    }

    @Test("Selected section border follows light and dark appearance")
    func selectedBorderAppearance() {
        let bar = PodcastSectionBar(frame: CGRect(x: 0, y: 0, width: 343, height: 60))
        bar.traitOverrides.userInterfaceStyle = .light
        bar.layoutIfNeeded()
        let selectedSurface = bar.subviews.first
        let lightBorder = selectedSurface?.layer.borderColor

        bar.traitOverrides.userInterfaceStyle = .dark
        bar.layoutIfNeeded()
        let darkBorder = selectedSurface?.layer.borderColor

        guard let lightBorder, let darkBorder else {
            Issue.record("selected section border is missing")
            return
        }

        #expect(UIColor(cgColor: lightBorder).isEqual(Theme.outlineVariant
            .resolvedColor(with: UITraitCollection(userInterfaceStyle: .light))))
        #expect(UIColor(cgColor: darkBorder).isEqual(Theme.outlineVariant
            .resolvedColor(with: UITraitCollection(userInterfaceStyle: .dark))))
    }
}
