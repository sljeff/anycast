import UIKit
import Testing
@testable import Anycast

/// The detail sheet's accessibility-size header. The cover moves beside the
/// channel line, and the channel control stays a real button: the name label
/// must not become its superview, because a label does not receive touches.
@MainActor
struct DetailAccessibilityHeaderTests {

    private func makeDetail() -> DetailViewController {
        DetailViewController(
            episode: DetailViewController.Episode(
                title: "Reference episode — detail sheet layout",
                channelTitle: "Reference channel",
                pubDateMilliseconds: 1_700_000_000_000,
                durationMilliseconds: 80 * 60_000,
                rssFeedURL: "https://example.com/feed.xml",
                enclosureURL: "https://example.com/episode.mp3",
                descriptionHTML: "<p>Notes</p>"
            ),
            actions: [],
            htmlRenderer: HTMLContentRenderer()
        )
    }

    /// Hidden, and not key, so a size-category override can lay the header
    /// out without disturbing other suites. The caller keeps the window alive.
    private func layOut(
        _ detail: DetailViewController,
        in window: UIWindow,
        category: UIContentSizeCategory
    ) {
        detail.traitOverrides.preferredContentSizeCategory = category
        if window.rootViewController !== detail {
            window.rootViewController = detail
        }
        detail.view.frame = window.bounds
        detail.view.setNeedsLayout()
        detail.view.layoutIfNeeded()
        detail.view.layoutIfNeeded()
    }

    private func makeWindow() -> UIWindow {
        UIWindow(frame: CGRect(x: 0, y: 0, width: 402, height: 874))
    }

    @Test("Detail sheet corners are concentric with the 54 pt sheet")
    func sheetCornerRule() {
        #expect(Radius.sheetCorner == 54)
        #expect(Radius.concentric(insetFromSheetEdge: Spacing.sheetContent) == 26)
        #expect(Radius.sheetCapsuleHeight == 52)
        let arc = Radius.arcContentInset(Radius.sheetCorner)
        let cap = Radius.maximumSheetCapsuleHeight
        #expect(abs(cap - 2 * (Radius.sheetCorner - arc)) < 0.001)
        #expect(abs((Radius.sheetCorner - cap / 2) - arc) < 0.001)
    }

    @Test("Default size keeps the one-line channel button beside the 120 pt cover")
    func defaultSizeChannelButton() throws {
        let detail = makeDetail()
        let window = makeWindow()
        layOut(detail, in: window, category: .large)

        let button = try #require(channelButton(in: detail.view))
        #expect(button.superview is UIStackView)
        #expect(!(button.superview is UILabel))
        #expect(button.accessibilityLabel == "Open channel Reference channel")
        #expect(button.accessibilityTraits.contains(.button))
        #expect(button.configuration?.title == "Reference channel")
        #expect(button.configuration?.titleLineBreakMode == .byTruncatingTail)
        #expect(button.configuration?.contentInsets == NSDirectionalEdgeInsets.zero)
        #expect(button.bounds.height > 1)
        let hit = button.hitTest(CGPoint(x: button.bounds.midX, y: button.bounds.midY), with: nil)
        #expect(hit?.isDescendant(of: button) == true)

        let artwork = try #require(artworkView(in: detail.view))
        #expect(abs(artwork.bounds.width - 120) < 0.5)
        let header = artwork.superview?.superview as? UIStackView
        #expect(header?.axis == .horizontal)
        #expect(header?.spacing == Spacing.pageH)

        let title = try #require(label(in: detail.view, text: "Reference episode — detail sheet layout"))
        #expect(title.numberOfLines == 3)
        #expect(title.superview !== header)
        let paragraph = title.attributedText?.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle
        #expect(paragraph?.minimumLineHeight == 22)
        #expect(paragraph?.maximumLineHeight == 22)

        let play = try #require(playButton(in: detail.view))
        #expect(abs(play.bounds.height - Radius.sheetCapsuleHeight) < 0.5)
        #expect(play.showsLargeContentViewer == false)
    }

