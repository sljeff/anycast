import UIKit
import Testing
import AnycastKit
@testable import Anycast

/// Channel page pure logic: fold interpolation (05 §6.3 P1 checklist),
/// OrderChooser mapping, subscription tristate, the channel-page
/// inPlaylist guard, search filter, playlist insertion semantics, and the
/// K34 session store (hit / miss / invalidation).
@MainActor
struct ChannelLogicTests {

    // MARK: - Fold geometry (channel.dart:248-541)

    private func makeGeometry(safeTop: CGFloat = 59) -> ChannelFoldGeometry {
        ChannelFoldGeometry(safeAreaTop: safeTop)
    }

    @Test("Extents: min = safe top + 148, max = safe top + 460, any window")
    func extents() {
        let geo = makeGeometry(safeTop: 59)
        #expect(geo.minExtent == 207)
        #expect(geo.maxExtent == 519)
        #expect(geo.maxShrink == 312)

        // A different window/safe area moves both extents equally.
        let taller = makeGeometry(safeTop: 0)
        #expect(taller.minExtent == 148)
        #expect(taller.maxExtent == 460)
    }

    @Test("Fold at shrink 0: fully expanded")
    func foldAtZero() {
        let geo = makeGeometry()
        #expect(geo.headerHeight(shrink: 0) == geo.maxExtent)
        #expect(geo.coverSize(shrink: 0) == 120)
        #expect(geo.titleLeadingPadding(shrink: 0) == 0)
        #expect(geo.secondaryOpacity(shrink: 0) == 1)
        #expect(geo.contentRise(shrink: 0) == 0)
        // Centered cover in a 320pt padded container.
        #expect(geo.coverLeading(shrink: 0, paddedWidth: 320) == 320.0 / 2 - 60)
    }

    @Test("Fold at maxExtent/4: secondary block exactly invisible")
    func foldAtQuarter() {
        let geo = makeGeometry()
        let quarter = geo.maxExtent / 4
        #expect(geo.secondaryOpacity(shrink: quarter) == 0)
        // Beyond the quarter it stays clamped at 0.
        #expect(geo.secondaryOpacity(shrink: quarter + 100) == 0)
        // The two spacers are fully collapsed by then (120 + 12 rise).
        #expect(geo.contentRise(shrink: quarter) == 132)
    }

    @Test("Fold at maxShrink: fully collapsed")
    func foldAtMax() {
        let geo = makeGeometry()
        let s = geo.maxShrink
        #expect(geo.headerHeight(shrink: s) == geo.minExtent)
        #expect(geo.coverSize(shrink: s) == 60)
        #expect(geo.coverLeading(shrink: s, paddedWidth: 320) == 16)
        #expect(geo.titleLeadingPadding(shrink: s) == 84)   // min(60 + 24, s)
        #expect(geo.secondaryOpacity(shrink: s) == 0)
        #expect(geo.contentRise(shrink: s) == 132)
    }

    @Test("Fold clamps negative (bounce) and overshooting offsets")
    func foldClamping() {
        let geo = makeGeometry()
        #expect(geo.headerHeight(shrink: -50) == geo.maxExtent)
        #expect(geo.coverSize(shrink: -50) == 120)
        #expect(geo.headerHeight(shrink: geo.maxShrink + 1000) == geo.minExtent)
        #expect(geo.coverSize(shrink: geo.maxShrink + 1000) == 60)
        #expect(geo.coverLeading(shrink: geo.maxShrink + 1000, paddedWidth: 320) == 16)
    }

    @Test("Mid-fold cover motion is linear toward 16/60")
    func foldMidpoint() {
        let geo = makeGeometry()
        let paddedWidth: CGFloat = 320
        let initial = paddedWidth / 2 - 60
        // Shrink of 40 moves the cover left by 40 and shrinks it by 40.
        #expect(geo.coverSize(shrink: 40) == 80)
        #expect(geo.coverLeading(shrink: 40, paddedWidth: paddedWidth) == initial - 40)
        // Title padding rides along until the 84 cap.
        #expect(geo.titleLeadingPadding(shrink: 40) == 40)
        #expect(geo.titleLeadingPadding(shrink: 90) == 84)
    }

