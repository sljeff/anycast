import UIKit
import Testing
@testable import Anycast

/// UIKit-level onboarding pieces: wrapping layout, line heights, playlist
/// tray, live subscription status, transcript emphasis, and warm tiles.
@MainActor
struct OnboardingComponentsTests {

    // MARK: - Flow layout wrapping

    @Test("A chip wider than the row wraps and grows the row's height")
    func flowLayoutWrapsOversizedChip() {
        let longTitle = String(repeating: "Design ", count: 30)
        let chip = OnboardingChipButton(title: longTitle)
        let layout = OnboardingFlowLayoutView(items: [chip])
        layout.frame = CGRect(x: 0, y: 0, width: 200, height: 100)
        layout.layoutIfNeeded()

        // A single-line chip is the 44 pt minimum; a wrapped one must be
        // taller than that, and no wider than the row.
        #expect(layout.intrinsicContentSize.height > 44)
        #expect(chip.bounds.height > 44)
        #expect(chip.bounds.width <= 200)
    }

    @Test("Chips that fit stay on single-line height")
    func flowLayoutSingleLine() {
        let layout = OnboardingFlowLayoutView(items: [
            OnboardingChipButton(title: "Tech"),
            OnboardingChipButton(title: "News"),
        ])
        layout.frame = CGRect(x: 0, y: 0, width: 320, height: 100)
        layout.layoutIfNeeded()

        #expect(layout.intrinsicContentSize.height > 0)
        #expect(layout.intrinsicContentSize.height < 60)
    }

    // MARK: - Typography line heights

    @Test("OnboardingUI.label applies TypographyV2 line height attributes and preserves them on update")
    func styledLabelAppliesLineHeights() {
        let label = OnboardingUI.label("Line one", style: TypographyV2.body)
        let expected = TypographyV2.body.attributes(traits: label.traitCollection)[.paragraphStyle] as? NSParagraphStyle
        let initial = label.attributedText?.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle

        #expect(expected != nil)
        #expect(initial?.minimumLineHeight == expected?.minimumLineHeight)
        #expect(initial?.maximumLineHeight == expected?.maximumLineHeight)

        label.text = "Line two"
        let updated = label.attributedText?.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle
        #expect(updated?.minimumLineHeight == expected?.minimumLineHeight)
        #expect(updated?.maximumLineHeight == expected?.maximumLineHeight)
    }

    // MARK: - Playlist tray

    @Test("Playlist tray inserts new sample episodes and removes unqueued ones")
    func playlistTrayUpdatesRows() {
        let tray = OnboardingPlaylistTrayView()
        #expect(tray.rowCount == 0)

        tray.setEpisodes([OnboardingSamples.episodes[0], OnboardingSamples.episodes[1]], animated: false)
        #expect(tray.rowCount == 2)

        tray.setEpisodes([OnboardingSamples.episodes[1]], animated: false)
        #expect(tray.rowCount == 1)
    }

    // MARK: - Artwork tiles

    @Test("Warm artwork tiles draw distinct images in code for all sample shows")
    func warmArtworkTilesAreDistinct() {
        let images = OnboardingSamples.episodes.map { OnboardingArtworkTile.image(for: $0.show) }
        for image in images {
            #expect(image.size == CGSize(width: 88, height: 88))
        }
        let uniquePayloads = Set(images.compactMap { $0.pngData() })
        #expect(uniquePayloads.count == 3)
    }

    // MARK: - Live subscription status

    @MainActor
    private final class SubscriptionCountBox {
        var value = 0
    }

    @Test("Subscriptions step updates live status line on notification and hides at zero")
    func subscriptionsLiveStatusUpdatesOnNotification() async {
        let countBox = SubscriptionCountBox()
        let step = OnboardingSubscriptionsStepView(
            fetchSubscriptionCount: { countBox.value },
            onImportFile: {},
            onPasteFeed: {}
        )

        try? await Task.sleep(for: .milliseconds(20))
        #expect(step.statusText == nil)

        countBox.value = 2
        NotificationCenter.default.post(name: ShowsShelfLayout.subscriptionsDidChange, object: nil)
        let expectedTwo = "Following 2 shows · New episodes are in your Inbox"
        for _ in 0..<50 where step.statusText != expectedTwo {
            try? await Task.sleep(for: .milliseconds(10))
        }
        #expect(step.statusText == expectedTwo)

        countBox.value = 0
        NotificationCenter.default.post(name: ShowsShelfLayout.subscriptionsDidChange, object: nil)
        for _ in 0..<50 where step.statusText != nil {
            try? await Task.sleep(for: .milliseconds(10))
        }
        #expect(step.statusText == nil)
    }

    // MARK: - Transcript lesson

    @Test("Transcript lines use clear backgrounds and 0.42 inactive alpha")
    func transcriptLineControlUsesAlphaWithoutBackgroundBox() {
        let control = OnboardingTranscriptLineControl(line: OnboardingSamples.transcript[0])
        #expect(control.backgroundColor == .clear)
        #expect(abs(control.contentAlpha - OnboardingTranscriptLineControl.inactiveAlpha) < 0.001)

        control.isSelected = true
        #expect(control.backgroundColor == .clear)
        #expect(abs(control.contentAlpha - 1) < 0.001)
    }

    @Test("Tapping an answer timestamp pill activates the matching transcript line")
    func transcriptTimestampPillActivatesLine() {
        let step = OnboardingTranscriptStepView(lines: OnboardingSamples.transcript)
        #expect(step.lineCount == 3)
        #expect(step.selectedIndex == 1)
        #expect(step.isLineSelected(at: 1))
        #expect(!step.isLineSelected(at: 0))

        let answerBlock = step.makeAnswerBlockForTesting()
        let pills = collectSubviews(of: OnboardingTimestampPillButton.self, in: answerBlock)
        #expect(pills.count == 3)
        #expect(pills[1].isSelected)
        #expect(!pills[0].isSelected)

        pills[0].sendActions(for: .touchUpInside)
        #expect(step.selectedIndex == 0)
        #expect(step.isLineSelected(at: 0))
        #expect(!step.isLineSelected(at: 1))
        #expect(pills[0].isSelected)
        #expect(!pills[1].isSelected)

        pills[2].sendActions(for: .touchUpInside)
        #expect(step.selectedIndex == 2)
        #expect(step.isLineSelected(at: 2))
        #expect(!step.isLineSelected(at: 0))
    }

    private func collectSubviews<T: UIView>(of type: T.Type, in root: UIView) -> [T] {
        var result: [T] = []
        for subview in root.subviews {
            if let match = subview as? T {
                result.append(match)
            }
            result.append(contentsOf: collectSubviews(of: type, in: subview))
        }
        return result
    }
}
