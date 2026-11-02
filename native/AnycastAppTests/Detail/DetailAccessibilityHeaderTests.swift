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
        #expect(header?.spacing == Spacing.xs)
        #expect(header?.arrangedSubviews.first === title)
        #expect(title.numberOfLines == 0)
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
