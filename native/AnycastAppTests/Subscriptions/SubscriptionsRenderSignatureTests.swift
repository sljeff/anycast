import Testing
import AnycastKit
@testable import Anycast

/// The subscriptions reload gate must be metadata-aware: an inbox refresh
/// INSERT-OR-REPLACEs existing rows in place (same URL list, new
/// title/description/cover/lastUpdated). A URL-only signature would skip
/// the reload and keep stale cards on screen.
@MainActor
struct SubscriptionsRenderSignatureTests {

    @Test("in-place metadata rewrite changes the signature")
    func metadataRewriteChangesSignature() {
        let url = "https://example.com/feed.xml"
        let before = SubscriptionRow(rssFeedUrl: url, title: "Old Title", imageUrl: "https://cdn/old.jpg")
        var after = before
        after.title = "New Title"
        after.imageUrl = "https://cdn/new.jpg"
        after.lastUpdated = 1_700_000_000_000

        let beforeSignature = SubscriptionsPageViewController.renderSignature([before])
        let afterSignature = SubscriptionsPageViewController.renderSignature([after])

        #expect(beforeSignature == SubscriptionsPageViewController.renderSignature([before]),
                "identical rows must produce identical signatures")
        #expect(beforeSignature != afterSignature,
                "a metadata rewrite must produce a different signature")
    }

    @Test("adding or removing a feed changes the signature")
    func membershipChangeChangesSignature() {
        let a = SubscriptionRow(rssFeedUrl: "https://a.example/f", title: "A")
        let b = SubscriptionRow(rssFeedUrl: "https://b.example/f", title: "B")

        let one = SubscriptionsPageViewController.renderSignature([a])
        let two = SubscriptionsPageViewController.renderSignature([a, b])

        #expect(one != two)
    }
}