    @Test("Gradient top color: dominant at 30% over 0xFF111316")
    func gradientBlend() {
        #expect(ChannelFoldGeometry.gradientTopColor(rgb: 0x86_7D_75) == 0x34_32_32)
        // Blending the background over itself is a no-op.
        #expect(ChannelFoldGeometry.gradientTopColor(rgb: 0x11_13_16) == 0x11_13_16)
        // Pure white dominates at 30%.
        #expect(ChannelFoldGeometry.gradientTopColor(rgb: 0xFF_FF_FF) == 0x58_59_5B)
    }

    // MARK: - OrderChooser (channel.dart:199-246 / 71-92)

    @Test("Newest/Oldest selection maps to isReversed and back")
    func orderMapping() {
        #expect(!ChannelOrderMapping.isReversed(selectedIndex: 0))
        #expect(ChannelOrderMapping.isReversed(selectedIndex: 1))
        #expect(ChannelOrderMapping.selectedIndex(isReversed: false) == 0)
        #expect(ChannelOrderMapping.selectedIndex(isReversed: true) == 1)
    }

    @Test("showEpisodes: Newest keeps order, Oldest reverses")
    func showEpisodesOrdering() {
        let episodes = [
            FeedEpisodeRow(enclosureUrl: "a"),
            FeedEpisodeRow(enclosureUrl: "b"),
            FeedEpisodeRow(enclosureUrl: "c"),
        ]
        #expect(ChannelOrderMapping.showEpisodes(episodes, isReversed: false).map(\.enclosureUrl) == ["a", "b", "c"])
        #expect(ChannelOrderMapping.showEpisodes(episodes, isReversed: true).map(\.enclosureUrl) == ["c", "b", "a"])
    }

    // MARK: - Subscription tristate (channel.dart:558-592)

    @Test("Subscription display tristate reducer")
    func subscriptionDisplay() {
        // Loading ONLY while the local exists-check is unsettled or the
        // title is unknown — an in-flight feed fetch (the old isLoading
        // gate) must NOT keep the capsule spinning.
        #expect(ChannelSubscriptionDisplay.display(subscribed: false, subscriptionChecked: false, hasTitle: true) == .loading)
        #expect(ChannelSubscriptionDisplay.display(subscribed: true, subscriptionChecked: false, hasTitle: true) == .loading)
        #expect(ChannelSubscriptionDisplay.display(subscribed: false, subscriptionChecked: true, hasTitle: false) == .loading)
        #expect(ChannelSubscriptionDisplay.display(subscribed: true, subscriptionChecked: true, hasTitle: false) == .loading)
        // Settled states.
        #expect(ChannelSubscriptionDisplay.display(subscribed: false, subscriptionChecked: true, hasTitle: true) == .subscribe)
        #expect(ChannelSubscriptionDisplay.display(subscribed: true, subscriptionChecked: true, hasTitle: true) == .unsubscribe)
    }

    // MARK: - inPlaylist guard (channel.dart:152-155 / 831-834)

    @Test("Channel-page add gate: check icon and no-op when already in a playlist")
    func playlistGate() {
        #expect(ChannelPlaylistGate.action(inPlaylist: true) == .blocked)
        #expect(ChannelPlaylistGate.action(inPlaylist: false) == .flyInAndInsert)
    }

    // MARK: - Channel search filter (channel.dart:781-785)

    @Test("In-channel filter: case-insensitive contains over titles")
    func searchFilter() {
        let episodes = [
            FeedEpisodeRow(title: "Deep Work", enclosureUrl: "a"),
            FeedEpisodeRow(title: "deep dive", enclosureUrl: "b"),
            FeedEpisodeRow(title: nil, enclosureUrl: "c"),   // K4: nil title never crashes
            FeedEpisodeRow(title: "Unrelated", enclosureUrl: "d"),
        ]
        let filtered = ChannelSearchFilter.apply("deep", to: episodes)
        #expect(filtered.map(\.enclosureUrl) == ["a", "b"])

        // Empty needle matches everything (contains("")); nil-title rows
        // participate as "".
        #expect(ChannelSearchFilter.apply("", to: episodes).count == 4)
        #expect(ChannelSearchFilter.apply("work", to: episodes).map(\.enclosureUrl) == ["a"])
    }

