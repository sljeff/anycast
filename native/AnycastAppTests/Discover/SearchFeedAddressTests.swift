import Foundation
import UIKit
import Testing
import AnycastKit
@testable import Anycast

/// A pasted feed address in Search: which text counts as an address, and
/// what the one-row page shows while loading, when the feed is read, when it
/// is not a feed, and when Follow is tapped.
@MainActor
struct SearchFeedAddressTests {

    // MARK: - Detecting an address

    @Test("Web addresses are fed, not searched; names and half addresses are searched")
    func detection() {
        #expect(FeedAddress.parse("https://feeds.npr.org/510289/podcast.xml") == "https://feeds.npr.org/510289/podcast.xml")
        #expect(FeedAddress.parse("  http://example.com/feed  ") == "http://example.com/feed")
        #expect(FeedAddress.parse("HTTPS://Example.com/Feed") == "HTTPS://Example.com/Feed")
        #expect(FeedAddress.parse("feed://example.com/rss") == "http://example.com/rss")
        #expect(FeedAddress.parse("itpc://example.com/rss") == "http://example.com/rss")
        #expect(FeedAddress.parse("pcast://example.com/rss") == "http://example.com/rss")

        #expect(FeedAddress.parse("planet money") == nil)
        #expect(FeedAddress.parse("feeds.npr.org/510289") == nil, "no scheme: a search")
        #expect(FeedAddress.parse("https://") == nil)
        #expect(FeedAddress.parse("https://exa mple.com") == nil, "spaces: a search")
        #expect(FeedAddress.parse("ftp://example.com/f") == nil)
        #expect(FeedAddress.parse("") == nil)
    }

    @Test("The hint line promises names and addresses")
    func hint() {
        #expect(SearchEntryViewController.hintText == "Search by name, or paste a feed address.")
        #expect(SearchFeedAddressViewController.notAFeedText == "That address isn\u{2019}t a podcast feed.")
        #expect(FeedAddress.host(of: "https://feeds.npr.org/510289/podcast.xml") == "feeds.npr.org")
    }

    // MARK: - The page

    private func podcast(_ url: String, title: String) -> PodcastImportData {
        PodcastImportData(
            subscription: SubscriptionRow(rssFeedUrl: url, title: title, description: "d"),
            feedEpisodes: []
        )
    }

    private func settle(_ page: SearchFeedAddressViewController) async {
        for _ in 0..<100 where page.phase == .loading {
            try? await Task.sleep(for: .milliseconds(20))
        }
    }

    @Test("Loading, then one row for the feed; Follow subscribes once")
    func loadsAndFollows() async {
        let address = "https://feeds.example.com/show.xml"
        let feed = podcast(address, title: "The Show")
        let calls = CallLog()
        let page = SearchFeedAddressViewController(
            context: nil,
            fetch: { _ in
                try? await Task.sleep(for: .milliseconds(100))
                return feed
            },
            followed: { [] },
            subscribe: { data in
                calls.record(data.subscription.title ?? "")
                return true
            }
        )
        page.loadViewIfNeeded()
        page.load(address: address)
        #expect(page.phase == .loading, "a skeleton row while the feed is read")

        await settle(page)
        #expect(page.phase == .loaded(feed))
        #expect(!page.isFollowing)

        let follow = Self.button("search-feed-follow", in: page.view)
        #expect(follow?.configuration?.title == "Follow")
        follow?.sendActions(for: .touchUpInside)
        #expect(page.isFollowing)
        #expect(follow?.configuration?.title == "Following")
        follow?.sendActions(for: .touchUpInside)
        try? await Task.sleep(for: .milliseconds(50))
        #expect(calls.entries == ["The Show"], "a second tap does not subscribe again")
    }

    @Test("A followed show reads Following, matched by feed address")
    func alreadyFollowing() async {
        let page = SearchFeedAddressViewController(
            context: nil,
            fetch: { address in
                PodcastImportData(
                    subscription: SubscriptionRow(rssFeedUrl: address, title: "The Show"), feedEpisodes: []
                )
            },
            followed: { ["https://FEEDS.example.com/show.xml/"] },
            subscribe: { _ in true }
        )
        page.loadViewIfNeeded()
        page.load(address: "https://feeds.example.com/show.xml")
        await settle(page)
        #expect(page.isFollowing)
        #expect(Self.button("search-feed-follow", in: page.view)?.configuration?.title == "Following")
    }

    @Test("Not a feed: one line, no row")
    func notAFeed() async {
        let page = SearchFeedAddressViewController(
            context: nil, fetch: { _ in nil }, followed: { [] }, subscribe: { _ in true }
        )
        page.loadViewIfNeeded()
        page.load(address: "https://example.com/not-a-feed")
        await settle(page)
        #expect(page.phase == .notAFeed)
        let message = Self.label("search-feed-message", in: page.view)
        #expect(message?.text == "That address isn\u{2019}t a podcast feed.")
        #expect(message?.isHidden == false)
    }

    @Test("A write that fails puts the button back")
    func followFailure() async {
        let page = SearchFeedAddressViewController(
            context: nil,
            fetch: { address in
                PodcastImportData(
                    subscription: SubscriptionRow(rssFeedUrl: address, title: "The Show"), feedEpisodes: []
                )
            },
            followed: { [] },
            subscribe: { _ in false }
        )
        page.loadViewIfNeeded()
        page.load(address: "https://feeds.example.com/show.xml")
        await settle(page)
        Self.button("search-feed-follow", in: page.view)?.sendActions(for: .touchUpInside)
        try? await Task.sleep(for: .milliseconds(100))
        #expect(!page.isFollowing)
        #expect(Self.button("search-feed-follow", in: page.view)?.configuration?.title == "Follow")
    }

    // MARK: - Helpers

    private final class CallLog: @unchecked Sendable {
        private let lock = NSLock()
        private var stored: [String] = []
        func record(_ value: String) { lock.lock(); stored.append(value); lock.unlock() }
        var entries: [String] { lock.lock(); defer { lock.unlock() }; return stored }
    }

    private static func button(_ identifier: String, in view: UIView) -> UIButton? {
        if let button = view as? UIButton, button.accessibilityIdentifier == identifier { return button }
        for subview in view.subviews {
            if let found = button(identifier, in: subview) { return found }
        }
        return nil
    }

    private static func label(_ identifier: String, in view: UIView) -> UILabel? {
        if let label = view as? UILabel, label.accessibilityIdentifier == identifier { return label }
        for subview in view.subviews {
            if let found = label(identifier, in: subview) { return found }
        }
        return nil
    }
}
