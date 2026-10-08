import UIKit
import Testing
@testable import Anycast

/// The v2 floating pill tab bar (Figma 243:7288 — 09 §3.1).
@MainActor
struct BottomTabBarTests {

    private func makeBar() -> (BottomTabBarView, [(index: Int, isRetap: Bool)]) {
        let bar = BottomTabBarView(items: [
            .init(title: "Inbox", icon: AppIcons.inbox),
            .init(title: "queue", icon: AppIcons.playlist),
            .init(title: "library", icon: AppIcons.subscriptions),
        ])
        bar.frame = CGRect(x: 0, y: 0, width: 440, height: 120)
        bar.layoutIfNeeded()
        var taps: [(Int, Bool)] = []
        bar.onTabTap = { taps.append(($0, $1)) }
        return (bar, taps)
    }

    @Test("Three equal-width chips inside the pill plus the search circle")
    func chipGeometry() {
        let (bar, _) = makeBar()
        // Chip frames live in the pill's coordinate space; convert to bar
        // coordinates before asserting page insets.
        let chips = bar.pillButtons.map { button -> CGRect in
            guard let chip = button.superview, let pill = chip.superview else { return .zero }
            return pill.convert(chip.frame, to: bar)
        }
        #expect(chips.count == 3)
        let widths = chips.map(\.width)
        #expect(widths.allSatisfy { abs($0 - widths[0]) < 0.5 }, "chips are not equal width: \(widths)")
        // Figma: chip body 64 in a 72 pt pill.
        #expect(abs(chips[0].height - 64) < 0.5, "chip height \(chips[0].height)")
        // Search circle is a 72 pt glass surface to the pill's trailing side.
        let searchHost = bar.searchButton.superview
        #expect(searchHost != nil)
        let search = searchHost?.convert(bar.searchButton.frame, to: bar) ?? .zero
        #expect(abs(search.width - BottomTabBarView.searchButtonSize) < 1)
        #expect(search.minX > chips[2].maxX, "search button overlaps the pill: \(search.minX) vs \(chips[2].maxX)")
        // The whole group respects the horizontal page inset.
        #expect(abs(chips[0].minX - (BottomTabBarView.horizontalInset + 4)) < 1, "leading inset \(chips[0].minX)")
        #expect(abs(search.maxX - (440 - BottomTabBarView.horizontalInset)) < 1, "trailing inset \(search.maxX)")
        // Accessibility identifiers the UITests rely on.
        #expect(bar.pillButtons[0].accessibilityIdentifier == "tab-0")
        #expect(bar.searchButton.accessibilityIdentifier == "tab-search")
    }

    @Test("Selection moves the gold chip; a second tap on the same chip reports a re-tap")
    func selectionAndRetap() {
        final class TapLog { var entries: [(Int, Bool)] = [] }
        let bar = BottomTabBarView(items: [
            .init(title: "Inbox", icon: AppIcons.inbox),
            .init(title: "queue", icon: AppIcons.playlist),
            .init(title: "library", icon: AppIcons.subscriptions),
        ])
        bar.frame = CGRect(x: 0, y: 0, width: 440, height: 120)
        bar.layoutIfNeeded()
        let log = TapLog()
        bar.onTabTap = { log.entries.append(($0, $1)) }
        bar.pillButtons[1].sendActions(for: .touchUpInside)
        #expect(bar.selectedTabIndex == 1)
        #expect(log.entries.last?.0 == 1 && log.entries.last?.1 == false)
        bar.pillButtons[1].sendActions(for: .touchUpInside)
        #expect(log.entries.last?.1 == true, "second tap on the active chip must report isRetap")
        // Programmatic select does not fire the tap callback.
        bar.select(2, animated: false)
        #expect(bar.selectedTabIndex == 2)
        #expect(log.entries.count == 2)
    }

    @Test("Search tap fires the search callback once")
    func searchTap() {
        let (bar, _) = makeBar()
        var count = 0
        bar.onSearchTap = { count += 1 }
        bar.searchButton.sendActions(for: .touchUpInside)
        #expect(count == 1)
    }
}
