import UIKit
import Testing
import AnycastKit
@testable import Anycast

/// Regression guards for the reuse-audit fixes (native/build/runs/
/// reuse-audit/report.md, findings 1-4): a card's in-flight HTML
/// description parse must never land on content configured afterwards; a
/// reused cell must never inherit an entrance pose; an attributed status
/// line must not taint later plain subtitles; the channel header's cover
/// uses the shared local placeholder instead of a remote fallback URL.
@MainActor
struct ReuseStateResetTests {

    /// Asset-catalog colors are trait-dynamic; compare resolved values.
    private static let traits = UITraitCollection(userInterfaceStyle: .light)

    private func labels(in view: UIView) -> [UILabel] {
        var found: [UILabel] = []
        for subview in view.subviews {
            if let label = subview as? UILabel { found.append(label) }
            else { found.append(contentsOf: labels(in: subview)) }
        }
        return found
    }

    private func label(identifier: String, in view: UIView) -> UILabel? {
        labels(in: view).first { $0.accessibilityIdentifier == identifier }
    }

    // MARK: - 1. EpisodeCardCell description source changes

    @Test("A plain description replaces a stale in-flight HTML parse")
    func plainDescriptionReplacesStaleParse() async {
        let cell = EpisodeCardCell(frame: CGRect(x: 0, y: 0, width: 358, height: 94))
        cell.configure(EpisodeCardContent(
            title: "Episode A", channelTitle: "Show", rightText: "5m",
            descriptionHTML: "<p>Alpha episode description body</p>", imageURL: nil
        ), actions: [])
        // Same cell, different episode, PLAIN description — no reuse between.
        cell.configure(EpisodeCardContent(
            title: "Episode B", channelTitle: "Show", rightText: "5m",
            descriptionHTML: nil, imageURL: nil,
            descriptionPlainText: "Bravo plain description"
        ), actions: [])
        // Long enough for the cancelled parse to have landed before the fix.
        for _ in 0..<50 { try? await Task.sleep(for: .milliseconds(10)) }
        #expect(
            label(identifier: "episode-card-description", in: cell)?.text == "Bravo plain description",
            "stale HTML text must not overwrite the plain description"
        )
    }

    @Test("A missing description clears a stale in-flight HTML parse")
    func nilDescriptionClearsStaleParse() async {
        let cell = EpisodeCardCell(frame: CGRect(x: 0, y: 0, width: 358, height: 94))
        cell.configure(EpisodeCardContent(
            title: "Episode A", channelTitle: "Show", rightText: "5m",
            descriptionHTML: "<p>Alpha episode description body</p>", imageURL: nil
        ), actions: [])
        cell.configure(EpisodeCardContent(
            title: "Episode B", channelTitle: "Show", rightText: "5m",
            descriptionHTML: nil, imageURL: nil
        ), actions: [])
        for _ in 0..<50 { try? await Task.sleep(for: .milliseconds(10)) }
        #expect(
            label(identifier: "episode-card-description", in: cell)?.text == "",
            "stale HTML text must not appear on a description-less card"
        )
    }

    @Test("A same-HTML reconfigure neither blanks nor restarts the parse")
    func sameHTMLReconfigureKeepsResolve() async {
        let cell = EpisodeCardCell(frame: CGRect(x: 0, y: 0, width: 358, height: 94))
        let content = EpisodeCardContent(
            title: "Episode A", channelTitle: "Show", rightText: "5m",
            descriptionHTML: "<p>Alpha episode description body</p>", imageURL: nil
        )
        cell.configure(content, actions: [])
        let description = label(identifier: "episode-card-description", in: cell)
        #expect(description != nil)
        // Wait for the async resolve to land.
        for _ in 0..<100 where (description?.text ?? "").isEmpty {
            try? await Task.sleep(for: .milliseconds(10))
        }
        let resolved = description?.text ?? ""
        #expect(!resolved.isEmpty, "the HTML description should resolve")

        // The playback-tick reconfigure with identical HTML keeps the text.
        cell.configure(content, actions: [])
        #expect(description?.text == resolved, "same-HTML reconfigure must not blank the label")
        for _ in 0..<30 { try? await Task.sleep(for: .milliseconds(10)) }
        #expect(description?.text == resolved, "same-HTML reconfigure must not restart the parse")
    }

    // MARK: - 2. Entrance poses reset on reuse

    /// Taints a cell the way an entrance animation would: a zero-alpha
    /// offset pose (model values) plus a lingering animation.
    private func taint(_ cell: UICollectionViewCell, includeSelf: Bool = false) {
        cell.contentView.alpha = 0
        cell.contentView.transform = CGAffineTransform(translationX: 0, y: 24)
        if includeSelf { cell.alpha = 0 }
        UIView.animate(withDuration: 30) { cell.contentView.alpha = 0.5 }
    }

    private func expectPoseReset(_ cell: UICollectionViewCell, includeSelf: Bool = false) {
        // Model values are the contract; a same-turn animation commit is a
        // test artifact (it lands after prepareForReuse's removeAllAnimations).
        #expect(cell.contentView.alpha == 1, "contentView.alpha")
        #expect(cell.contentView.transform == .identity, "contentView.transform")
        if includeSelf { #expect(cell.alpha == 1, "cell.alpha") }
    }

    @Test("prepareForReuse clears entrance poses on the plate and grid cells")
    func entrancePoseResets() {
        let podcast = PodcastCardCell(frame: CGRect(x: 0, y: 0, width: 358, height: 88))
        taint(podcast)
        podcast.prepareForReuse()
        expectPoseReset(podcast)

        // The Channel row's skeleton fade animates the cell itself and the
        // staggered arrival the content view — both must reset.
        let row = ChannelEpisodeRowCell(frame: CGRect(x: 0, y: 0, width: 358, height: 70))
        taint(row, includeSelf: true)
        row.prepareForReuse()
        expectPoseReset(row, includeSelf: true)

        let cover = ShowCoverCell(frame: CGRect(x: 0, y: 0, width: 120, height: 150))
        taint(cover)
        cover.prepareForReuse()
        expectPoseReset(cover)

        let recent = SearchRecentCell(frame: CGRect(x: 0, y: 0, width: 358, height: 44))
        taint(recent)
        recent.prepareForReuse()
        expectPoseReset(recent)

        let category = SearchCategoryCell(frame: CGRect(x: 0, y: 0, width: 120, height: 44))
        taint(category)
        category.prepareForReuse()
        expectPoseReset(category)
    }

    // MARK: - 3. Membership status subtitle

    @Test("An attributed status line cannot taint later plain subtitles")
    func membershipSubtitleStyleReset() {
        let row = AccountRowView(verticalPadding: 12)
        // The issue rendering: attributed runs (here deliberately with a
        // style that differs from the base, so the reset is what keeps the
        // plain path honest — the shipped attributed run starts with the
        // base style by coincidence).
        let attributed = NSMutableAttributedString(string: "Renews Mar 1 · ", attributes: [
            .font: TypographyV2.emphasis.font(), .foregroundColor: Theme.error,
        ])
        attributed.append(NSAttributedString(string: "Payment failed", attributes: [
            .font: TypographyV2.emphasis.font(), .foregroundColor: Theme.error,
        ]))
        row.subtitleLabel.attributedText = attributed
        row.subtitleLabel.isHidden = false

        row.setSubtitle("Plain status line")

        let label = row.subtitleLabel
        #expect(label.text == "Plain status line")
        #expect(
            label.font.fontName == TypographyV2.meta.font().fontName
                && label.font.pointSize == TypographyV2.meta.font().pointSize,
            "font: \(label.font) ≠ base \(TypographyV2.meta.font())"
        )
        #expect(
            label.textColor?.resolvedColor(with: Self.traits)
                == Theme.onSurfaceVariant.resolvedColor(with: Self.traits),
            "color: \(String(describing: label.textColor)) ≠ base"
        )
        // No attributed residue (background fill / tinted foreground).
        let text = label.attributedText ?? NSAttributedString(string: "")
        let full = NSRange(location: 0, length: text.length)
        var residue: [String] = []
        text.enumerateAttribute(.backgroundColor, in: full) { value, _, _ in
            if value != nil { residue.append("background fill") }
        }
        text.enumerateAttribute(.foregroundColor, in: full) { value, _, _ in
            if let color = value as? UIColor,
               color.resolvedColor(with: Self.traits) != Theme.onSurfaceVariant.resolvedColor(with: Self.traits) {
                residue.append("tinted foreground")
            }
        }
        #expect(residue.isEmpty, "attributed residue: \(residue)")
    }

    // MARK: - 4. Channel header cover placeholder

    @Test("A channel without artwork shows the shared local placeholder")
    func channelHeaderCoverPlaceholder() {
        let header = ChannelHeaderView(frame: CGRect(x: 0, y: 0, width: 390, height: 400))
        header.configure(
            channel: SubscriptionRow(
                rssFeedUrl: "https://example.com/feed.xml", title: "The Show", description: nil
            ),
            dominant: ChannelViewModel.playerWarmColor
        )
        // The cover slot must carry the initial-on-sand placeholder, not
        // stay empty and not start a remote placeholder request.
        let covers = header.subviewsRecursive().compactMap { $0 as? UIImageView }
        #expect(covers.contains { $0.image != nil }, "no placeholder image on the header cover")
    }
}

private extension UIView {
    func subviewsRecursive() -> [UIView] {
        subviews + subviews.flatMap { $0.subviewsRecursive() }
    }
}
