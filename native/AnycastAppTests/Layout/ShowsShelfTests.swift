import UIKit
import Testing
import AnycastKit
@testable import Anycast

/// The Podcast tab's shows shelf and Shows sheet: how many covers fit one
/// row, the order, the Inbox section set, and the sheet geometry.
@MainActor
struct ShowsShelfTests {

    private func show(_ name: String, updated: Int64? = nil) -> SubscriptionRow {
        SubscriptionRow(
            rssFeedUrl: "https://example.com/\(name).xml", title: name, lastUpdated: updated
        )
    }

    private func makeShelf(width: CGFloat, shows: [SubscriptionRow]) -> ShowsShelfView {
        let shelf = ShowsShelfView(frame: CGRect(x: 0, y: 0, width: width, height: 56))
        shelf.configure(shows: shows)
        shelf.layoutIfNeeded()
        return shelf
    }

    /// The shelf's visible items, left to right.
    private func visibleItems(_ shelf: ShowsShelfView) -> [UIView] {
        guard let stack = shelf.subviews.compactMap({ $0 as? UIStackView }).first else { return [] }
        return stack.arrangedSubviews.filter { !$0.isHidden }
    }

    // MARK: - Fit count

    @Test("A 402 pt row holds four covers and the button")
    func fitCountAt402() {
        #expect(ShowsShelfLayout.itemCapacity(width: 402) == 5)
        #expect(ShowsShelfLayout.coverCount(width: 402, showCount: 9) == 4)
        // Fewer shows than room: all of them, no padding items.
        #expect(ShowsShelfLayout.coverCount(width: 402, showCount: 2) == 2)
        #expect(ShowsShelfLayout.coverCount(width: 402, showCount: 0) == 0)
    }

    @Test("The capacity follows the width and always keeps the button")
    func capacityFollowsWidth() {
        // 5 items need 5 * 56 + 4 * 12 = 328 pt between the 16 pt insets.
        #expect(ShowsShelfLayout.itemCapacity(width: 360) == 5)
        #expect(ShowsShelfLayout.itemCapacity(width: 359) == 4)
        #expect(ShowsShelfLayout.itemCapacity(width: 320) == 4)
        #expect(ShowsShelfLayout.itemCapacity(width: 1024) == 14)
        #expect(ShowsShelfLayout.itemCapacity(width: 40) == 1)
        #expect(ShowsShelfLayout.coverCount(width: 40, showCount: 5) == 0)
    }

    @Test("The shelf lays out one leading-aligned row ending in the button")
    func shelfLayout() {
        let shows = (1...8).map { show("S\($0)", updated: Int64($0)) }
        let shelf = makeShelf(width: 402, shows: shows)
        let items = visibleItems(shelf)
        #expect(items.count == 5)
        #expect(shelf.visibleCoverCount == 4)
        #expect(items.last is AnycastIconButton, "the All shows button is always last")
        #expect(items.last?.accessibilityLabel == "All shows")

        let frames = items.map { $0.convert($0.bounds, to: shelf) }
        #expect(frames.first?.minX == Spacing.pageH)
        for index in frames.indices {
            #expect(frames[index].size == CGSize(width: 56, height: 56))
            #expect(frames[index].minY == frames[0].minY, "one row, no wrap")
            if index > 0 {
                #expect(frames[index].minX - frames[index - 1].maxX == 12)
            }
        }
        if let last = frames.last {
            #expect(last.maxX <= 402 - Spacing.pageH)
        }
    }

    @Test("The row recomputes when the width changes")
    func shelfRecomputesOnWidthChange() {
        let shows = (1...8).map { show("S\($0)") }
        let shelf = makeShelf(width: 402, shows: shows)
        #expect(shelf.visibleCoverCount == 4)

        shelf.frame.size.width = 320
        shelf.layoutIfNeeded()
        #expect(shelf.visibleCoverCount == 3)
        #expect(visibleItems(shelf).last is AnycastIconButton)

        shelf.frame.size.width = 440
        shelf.layoutIfNeeded()
        #expect(shelf.visibleCoverCount == 5)
        #expect(visibleItems(shelf).last is AnycastIconButton)
    }

    @Test("Covers carry the show name and a tap reports the show")
    func coversReportTaps() {
        let shows = [show("Alpha", updated: 2), show("Beta", updated: 1)]
        let shelf = makeShelf(width: 402, shows: shows)
        var tapped: [String?] = []
        shelf.onSelect = { tapped.append($0.title) }
        var allShowsTaps = 0
        shelf.onAllShows = { allShowsTaps += 1 }

        let items = visibleItems(shelf)
        #expect(items.count == 3)
        #expect(items[0].accessibilityLabel == "Alpha")
        #expect((items[1] as? UIControl)?.isEnabled == true)
        (items[1] as? UIControl)?.sendActions(for: .touchUpInside)
        (items[2] as? UIControl)?.sendActions(for: .touchUpInside)
        #expect(tapped == ["Beta"])
        #expect(allShowsTaps == 1)
    }

    @Test("Metadata rewritten in place reaches the covers")
    func inPlaceMetadataUpdate() {
        let url = "https://example.com/feed.xml"
        let shelf = makeShelf(width: 402, shows: [SubscriptionRow(rssFeedUrl: url, title: "Old")])
        #expect(visibleItems(shelf).first?.accessibilityLabel == "Old")

        shelf.configure(shows: [SubscriptionRow(rssFeedUrl: url, title: "New")])
        shelf.layoutIfNeeded()
        #expect(visibleItems(shelf).first?.accessibilityLabel == "New")
    }

