import UIKit
import Testing
import AnycastKit
@testable import Anycast

/// The V2 shell pieces (09 §10 V2): the header component, the category
/// projection, the mini player capsule chrome, and the subscriptions status
/// line. Color values are asserted with an explicit dark resolution
/// (09 §9a).
@MainActor
struct V2ShellTests {

    private let dark = UITraitCollection(userInterfaceStyle: .dark)

    // MARK: - HeaderView (09 §3.8, Figma 624:30831)

    @Test("Header paints the display title, status, search field, and settings action")
    func headerBasics() {
        let header = HeaderView()
        header.configure(HeaderView.Configuration(
            title: "Podcast", statusText: "updated just now - 100 unlistened"
        ))
        header.frame = CGRect(x: 0, y: 0, width: 440, height: 160)
        header.layoutIfNeeded()

        let title = header.subviews.compactMap { $0 as? UIStackView }.first?
            .arrangedSubviews.compactMap { $0 as? UILabel }
            .first { $0.accessibilityIdentifier == "header-title" }
        #expect(title?.text == "Podcast")
        #expect(title?.font.pointSize == 48)

        let status = header.subviews.compactMap { $0 as? UIStackView }.first?
            .arrangedSubviews.compactMap { $0 as? UILabel }
            .first { $0.accessibilityIdentifier == "header-status" }
        #expect(status?.text == "updated just now - 100 unlistened")
        #expect(status?.isHidden == false)
        #expect(
            status?.textColor.resolvedColor(with: dark)
                == AnycastColor.sand9.resolvedColor(with: dark),
            "status caption paints sand9"
        )

        let search = header.subviews.compactMap { $0 as? UITextField }
            .first { $0.accessibilityIdentifier == "header-search-field" }
        let settings = header.subviews.compactMap { $0 as? GlassContainerView }
            .flatMap { $0.glassContentView.subviews.compactMap { $0 as? UIButton } }
            .first { $0.accessibilityIdentifier == "header-settings" }
        #expect(search?.accessibilityLabel == "Search")
        #expect(search?.placeholder == "Shows, episodes, and more")
        #expect(settings?.accessibilityIdentifier == "header-settings")
        #expect(settings?.isHidden == false)

