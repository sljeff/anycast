import UIKit
import Testing
@testable import Anycast

/// The shared three-destination floating pill bar.
@MainActor
struct BottomTabBarTests {

    private func makeBar() -> (BottomTabBarView, [(index: Int, isRetap: Bool)]) {
        let bar = BottomTabBarView(items: [
            .init(title: "Podcast", icon: AppIcons.inbox),
            .init(title: "Playlist", icon: AppIcons.playlist),
            .init(title: "Discover", icon: AppIcons.discover),
        ])
        bar.frame = CGRect(x: 0, y: 0, width: 440, height: 120)
        bar.layoutIfNeeded()
        var taps: [(Int, Bool)] = []
        bar.onTabTap = { taps.append(($0, $1)) }
        return (bar, taps)
    }

    @Test("Three equal-width destination chips fill the glass pill")
    func chipGeometry() {
        let (bar, _) = makeBar()
        // Chip frames live in the pill's coordinate space; convert to bar
        // coordinates before asserting page insets.
        let chips = bar.pillButtons.map { button -> CGRect in
            guard let chip = button.superview,
                  let glassContent = chip.superview,
                  let pill = glassContent.superview else { return .zero }
            return pill.convert(chip.frame, to: bar)
        }
        #expect(chips.count == 3)
        let widths = chips.map(\.width)
        #expect(widths.allSatisfy { abs($0 - widths[0]) < 0.5 }, "chips are not equal width: \(widths)")
        // The 64 pt chip body keeps an eight-point inset in the pill.
        #expect(abs(chips[0].height - 64) < 0.5, "chip height \(chips[0].height)")
        // The pill respects the shared 16 pt page inset.
        #expect(abs(chips[0].minX - (BottomTabBarView.horizontalInset + 4)) < 1, "leading inset \(chips[0].minX)")
        #expect(abs(chips[2].maxX - (440 - BottomTabBarView.horizontalInset - 4)) < 1, "trailing inset \(chips[2].maxX)")
        // Accessibility identifiers the UITests rely on.
        #expect(bar.pillButtons[0].accessibilityIdentifier == "tab-0")
        #expect(bar.pillButtons.map(\.accessibilityIdentifier) == ["tab-0", "tab-1", "tab-2"])
    }

    @Test("Selection moves the gold chip; a second tap on the same chip reports a re-tap")
    func selectionAndRetap() {
        final class TapLog { var entries: [(Int, Bool)] = [] }
        let bar = BottomTabBarView(items: [
            .init(title: "Podcast", icon: AppIcons.inbox),
            .init(title: "Playlist", icon: AppIcons.playlist),
            .init(title: "Discover", icon: AppIcons.discover),
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

    @Test("Destination accessibility labels match the main navigation")
    func destinationAccessibility() {
        let (bar, _) = makeBar()
        #expect(bar.pillButtons.map(\.accessibilityLabel) == ["Podcast", "Playlist", "Discover"])
    }

    @Test("Destination labels scale with accessibility text")
    func dynamicTypeLabels() {
        let (bar, _) = makeBar()
        bar.traitOverrides.preferredContentSizeCategory = .accessibilityExtraExtraExtraLarge
        bar.setNeedsLayout()
        bar.layoutIfNeeded()

        let label = bar.pillButtons.first?.titleLabel
        #expect((label?.font.pointSize ?? 0) > 12)
        #expect((label?.frame.maxY ?? .infinity) <= (bar.pillButtons.first?.bounds.height ?? 0))
    }
}