    @Test("Accessibility size taps the channel name block and shrinks the cover")
    func accessibilityChannelBlock() throws {
        let detail = makeDetail()
        let window = makeWindow()
        layOut(detail, in: window, category: .accessibilityExtraExtraExtraLarge)

        let button = try #require(channelButton(in: detail.view))
        let block = try #require(button.superview)
        #expect(!(block is UILabel))
        #expect(!(block is UIStackView))
        #expect(block.isUserInteractionEnabled)
        let name = block.subviews.compactMap { $0 as? UILabel }.first { $0.text == "Reference channel" }
        let channelName = try #require(name)
        #expect(channelName.isUserInteractionEnabled == false)
        #expect(channelName.numberOfLines == 0)
        #expect(button.accessibilityLabel == "Open channel Reference channel")
        #expect(button.accessibilityTraits.contains(.button))
        #expect(button.isAccessibilityElement)
        // The label draws the name. The button is only the hit target, so its
        // configuration title is nil rather than an empty stand-in.
        let configuration = try #require(button.configuration)
        #expect(configuration.title == nil)
        #expect(block.bounds.height > 1)
        let hit = block.hitTest(CGPoint(x: block.bounds.midX, y: block.bounds.midY), with: nil)
        #expect(hit?.isDescendant(of: button) == true)
        #expect(hit !== channelName)

        let artwork = try #require(artworkView(in: detail.view))
        #expect(abs(artwork.bounds.width - Spacing.sheetTitleH) < 0.5)
        let title = try #require(label(in: detail.view, text: "Reference episode — detail sheet layout"))
        let header = title.superview as? UIStackView
        #expect(header?.axis == .vertical)
        let titleGap = TypographyV2.scaledValue(
            Spacing.md, style: .emphasis, compatibleWith: detail.traitCollection
        )
        #expect(titleGap > Spacing.xs)
        #expect(abs((header?.spacing ?? 0) - titleGap) < 0.5)
        let metaGap = TypographyV2.scaledValue(
            Spacing.xs, style: .meta, compatibleWith: detail.traitCollection
        )
        let info = block.superview as? UIStackView
        #expect(abs((info?.spacing ?? 0) - metaGap) < 0.5)
        #expect(header?.arrangedSubviews.first === title)
        #expect(title.numberOfLines == 0)
        let titleLine = title.attributedText?.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle
        let emphasis = TypographyV2.emphasis
        let emphasisFont = emphasis.font(traits: detail.traitCollection)
        let expectedLine = emphasis.resolvedLineHeight(for: emphasisFont, traits: detail.traitCollection)
        #expect(abs((titleLine?.minimumLineHeight ?? 0) - expectedLine) < 0.5)
        #expect(titleLine?.minimumLineHeight == titleLine?.maximumLineHeight)

        let play = try #require(playButton(in: detail.view))
        #expect(play.showsLargeContentViewer == true)
        #expect(play.largeContentTitle?.isEmpty == false)
        #expect(play.interactions.contains { $0 is UILargeContentViewerInteraction })
        let capped = TypographyV2.emphasis.font(
            traits: detail.traitCollection,
            maximumPointSize: DetailViewController.playLabelMaximumPointSize
        )
        let natural = capped.lineHeight + Spacing.gap * 2
        let expectedHeight = min(max(natural, Radius.sheetCapsuleHeight), Radius.maximumSheetCapsuleHeight)
        #expect(expectedHeight < Radius.maximumSheetCapsuleHeight)
        #expect(abs(play.bounds.height - expectedHeight) < 1)
        #expect((play.titleLabel?.font.pointSize ?? 0) <= DetailViewController.playLabelMaximumPointSize + 0.5)
        #expect((play.titleLabel?.font.pointSize ?? 0) > 30)
        // The cover is beside the channel line, not in its own row above the title.
        #expect(artwork.superview?.superview !== header)

        // Leaving the accessibility size restores the one-line button.
        layOut(detail, in: window, category: .large)
        let restored = try #require(channelButton(in: detail.view))
        #expect(restored.superview is UIStackView)
        #expect(restored.configuration?.title == "Reference channel")
        #expect(restored.accessibilityLabel == "Open channel Reference channel")
        let restoredArtwork = try #require(artworkView(in: detail.view))
        #expect(abs(restoredArtwork.bounds.width - 120) < 0.5)
        let restoredHeader = restoredArtwork.superview?.superview as? UIStackView
        #expect(restoredHeader?.axis == .horizontal)
    }

    private func playButton(in root: UIView) -> UIButton? {
        root.subviewsRecursive().compactMap { $0 as? UIButton }.first {
            $0.accessibilityIdentifier == "detail-play"
        }
    }

    private func channelButton(in root: UIView) -> UIButton? {
        root.subviewsRecursive().compactMap { $0 as? UIButton }.first {
            $0.accessibilityLabel == "Open channel Reference channel"
        }
    }

    private func artworkView(in root: UIView) -> UIImageView? {
        root.subviewsRecursive().compactMap { $0 as? UIImageView }.first {
            $0.accessibilityLabel == "Episode artwork"
        }
    }

    private func label(in root: UIView, text: String) -> UILabel? {
        root.subviewsRecursive().compactMap { $0 as? UILabel }.first { $0.text == text }
    }
}

private extension UIView {
    func subviewsRecursive() -> [UIView] {
        var found: [UIView] = []
        for subview in subviews {
            found.append(subview)
            found.append(contentsOf: subview.subviewsRecursive())
        }
        return found
    }
}
