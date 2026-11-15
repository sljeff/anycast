import Foundation
import UIKit
import Testing
@testable import Anycast

/// Empty-state copy: each reason for an empty page has its own words, with
/// curly apostrophes and quotes, and no title weight or icon.
@MainActor
struct EmptyStateCopyTests {

    @Test("Inbox: no subscriptions, caught up (1 show / N shows), and a filtered category")
    func inboxCopy() {
        let none = InboxEmptyStateView.copy(for: .noSubscriptions)
        #expect(none.title == "New episodes from shows you follow land here.")
        #expect(none.message == "Anycast can transcribe and translate them.")
        let two = InboxEmptyStateView.copy(for: .caughtUp(showCount: 2))
        #expect(two.title == "All caught up.")
        #expect(two.message == "New episodes from your 2 shows land here.")
        #expect(InboxEmptyStateView.copy(for: .caughtUp(showCount: 1)).message == "New episodes from your 1 show land here.")
        let filtered = InboxEmptyStateView.copy(for: .filtered(category: "Technology"))
        #expect(filtered.title == "No episodes in Technology.")
        #expect(filtered.message == nil)
    }

    @Test("Inbox empty state: Find a show + import link only when nothing is followed; Show all when filtered")
    func inboxActions() {
        func buttonTitles(_ view: InboxEmptyStateView) -> [String] {
            view.frame = CGRect(x: 0, y: 0, width: 393, height: 700)
            view.layoutIfNeeded()
            return Self.allViews(in: view).compactMap { ($0 as? UIButton)?.configuration?.title }
        }
        let none = InboxEmptyStateView()
        none.show(.noSubscriptions)
        #expect(buttonTitles(none) == ["Find a show", "Import from another app"])
        let caughtUp = InboxEmptyStateView()
        caughtUp.show(.caughtUp(showCount: 2))
        #expect(buttonTitles(caughtUp).isEmpty)
        let filtered = InboxEmptyStateView()
        filtered.show(.filtered(category: "News"))
        #expect(buttonTitles(filtered) == ["Show all"])
    }

    @Test("Channel in-show search: curly quotes around the query")
    func channelSearchCopy() {
        #expect(ChannelSearchViewController.noResultsText(for: "x") == "No episodes for \u{201C}x\u{201D}")
        #expect(ChannelSearchViewController.noResultsText(for: "  ") == "No episodes.")
    }

    private static func allViews(in view: UIView) -> [UIView] {
        [view] + view.subviews.flatMap { allViews(in: $0) }
    }
}
