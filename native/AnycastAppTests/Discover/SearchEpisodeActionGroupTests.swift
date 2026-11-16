import UIKit
import Testing
import AnycastKit
@testable import Anycast

/// The real Search Episodes page over a scripted transport: covered Show
/// cards with the list-owned group, and result reloads that keep or close the
/// group by identity.
@Suite(.serialized)
@MainActor
struct SearchEpisodeActionGroupTests {

    private final class Results: @unchecked Sendable {
        var items: [APIClient.EpisodeWithChannel] = []
    }

    private static func item(_ index: Int) -> APIClient.EpisodeWithChannel {
        let show = SubscriptionRow(rssFeedUrl: "https://example.invalid/show\(index).xml", title: "Show \(index)")
        return APIClient.EpisodeWithChannel(
            episode: FeedEpisodeRow(
                title: "Episode \(index)", duration: 1_800_000,
                enclosureUrl: "https://example.invalid/e\(index).mp3", channelTitle: "Show \(index)",
                rssFeedUrl: show.rssFeedUrl
            ),
            channel: show
        )
    }

    @Test("Body tap toggles the group; a reload keeps it by identity and closes it once the episode is gone")
    func toggleAndReloadKeepsIdentity() async throws {
        let (context, directory) = try await ShowListTestContext.make()
        defer { try? FileManager.default.removeItem(at: directory) }
        let results = Results()
        results.items = (0..<6).map(Self.item)
        let model = SearchPageViewModel(
            searchText: "q", fetchChannels: { _ in [] }, fetchEpisodes: { _ in await MainActor.run { results.items } }
        )
        let page = SearchEpisodesPageViewController(context: context, viewModel: model)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = page
        window.isHidden = false
        page.loadViewIfNeeded()
        defer {
            page.actionController.close(animated: false)
            window.isHidden = true
            window.rootViewController = nil
        }
        let collection = try #require(page.edgeScrollView as? ListActionCollectionView)
        model.search()
        try await settle(window, collection) { page.displayedEpisodes.count == 6 }

        func card(_ index: Int) throws -> EpisodeCardCell {
            try #require(collection.cellForItem(at: IndexPath(item: index, section: 0)) as? EpisodeCardCell)
        }
        let id = "https://example.invalid/e2.mp3"
        let body = try card(2).cardFrameInCell.height
        #expect(abs(body - EpisodeCardCell.showRowHeight) <= 0.5)
        // The search card names its show in the meta row.
        #expect(ChannelActionGroupTests.descendants(try card(2)).contains {
            ($0 as? UILabel)?.text == "Show 2" && !$0.isHidden
        })
        try card(2).onCardTap?()
        try await settle(window, collection)
        #expect(page.actionController.selectedID == id)
        #expect(page.actionController.groupView.circles.map(\.actionID) == ["play", "add", "details"])
        #expect(try card(2).actionGap == 68)

        // A reload that moves the episode keeps the group on it.
        results.items = [Self.item(9), Self.item(2), Self.item(0), Self.item(4)]
        model.retry(tab: 1)
        try await settle(window, collection) { page.displayedEpisodes.count == 4 }
        #expect(page.actionController.selectedID == id, "reload dropped the open group")
        #expect(!page.actionController.groupView.isHidden)
        let moved = try card(1)
        #expect(moved.actionGap == 68)
        #expect(abs(moved.cardFrameInCell.height - body) <= 0.5)
        #expect(abs(page.actionController.groupView.frame.minY - moved.frame.minY - moved.cardFrameInCell.maxY - 12) <= 0.5)
        #expect(try card(0).actionGap == 0)

        // A reload without it closes the group.
        results.items = [Self.item(7), Self.item(8)]
        model.retry(tab: 1)
        try await settle(window, collection) { page.displayedEpisodes.count == 2 }
        #expect(page.actionController.selectedID == nil)
        #expect(page.actionController.groupView.isHidden)
        #expect(try card(0).actionGap == 0 && card(1).actionGap == 0)

        // Body tap again closes on the second tap.
        try card(1).onCardTap?()
        try await settle(window, collection)
        #expect(page.actionController.selectedID == "https://example.invalid/e8.mp3")
        try card(1).onCardTap?()
        try await settle(window, collection)
        #expect(page.actionController.selectedID == nil)
    }

    private func settle(
        _ window: UIWindow, _ collection: UICollectionView, until condition: () -> Bool = { true }
    ) async throws {
        for _ in 0..<40 where !condition() {
            try await Task.sleep(for: .milliseconds(50))
        }
        try await Task.sleep(for: .milliseconds(450))
        window.layoutIfNeeded()
        collection.layoutIfNeeded()
    }
}
