import UIKit
import Testing
@testable import Anycast

/// ChipTabBarView layout invariants — the regression guards for the
/// strip's two shipped defects: (1) a fitted strip whose content ran wider
/// than the viewport (trailing clip + an 8 pt horizontal jog on every
/// selection), and (2) chips distributed flush against the screen edges.
/// Both are cheap to measure here and expensive to notice by eye, so the
/// strip re-verifies them on every suite run.
@MainActor
struct ChipTabBarLayoutTests {

    /// Host on a real window: scroll-view frameLayoutGuide pins do not
    /// settle deterministically for unhosted views.
    private func hostStrip(titles: [String], width: CGFloat = 402) -> ChipTabBarView {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: width, height: 120))
        let strip = ChipTabBarView(titles: titles)
        strip.translatesAutoresizingMaskIntoConstraints = false
        window.addSubview(strip)
        NSLayoutConstraint.activate([
            strip.leadingAnchor.constraint(equalTo: window.leadingAnchor),
            strip.trailingAnchor.constraint(equalTo: window.trailingAnchor),
            strip.topAnchor.constraint(equalTo: window.topAnchor),
            strip.heightAnchor.constraint(equalToConstant: ChipTabBarView.chipHeight),
        ])
        window.layoutIfNeeded()
        return strip
    }

    @Test("Fitted strip: equal halves, each title centered in its own half")
    func fittedStripSplitsEvenly() {
        let strip = hostStrip(titles: ["Channels", "Episodes"])
        let scroll = strip.scrollView
        // Content wider than the viewport with nothing to scroll to is the
        // clip/jog defect; narrower means left-clustered chips.
        #expect(
            abs(scroll.contentSize.width - strip.bounds.width) < 0.5,
            "contentSize \(scroll.contentSize.width) must equal bounds \(strip.bounds.width)"
        )
        let labels = Self.titleLabels(in: scroll)
        #expect(labels.count == 2)
        // The chips are the labels' superviews; measure both in strip
        // coordinates (label/chip frames are otherwise view-local).
        guard let chips = labels.compactMap({ $0.superview }) as? [UIView], chips.count == 2 else {
            Issue.record("chip containers not found"); return
        }
        let frames = chips
            .map { $0.convert($0.bounds, to: strip) }
            .sorted { $0.minX < $1.minX }
        guard frames.count == 2, let first = frames.first, let last = frames.last else { return }
        let width = strip.bounds.width
        let contentWidth = width - 2 * Spacing.pageH
        let segment = contentWidth / 2
        #expect(abs(first.width - segment) < 0.5, "leading chip must take half the content width")
        #expect(abs(last.width - segment) < 0.5, "trailing chip must take half the content width")
        // Each chip centers in its own half — the quarter points of the
        // CONTENT box (inside the page margins), not the raw screen halves:
        // exact screen quarters would require either edge-hugging chips or
        // a phantom-scrollable strip.
        let leftCenter = Spacing.pageH + contentWidth * 0.25
        let rightCenter = Spacing.pageH + contentWidth * 0.75
        #expect(abs(first.midX - leftCenter) < 1.0, "leading title must center in the left half")
        #expect(abs(last.midX - rightCenter) < 1.0, "trailing title must center in the right half")
        // Neither chip crosses into the other's half.
        #expect(first.maxX <= last.minX + 0.5)
    }

    @Test("Selection round-trips never move a fitted strip's content offset")
    func selectionDoesNotJog() {
        let strip = hostStrip(titles: ["Channels", "Episodes"])
        strip.select(1, animated: false)
        strip.select(0, animated: false)
        strip.select(1, animated: false)
        #expect(strip.scrollView.contentOffset.x == 0, "selection jogged the strip")
    }

    @Test("Overflowing strip keeps its natural content width and scrolls")
    func overflowingStripScrolls() {
        let titles = (1...12).map { "Category \($0) with a long name" }
        let strip = hostStrip(titles: titles)
        let scroll = strip.scrollView
        #expect(
            scroll.contentSize.width > scroll.bounds.width,
            "an overflowing strip must stay scrollable, not compress its chips"
        )
        // Edge padding exists on both ends of the scroll range.
        let labels = Self.titleLabels(in: scroll)
        let frames = labels.map { $0.convert($0.bounds, to: strip) }.sorted { $0.minX < $1.minX }
        if let first = frames.first {
            #expect(first.minX >= Spacing.pageH + Spacing.gap - 0.5)
        }
    }

    private static func titleLabels(in view: UIView) -> [UILabel] {
        view.subviews.flatMap { subview -> [UILabel] in
            switch subview {
            case let label as UILabel: return [label]
            default: return titleLabels(in: subview)
            }
        }
    }
}