    // MARK: - Playlist insertion semantics (states/feed_episode.dart:80-105)

    @Test("addToPlaylistIndex: current-playlist special cases")
    func addToPlaylistIndex() {
        let target: Int64 = ChannelPlaylistLogic.defaultPlaylistID
        // Not the current playlist → top.
        #expect(ChannelPlaylistLogic.addToPlaylistIndex(
            currentPlaylistId: nil, targetPlaylistId: target,
            currentEnclosureURL: "x", episodeEnclosureURL: "y") == 0)
        #expect(ChannelPlaylistLogic.addToPlaylistIndex(
            currentPlaylistId: 7, targetPlaylistId: target,
            currentEnclosureURL: "x", episodeEnclosureURL: "y") == 0)
        // Current playlist, different episode → below the head (index 1).
        #expect(ChannelPlaylistLogic.addToPlaylistIndex(
            currentPlaylistId: target, targetPlaylistId: target,
            currentEnclosureURL: "x", episodeEnclosureURL: "y") == 1)
        // The current episode itself → no-op.
        #expect(ChannelPlaylistLogic.addToPlaylistIndex(
            currentPlaylistId: target, targetPlaylistId: target,
            currentEnclosureURL: "same", episodeEnclosureURL: "same") == nil)
        // Nil current enclosure behaves as "not the current episode".
        #expect(ChannelPlaylistLogic.addToPlaylistIndex(
            currentPlaylistId: target, targetPlaylistId: target,
            currentEnclosureURL: nil, episodeEnclosureURL: "y") == 1)
    }

    @Test("feed2playlist maps every field with the default playlist id")
    func playlistRowMapping() {
        let episode = FeedEpisodeRow(
            title: "t", description: "d", duration: 1000, enclosureUrl: "e",
            pubDate: 123, imageUrl: "i", channelTitle: "c", rssFeedUrl: "r"
        )
        let row = ChannelPlaylistLogic.playlistRow(from: episode, playlistId: 1)
        #expect(row.title == "t")
        #expect(row.description == "d")
        #expect(row.duration == 1000)
        #expect(row.enclosureUrl == "e")
        #expect(row.pubDate == 123)
        #expect(row.imageUrl == "i")
        #expect(row.channelTitle == "c")
        #expect(row.rssFeedUrl == "r")
        #expect(row.playlistId == 1)
    }

    // MARK: - K34 session store (same-session reuse without refetch)

    @Test("K34: hit/miss/invalidation over the rssFeedURL key")
    func sessionStoreReuse() async throws {
        // A throwaway database backs the repositories the view models hold.
        let database = try await AppDatabase.openAt(
            URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent("channel-store-\(UUID().uuidString).sqlite3")
        )
        let urlA = "https://example.com/a.rss"
        let urlB = "https://example.com/b.rss"
        var created = 0
        let store = ChannelSessionStore(factory: { url, seed in
            created += 1
            return ChannelViewModel(
                rssFeedURL: url,
                seed: seed ?? SubscriptionRow(rssFeedUrl: url, title: "S\(created)"),
                fetcher: RSSFetcher(client: HTTPClient(), userAgent: "test"),
                subscriptions: database.subscriptionRepository(),
                feeds: database.feedRepository(),
                palette: PaletteService.shared
            )
        })

        // Miss → creates (isNew — the caller drives prepare()).
        let first = store.entry(rssFeedURL: urlA)
        #expect(first.isNew)
        #expect(created == 1)

        // Hit → same instance, NOT new: no refetch on same-session reopen,
        // even with a different seed (the cache wins).
        let second = store.entry(rssFeedURL: urlA, seed: SubscriptionRow(rssFeedUrl: urlA, title: "other"))
        #expect(!second.isNew)
        #expect(second.model === first.model)
        #expect(created == 1)

        // A different URL is a separate entry.
        let other = store.entry(rssFeedURL: urlB)
        #expect(other.isNew)
        #expect(other.model !== first.model)
        #expect(created == 2)

        // Invalidation: after removal the next entry is a fresh model.
        store.remove(rssFeedURL: urlA)
        let third = store.entry(rssFeedURL: urlA)
        #expect(third.isNew)
        #expect(third.model !== first.model)
        #expect(created == 3)
    }
}