        var submittedQuery: String?
        var settingsTaps = 0
        header.onSearch = { submittedQuery = $0 }
        header.onSettings = { settingsTaps += 1 }
        search?.text = "  news  "
        if let search { _ = header.textFieldShouldReturn(search) }
        settings?.sendActions(for: .touchUpInside)
        #expect(submittedQuery == "news")
        #expect(settingsTaps == 1)
    }

    @Test("Header scales for accessibility text and keeps actions clear")
    func headerDynamicTypeLayout() {
        let header = HeaderView()
        header.traitOverrides.preferredContentSizeCategory = .accessibilityExtraExtraExtraLarge
        header.configure(HeaderView.Configuration(title: "Discover", statusText: "Updated just now"))
        header.frame = CGRect(x: 0, y: 0, width: 393, height: 180)
        header.layoutIfNeeded()

        let title = header.subviews.compactMap { $0 as? UIStackView }.first?
            .arrangedSubviews.compactMap { $0 as? UILabel }
            .first { $0.accessibilityIdentifier == "header-title" }
        let titleColumn = title?.superview
        let actions = header.subviews.compactMap { $0 as? GlassContainerView }.first
        let titleRight = titleColumn?.frame.maxX ?? .infinity
        let actionLeft = actions?.frame.minX ?? 0

        #expect((title?.font.pointSize ?? 0) > 48)
        #expect(titleRight <= actionLeft)
    }

    @Test("A nil status collapses the caption; settings can hide")
    func headerCollapses() {
        let header = HeaderView()
        header.configure(HeaderView.Configuration(title: "queue", statusText: nil, showsSettings: false))
        header.frame = CGRect(x: 0, y: 0, width: 440, height: 120)
        header.layoutIfNeeded()

        let status = header.subviews.compactMap { $0 as? UIStackView }.first?
            .arrangedSubviews.compactMap { $0 as? UILabel }
            .first { $0.accessibilityIdentifier == "header-status" }
        #expect(status?.isHidden == true)
        let search = header.subviews.compactMap { $0 as? UITextField }
            .first { $0.accessibilityIdentifier == "header-search-field" }
        let settings = header.subviews.compactMap { $0 as? GlassContainerView }.first
        #expect(search?.isHidden == false)
        #expect(settings?.isHidden == true)
    }

    // MARK: - Inbox category projection (09 §3.2)

    private func episode(_ url: String, feed: String?) -> FeedEpisodeRow {
        var row = FeedEpisodeRow(enclosureUrl: url)
        row.rssFeedUrl = feed
        return row
    }

    @Test("Category map splits, trims, and lowercases; filtering is case-insensitive")
    func categoryProjection() {
        let subscriptions = [
            SubscriptionRow(rssFeedUrl: "https://a.example/feed", categories: " Technology, business "),
            SubscriptionRow(rssFeedUrl: "https://b.example/feed", categories: "arts"),
            SubscriptionRow(rssFeedUrl: "https://c.example/feed", categories: nil),
        ]
        let map = InboxCategoryFilter.categoriesByFeed(from: subscriptions)
        #expect(map["https://a.example/feed"] == ["technology", "business"])
        #expect(map["https://b.example/feed"] == ["arts"])
        #expect(map["https://c.example/feed"] == nil)

        let episodes = [
            episode("e1", feed: "https://a.example/feed"),
            episode("e2", feed: "https://b.example/feed"),
            episode("e3", feed: nil),
        ]
        #expect(InboxCategoryFilter.displayed(episodes: episodes, selected: nil, categoriesByFeed: map).count == 3)
        #expect(
            InboxCategoryFilter.displayed(episodes: episodes, selected: "TECHNOLOGY", categoriesByFeed: map)
                .map(\.enclosureUrl) == ["e1"],
            "selected filter keeps only matching feeds, case-insensitively"
        )
        #expect(
            InboxCategoryFilter.displayed(episodes: episodes, selected: "missing", categoriesByFeed: map).isEmpty
        )
    }

    // MARK: - Inbox status line (09 §3.8)

    @Test("Inbox status line formats refresh time and unlistened count")
    func inboxStatusText() {
        let now = Date()
        let justNow = now.addingTimeInterval(-5)
        let text = InboxPageViewController.headerStatusText(
            lastRefresh: justNow, episodeCount: 12, now: now
        )
        #expect(text == "updated just now - 12 unlistened", "got: \(text)")

        let never = InboxPageViewController.headerStatusText(lastRefresh: nil, episodeCount: 0, now: now)
        #expect(never == "updated — - 0 unlistened", "got: \(never)")
    }

    // MARK: - Library status line (09 §3.3)

    @Test("Subscriptions status pluralizes the show count")
    func subscriptionsStatusText() {
        #expect(LibraryViewController.statusText(showCount: 0) == "0 shows")
        #expect(LibraryViewController.statusText(showCount: 1) == "1 show")
        #expect(LibraryViewController.statusText(showCount: 7) == "7 shows")
    }

    // MARK: - Mini player capsule chrome (09 §3.6 state c, Figma 83:2562)

    @Test("Capsule mini player paints the v2 chrome and drops the time label")
    func capsuleChrome() async {
        guard let context = await Self.liveUIContext() else {
            print("[v2shell] shell not ready; skipping capsule test"); return
        }
        let bar = context.makePlayerBar(style: .capsule)
        bar.frame = CGRect(x: 0, y: 0, width: 408, height: PlayerBarView.barHeight)
        bar.layoutIfNeeded()

        let capsule = bar.subviews.first { $0 !== bar } ?? bar.subviews.first
        // The v2 chrome family is the STATIC white-80 literal (09 §3.6 +
        // patch-round 3: the dark design frame renders the capsule bright).
        #expect(capsule?.backgroundColor == UIColor(white: 1, alpha: 0.8))
        #expect(capsule?.layer.borderWidth == 1)
        #expect(capsule?.layer.shadowOpacity == 0.05)
        #expect(capsule?.layer.cornerRadius == PlayerBarView.barHeight / 2, "full capsule silhouette")

        let labels = (capsule?.subviews.compactMap { $0 as? UILabel } ?? [])
            .filter { !$0.isHidden }
        #expect(labels.count == 1, "capsule carries only the title label (time label hidden)")
        #expect(labels.first?.accessibilityIdentifier == "mini-player-title")
    }

    // MARK: - Welcome / SignUp smoke (V2 scope: UI lands, auth stays TODO)

    @Test("Welcome and SignUp expose their entry identifiers")
    func authScreensSmoke() async {
        guard let context = await Self.liveUIContext() else {
            print("[v2shell] shell not ready; skipping auth smoke"); return
        }
        let welcome = WelcomeViewController(context: context)
        welcome.loadViewIfNeeded()
        #expect(welcome.view.subviews.contains { $0 is UIStackView })
        #expect(welcome.view.backgroundColor == Theme.background)

        let signUp = SignUpViewController(context: context)
        signUp.loadViewIfNeeded()
        let identifiers = signUp.view.recursiveAccessibilityIdentifiers()
        #expect(identifiers.contains("signup-back"))
        #expect(identifiers.contains("signup-submit"))
        #expect(identifiers.contains("signup-wordmark"))
    }

    // MARK: - Helpers

    @MainActor
    private static func liveUIContext() async -> UIContext? {
        for _ in 0..<40 {
            if let context = (UIApplication.shared.delegate as? AppDelegate)?.environment.uiContext {
                return context
            }
            try? await Task.sleep(for: .milliseconds(500))
        }
        return nil
    }
}

private extension UIView {
    func recursiveAccessibilityIdentifiers() -> [String] {
        var found = accessibilityIdentifier.map { [$0] } ?? []
        for subview in subviews {
            found.append(contentsOf: subview.recursiveAccessibilityIdentifiers())
        }
        return found
    }
}
