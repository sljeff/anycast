import UIKit
import Testing
import AnycastKit
@testable import Anycast

/// Regression guards for the skeleton-to-content handoff on reused rows
/// (the Discover bug: after a category switch, rows dequeued as skeletons
/// kept drawing bars in the text area once data arrived — the covers, set
/// on a separate image view, loaded fine — and further reused rows down
/// the list did the same).
///
/// Each case paints a skeleton and then real content on the SAME instance —
/// the reuse path a collection view takes — and asserts the label wears its
/// base style again: the base font, the base color, the real string, and no
/// bar residue (no background fill, no clear foreground) anywhere in the
/// attributed text.
@MainActor
struct SkeletonReuseTests {

    /// Asset-catalog colors are trait-dynamic; compare resolved values so
    /// the host's appearance cannot change the outcome.
    private static let traits = UITraitCollection(userInterfaceStyle: .light)

    // MARK: - PodcastCardCell (Discover rows)

    @Test("A channel card reused from a skeleton shows the real title and description")
    func podcastCard() {
        let cell = PodcastCardCell(frame: CGRect(x: 0, y: 0, width: 358, height: PodcastCardCell.rowHeight))
        cell.configureSkeleton()

        let cellLabels = labels(in: cell.contentView)
        #expect(cellLabels.count == 2, "title + description")
        let title = cellLabels.first { Self.sameFace($0.font, TypographyV2.emphasis.font()) }
        let description = cellLabels.last { Self.sameFace($0.font, TypographyV2.meta.font()) }
        #expect(title != nil)
        #expect(description != nil)
        // The skeleton really painted bars (the taint this file pins).
        #expect(title?.textColor == UIColor.clear)
        #expect(description?.textColor == UIColor.clear)

        cell.configure(PodcastCardContent(
            rssFeedURL: "https://example.com/feed.xml",
            title: "A real channel title",
            description: "A real description",
            imageURL: nil
        ))

        expectRealText(
            title.unsafelyUnwrapped, "A real channel title",
            baseFont: TypographyV2.emphasis.font(), baseColor: TypographyV2.emphasis.color
        )
        expectRealText(
            description.unsafelyUnwrapped, "A real description",
            baseFont: TypographyV2.meta.font(), baseColor: TypographyV2.meta.color
        )
    }

    // MARK: - ChannelEpisodeRowCell (Channel page)

    @Test("A channel episode row reused from a skeleton shows the real title and meta")
    func channelEpisodeRow() {
        let cell = ChannelEpisodeRowCell(frame: CGRect(x: 0, y: 0, width: 358, height: ChannelEpisodeRowCell.minimumHeight))
        cell.configureSkeleton()

        let cellLabels = labels(in: cell.contentView)
        #expect(cellLabels.count == 2, "title + meta")
        let title = cellLabels.first { Self.sameFace($0.font, TypographyV2.emphasis.font()) }
        let meta = cellLabels.last { Self.sameFace($0.font, TypographyV2.meta.font().monospacedDigits()) }
        #expect(title != nil)
        #expect(meta != nil)
        #expect(title?.textColor == UIColor.clear)
        #expect(meta?.textColor == UIColor.clear)

        cell.configure(title: "A real episode title", meta: "Nov 14 · 42 min")

        expectRealText(
            title.unsafelyUnwrapped, "A real episode title",
            baseFont: TypographyV2.emphasis.font(), baseColor: TypographyV2.emphasis.color
        )
        expectRealText(
            meta.unsafelyUnwrapped, "Nov 14 · 42 min",
            baseFont: TypographyV2.meta.font().monospacedDigits(), baseColor: TypographyV2.meta.color
        )
    }

    // MARK: - SearchFeedAddressViewController (pasted address row)