    // MARK: - Order

    @Test("Shows order by lastUpdated descending with never-updated last")
    func ordering() {
        let rows = [
            show("none-1"),
            show("old", updated: 100),
            show("new", updated: 300),
            show("none-2"),
            show("mid", updated: 200),
            show("tie", updated: 200),
        ]
        let titles = ShowsShelfLayout.ordered(rows).map { $0.title ?? "" }
        #expect(titles == ["new", "mid", "tie", "old", "none-1", "none-2"], "got \(titles)")
    }

    // MARK: - Inbox sections

    @Test("The shelf is hidden without subscriptions")
    func shelfHiddenWithoutSubscriptions() {
        #expect(
            InboxPageViewController.sections(hasShelf: false, hasStrip: false, hasCards: true)
                == [.cards, .tail]
        )
        #expect(
            InboxPageViewController.sections(hasShelf: true, hasStrip: false, hasCards: true)
                == [.shelf, .cards, .tail]
        )
    }

    @Test("The strip shows only with categories beyond All")
    func stripHiddenWithOnlyAll() {
        let strip = CategoryStripView()
        strip.configure(categories: [], selected: nil)
        #expect(strip.hasFilters == false)
        strip.configure(categories: ["", " , "], selected: nil)
        #expect(strip.hasFilters == false, "blank categories add no chip")

        strip.configure(categories: ["tech,news"], selected: nil)
        #expect(strip.hasFilters)

        #expect(
            InboxPageViewController.sections(hasShelf: true, hasStrip: true, hasCards: false)
                == [.shelf, .strip, .cards]
        )
    }

    // MARK: - Shows sheet

    @Test("Sheet height is title block plus grid, between 350 pt and the large detent")
    func sheetDetentHeight() {
        let line: CGFloat = 20
        // 3 columns at a 334 pt grid: (334 - 24) / 3 = 103.33 pt wide items.
        let item = ShowsSheetLayout.itemHeight(gridWidth: 334, nameLineHeight: line)
        #expect(abs(item - (310.0 / 3 + 6 + 20)) < 0.001)

        #expect(ShowsSheetLayout.gridHeight(gridWidth: 334, count: 0, nameLineHeight: line) == 0)
        #expect(ShowsSheetLayout.gridHeight(gridWidth: 334, count: 3, nameLineHeight: line) == item)
        #expect(abs(ShowsSheetLayout.gridHeight(gridWidth: 334, count: 4, nameLineHeight: line) - (2 * item + 20)) < 0.001)

        let small = ShowsSheetLayout.detentHeight(
            titleLineHeight: 22, gridHeight: item, safeAreaBottom: 34, maximum: 800
        )
        #expect(small == 350, "short content still gets the 350 pt floor")

        let grid = ShowsSheetLayout.gridHeight(gridWidth: 334, count: 9, nameLineHeight: line)
        // With a 34 pt safe area the system supplies the bottom gap (the
        // larger of 28 and the safe area): nothing more is counted.
        let grown = ShowsSheetLayout.detentHeight(
            titleLineHeight: 22, gridHeight: grid, safeAreaBottom: 34, maximum: 800
        )
        #expect(abs(grown - (28 + 22 + 16 + grid)) < 0.001, "grows to fit")
        // Without a safe area the 28 pt inset is counted in full.
        let flat = ShowsSheetLayout.detentHeight(
            titleLineHeight: 22, gridHeight: grid, safeAreaBottom: 0, maximum: 800
        )
        #expect(abs(flat - (28 + 22 + 16 + grid + 28)) < 0.001)
        #expect(ShowsSheetLayout.bottomGap(safeAreaBottom: 34) == 34)
        #expect(ShowsSheetLayout.bottomGap(safeAreaBottom: 0) == 28)

        let capped = ShowsSheetLayout.detentHeight(
            titleLineHeight: 22, gridHeight: 5000, safeAreaBottom: 34, maximum: 800
        )
        #expect(capped == 800, "capped at the large detent")
    }

    @Test("The sheet titles Shows with the count and lists every show in three columns")
    func sheetContent() {
        let shows = (1...7).map { show("S\($0)") }
        let sheet = ShowsSheetViewController(shows: shows)
        sheet.view.frame = CGRect(x: 0, y: 0, width: 390, height: 600)
        sheet.view.layoutIfNeeded()

        let label = sheet.view.subviews.compactMap { $0 as? UILabel }
            .first { $0.accessibilityIdentifier == "shows-sheet-title" }
        #expect(label?.attributedText?.string == "Shows · 7")

        let grid = sheet.view.subviews.compactMap { $0 as? UICollectionView }.first
        #expect(grid?.numberOfItems(inSection: 0) == 7)
        grid?.layoutIfNeeded()
        let frames = (0..<4).compactMap { grid?.layoutAttributesForItem(at: IndexPath(item: $0, section: 0))?.frame }
        #expect(frames.count == 4)
        if frames.count == 4 {
            #expect(frames[0].minY == frames[2].minY, "three to a row")
            #expect(frames[3].minY > frames[0].minY, "fourth wraps to the next row")
            #expect(frames[1].minX - frames[0].maxX == 12, "12 pt column gap")
            #expect(abs(frames[3].minY - frames[0].maxY - 20) < 0.5, "20 pt row gap (got \(frames[3].minY - frames[0].maxY))")
        }
    }
}
