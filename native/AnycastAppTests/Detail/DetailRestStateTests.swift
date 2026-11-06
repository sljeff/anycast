import UIKit
import Testing
@testable import Anycast

/// What the detail sheet shows before the listener touches it: the top edge
/// effect stays off the header, and at accessibility sizes the Play capsule
/// keeps one line.
@MainActor
struct DetailRestStateTests {

    private func makeDetail(played: Int64?) -> DetailViewController {
        DetailViewController(
            episode: DetailViewController.Episode(
                title: "Reference episode",
                channelTitle: "Reference channel",
                pubDateMilliseconds: 1_700_000_000_000,
                durationMilliseconds: 80 * 60_000,
                playedMilliseconds: played,
                rssFeedURL: "https://example.com/feed.xml",
                enclosureURL: "https://example.com/episode.mp3",
                descriptionHTML: "<p>Notes</p>"
            ),
            actions: [],
            htmlRenderer: HTMLContentRenderer()
        )
    }

    private func layOut(
        _ detail: DetailViewController, in window: UIWindow, category: UIContentSizeCategory
    ) {
        detail.traitOverrides.preferredContentSizeCategory = category
        window.rootViewController = detail
        detail.view.frame = window.bounds
        detail.view.setNeedsLayout()
        detail.view.layoutIfNeeded()
        detail.view.layoutIfNeeded()
    }

    private func subviews<T: UIView>(of type: T.Type, in root: UIView) -> [T] {
        ([root as? T].compactMap { $0 }) + root.subviews.flatMap { subviews(of: type, in: $0) }
    }

    private func playButton(in root: UIView) -> UIButton? {
        subviews(of: UIButton.self, in: root).first { $0.accessibilityIdentifier == "detail-play" }
    }

    @Test("The top edge effect stays off at rest and comes on once scrolled")
    @available(iOS 26.0, *)
    func topEffectOnlyWhenScrolled() throws {
        let detail = makeDetail(played: nil)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 402, height: 874))
        layOut(detail, in: window, category: .large)
        let scroll = try #require(subviews(of: UIScrollView.self, in: detail.view).first)

        #expect(scroll.topEdgeEffect.isHidden)

        scroll.contentOffset.y = 12
        detail.scrollViewDidScroll(scroll)
        #expect(!scroll.topEdgeEffect.isHidden)

        scroll.contentOffset.y = 0
        detail.scrollViewDidScroll(scroll)
        #expect(scroll.topEdgeEffect.isHidden)
    }

    @Test("Compact Play titles are the verb alone")
    func compactTitles() {
        let resume = DetailViewController.PlayLabel.make(
            durationMilliseconds: 80 * 60_000, playedMilliseconds: 48 * 60_000
        )
        #expect(resume.compactTitle == "Resume")
        let fresh = DetailViewController.PlayLabel.make(
            durationMilliseconds: 80 * 60_000, playedMilliseconds: nil
        )
        #expect(fresh.compactTitle == "Play")
    }

    @Test("Accessibility sizes shorten Play, keep its label, and move the time to meta")
    func accessibilityPlayTitle() throws {
        let detail = makeDetail(played: 48 * 60_000)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 402, height: 874))

        layOut(detail, in: window, category: .large)
        var play = try #require(playButton(in: detail.view))
        #expect(play.configuration?.title == "Resume · 32m left")
        let labels = subviews(of: UILabel.self, in: detail.view).compactMap(\.text)
        #expect(!labels.contains { $0 != "Resume · 32m left" && $0.hasSuffix("· 32m left") })

        layOut(detail, in: window, category: .accessibilityLarge)
        play = try #require(playButton(in: detail.view))
        #expect(play.configuration?.title == "Resume")
        #expect(play.accessibilityLabel == "Resume · 32m left")
        let accessibilityLabels = subviews(of: UILabel.self, in: detail.view).compactMap(\.text)
        #expect(accessibilityLabels.contains { $0.hasSuffix("· 32m left") })
    }

    @Test("An unplayed episode adds nothing to meta at accessibility sizes")
    func accessibilityUnplayedMeta() {
        let detail = makeDetail(played: nil)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 402, height: 874))
        layOut(detail, in: window, category: .accessibilityLarge)
        let labels = subviews(of: UILabel.self, in: detail.view).compactMap(\.text)
        #expect(!labels.contains { $0.hasSuffix(" left") })
    }
}