    @Test("The pasted-feed row shows the real title and host once the feed loads")
    func feedAddressRow() async {
        let address = "https://feeds.example.com/show.xml"
        let page = SearchFeedAddressViewController(
            context: nil,
            fetch: { _ in
                PodcastImportData(
                    subscription: SubscriptionRow(rssFeedUrl: address, title: "The Show", description: "d"),
                    feedEpisodes: []
                )
            },
            followed: { [] },
            subscribe: { _ in true }
        )
        page.loadViewIfNeeded()
        page.load(address: address)
        for _ in 0..<100 where page.phase == .loading {
            try? await Task.sleep(for: .milliseconds(20))
        }
        #expect(page.phase != .loading, "phase: \(String(describing: page.phase))")

        // The one row plate holds the title and host labels (the failure
        // message label lives outside it and stays hidden).
        guard let plate = page.view.subviewsRecursive().first(where: {
            ($0 as? UIControl)?.accessibilityIdentifier == "search-feed-row"
        }) else {
            Issue.record("feed row plate not found")
            return
        }
        let plateLabels = labels(in: plate)
        #expect(
            plateLabels.count == 2,
            "title + host; got \(plateLabels.count): \(plateLabels.map { "\($0.text ?? "-") \($0.font)" })"
        )
        let title = plateLabels.first { Self.sameFace($0.font, TypographyV2.emphasis.font()) }
        let host = plateLabels.last { Self.sameFace($0.font, TypographyV2.meta.font()) }
        #expect(title != nil)
        #expect(host != nil)

        expectRealText(
            title.unsafelyUnwrapped, "The Show",
            baseFont: TypographyV2.emphasis.font(), baseColor: Theme.onSurface
        )
        expectRealText(
            host.unsafelyUnwrapped, "feeds.example.com",
            baseFont: TypographyV2.meta.font(), baseColor: Theme.onSurfaceVariant
        )
    }

    // MARK: - Assertions

    /// The label shows `expected` in its base style with no bar residue:
    /// real string, base font, base color, and nothing bar-like (background
    /// fill or clear foreground) left in the attributed text.
    private func expectRealText(
        _ label: UILabel, _ expected: String, baseFont: UIFont, baseColor: UIColor
    ) {
        #expect(label.text == expected, "text")
        #expect(
            Self.sameFace(label.font, baseFont),
            "font: \(label.font) ≠ base \(baseFont)"
        )
        #expect(
            label.textColor?.resolvedColor(with: Self.traits) == baseColor.resolvedColor(with: Self.traits),
            "color: \(String(describing: label.textColor)) ≠ base \(baseColor)"
        )

        let attributed = label.attributedText ?? NSAttributedString(string: "")
        let full = NSRange(location: 0, length: attributed.length)
        var residue: [String] = []
        attributed.enumerateAttribute(.backgroundColor, in: full) { value, _, _ in
            if value != nil { residue.append("background fill") }
        }
        attributed.enumerateAttribute(.foregroundColor, in: full) { value, _, _ in
            if let color = value as? UIColor,
               color.resolvedColor(with: Self.traits).cgColor.alpha == 0 {
                residue.append("clear foreground")
            }
        }
        #expect(residue.isEmpty, "bar residue left in attributed text: \(residue)")
    }

    // MARK: - View traversal

    /// The labels under `view`, not counting a button's internal title
    /// label (the Follow button's is a semibold-17 UILabel too).
    private func labels(in view: UIView) -> [UILabel] {
        var found: [UILabel] = []
        for subview in view.subviews {
            if let label = subview as? UILabel {
                found.append(label)
            } else if subview is UIButton {
                continue
            } else {
                found.append(contentsOf: labels(in: subview))
            }
        }
        return found
    }

    /// Face-and-size equality: `UIFont` equality itself is unreliable for
    /// separately built scaled fonts.
    private static func sameFace(_ a: UIFont, _ b: UIFont) -> Bool {
        a.fontName == b.fontName && a.pointSize == b.pointSize
    }
}

private extension UIView {
    func subviewsRecursive() -> [UIView] {
        subviews + subviews.flatMap { $0.subviewsRecursive() }
    }
}
