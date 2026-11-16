import UIKit
import Testing
import AnycastKit
@testable import Anycast

/// The real Channel page with a private SQLite memory database and a feed
/// installed without the network: covered Show cards and the list-owned
/// Play · Add · Details group.
@Suite(.serialized)
@MainActor
struct ChannelActionGroupTests {

    @Test("Body tap opens Play · Add · Details under a 68 pt gap; a second tap closes it")
    func bodyTapTogglesGroup() async throws {
        let host = try await ChannelHost.make(count: 10)
        defer { host.close() }
        let cell = try host.card(0)
        let body = cell.cardFrameInCell.height
        cell.onCardTap?()
        try await host.settle()
        #expect(host.controller.selectedID == host.url(0))
        #expect(cell.actionGap == 68)
        #expect(abs(cell.bounds.height - body - 68) <= 0.5)
        #expect(host.group.circles.map(\.actionID) == ["play", "add", "details"])
        #expect(abs(host.group.frame.minY - cell.frame.minY - cell.cardFrameInCell.maxY - 12) <= 0.5)
        #expect(host.collection.visibleCells.allSatisfy { $0.layer.zPosition > host.group.layer.zPosition })

        cell.onCardTap?()
        try await host.settle()
        #expect(host.controller.selectedID == nil && host.group.isHidden)
        #expect(cell.actionGap == 0)
        #expect(abs(cell.bounds.height - body) <= 0.5)
    }

    @Test("The order row has no action identity and Show cards are the fixed Show composition")
    func headerRowAndCardGeometry() async throws {
        let host = try await ChannelHost.make(count: 4)
        defer { host.close() }
        let header = try #require(host.collection.cellForItem(at: IndexPath(item: 0, section: 0)) as? ChannelBodyHeaderCell)
        let first = try host.card(0)
        #expect(abs(first.cardFrameInCell.height - EpisodeCardCell.showRowHeight) <= 0.5)
        // The order row keeps its 44 pt row plus the 12 pt card gap.
        #expect(abs(first.frame.minY - header.frame.minY - ChannelBodyHeaderCell.fixedHeight) <= 0.5)
    }

    @Test("Cover tap opens Detail and leaves the group closed")
    func coverTapOpensDetail() async throws {
        let host = try await ChannelHost.make(count: 4)
        defer { host.close() }
        try host.card(1).onCoverTap?()
        try await host.settle()
        #expect(host.controller.selectedID == nil)
        #expect(Self.find(DetailViewController.self, from: host.channel) != nil, "cover tap did not open Detail")
        host.channel.dismiss(animated: false)
    }

    @Test("Add swaps the circle to the added state and shows the chip in place; height and group unchanged")
    func addSwapsStateInPlace() async throws {
        let host = try await ChannelHost.make(count: 6, inPlaylist: [3])
        defer { host.close() }
        let cell = try host.card(1)
        let body = cell.cardFrameInCell.height
        #expect(Self.chip(in: cell)?.isHidden == true)
        cell.onCardTap?()
        try await host.settle()
        let add = try #require(host.group.button(for: "add"))
        #expect(add.accessibilityLabel == "Add to playlist")

        add.sendActions(for: .touchUpInside)
        try await host.waitFor { host.group.button(for: "add")?.accessibilityLabel == "In playlist" }
        try await host.settle()
        let swapped = try #require(host.group.button(for: "add"))
        #expect(swapped.accessibilityLabel == "In playlist")
        #expect(swapped.disc.backgroundColor == AnycastColor.sandAlpha5)
        #expect(host.controller.selectedID == host.url(1), "Add closed or moved the group")
        let after = try host.card(1)
        #expect(Self.chip(in: after)?.isHidden == false, "the In playlist chip did not appear")
        #expect(abs(after.cardFrameInCell.height - body) <= 0.5, "card height changed with the chip")
        #expect(after.actionGap == 68)
        let members = try await host.context.database.playlistRepository().playlistContainsURLs([host.url(1)])
        #expect(members.contains(host.url(1)))

        // An episode already in a playlist opens with the added state.
        try host.card(3).onCardTap?()
        try await host.settle()
        #expect(host.controller.selectedID == host.url(3))
        #expect(host.group.button(for: "add")?.accessibilityLabel == "In playlist")
        #expect(Self.chip(in: try host.card(3))?.isHidden == false)
    }

    @Test("Play keeps the group open on its card")
    func playKeepsGroup() async throws {
        let host = try await ChannelHost.make(count: 4)
        defer { host.close() }
        try host.card(0).onCardTap?()
        try await host.settle()
        let play = try #require(host.group.button(for: "play"))
        #expect(play.contentHost.subviews.contains { $0 is PlayPauseIconControl })
        play.sendActions(for: .touchUpInside)
        try await host.settle()
        #expect(host.controller.selectedID == host.url(0))
        #expect(!host.group.isHidden)
        host.context.playback.pause()
    }

    @Test("The pinned header is not FLIP-animated while the cards move; the inset extension composes")
    func pinnedHeaderStaysAndInsetComposes() async throws {
        let host = try await ChannelHost.make(count: 12)
        defer { host.close() }
        let baseInset = host.collection.contentInset.bottom
        let header = try #require(host.collection.visibleSupplementaryViews(
            ofKind: ChannelViewController.headerElementKind).first as? ChannelHeaderView)
        // The lowest visible card needs the list to move to show its group.
        let lowest = try #require(host.collection.visibleCells.compactMap { $0 as? EpisodeCardCell }
            .max { $0.frame.minY < $1.frame.minY })
        let offset = host.collection.contentOffset.y
        lowest.onCardTap?()
        #expect(host.controller.selectedID != nil)
        #expect(header.layer.animation(forKey: ListActionMotion.translationKey) == nil,
                "the pinned header was FLIP-animated")
        #expect(abs(host.collection.contentOffset.y - offset) > 0.5, "opening the lowest card did not move the list")
        #expect(host.collection.visibleCells.contains { $0.layer.animation(forKey: ListActionMotion.translationKey) != nil },
                "the list moved without FLIP on the cards")
        try await host.settle()
        #expect(abs(header.frame.minY - host.collection.contentOffset.y) <= 0.5, "pinned header displaced")

        // A base-inset recompute while open keeps the controller's extension.
        let extended = host.collection.contentInset.bottom
        #expect(abs(extended - baseInset - host.controller.insetExtension) <= 0.5)
        host.channel.viewSafeAreaInsetsDidChange()
        #expect(abs(host.collection.contentInset.bottom - extended) <= 0.5)
        host.controller.close(animated: false)
        #expect(abs(host.collection.contentInset.bottom - baseInset) <= 0.5, "inset did not return to its base")
    }

    // MARK: - Helpers

    static func chip(in cell: EpisodeCardCell) -> UIView? {
        descendants(cell).first { $0.accessibilityIdentifier == "episode-card-in-playlist" }
    }

    static func descendants(_ view: UIView) -> [UIView] {
        view.subviews.flatMap { [$0] + descendants($0) }
    }

    static func find<T: UIViewController>(_ type: T.Type, from root: UIViewController) -> T? {
        var next: UIViewController? = root.presentedViewController
        while let controller = next {
            if let found = controller as? T { return found }
            if let found = controller.children.compactMap({ $0 as? T }).first { return found }
            next = controller.presentedViewController
        }
        return nil
    }
}

/// A UIContext over a private in-memory database (no seeded app data, no
/// network, no audio session work until something plays).
@MainActor
enum ShowListTestContext {
    static func make() async throws -> (UIContext, URL) {
        // SQLite's literal memory path; fileURLWithPath would absolutize it.
        let memoryURL = try #require(URL(string: "file::memory:"))
        let database = try await AppDatabase.openAt(memoryURL, localeIdentifier: "en_US")
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let paths = ApplicationPaths(documents: directory, applicationSupport: directory,
                                     temporary: directory, caches: directory)
        let settings = AppSettings.defaults(localeIdentifier: "en_US")
        let api = APIClient(client: HTTPClient(), tokenProvider: { nil })
        let cache = EpisodeCacheStore(meta: CacheMetaDatabase(queue: nil), directory: directory, maxObjects: { 10 })
        let playback = PlaybackService(
            engine: AVPlayerEngine(), cache: cache, store: DatabasePlaybackStore(database: database),
            settings: settings, session: AudioSessionController(),
            nowPlaying: NowPlayingController(artworkProvider: NowPlayingArtworkProvider(
                coverMeta: CacheMetaDatabase(queue: nil), coverDirectory: directory, fetchImage: { _ in nil }
            ))
        )
        let subtitles = SubtitlePollController(api: api, subtitles: database.subtitleRepository())
        let context = UIContext(
            database: database, api: api, paths: paths, playback: playback, cacheStore: cache,
            sleepTimer: SleepTimerController(), subtitles: subtitles,
            translations: TranslationPollController(
                api: api, translations: database.translationRepository(), subtitles: database.subtitleRepository(),
                targetLanguage: { "en" }, subtitleStatuses: { [:] }
            ),
            settingsBox: SettingsBox(settings), auth: AuthController(), purchases: RevenueCatController()
        )
        return (context, directory)
    }
}

@MainActor
final class ChannelHost {
    let context: UIContext
    let channel: ChannelViewController
    let window: UIWindow
    let rssFeedURL: String
    let directory: URL

    var collection: ListActionCollectionView {
        channel.view.subviews.compactMap { $0 as? ListActionCollectionView }.first!
    }
    var controller: ListActionController { channel.actionController }
    var group: ListActionGroupView { controller.groupView }

    private init(context: UIContext, rssFeedURL: String, directory: URL) {
        self.context = context
        self.rssFeedURL = rssFeedURL
        self.directory = directory
        channel = ChannelViewController(
            context: context, rssFeedURL: rssFeedURL,
            seed: SubscriptionRow(rssFeedUrl: rssFeedURL, title: "Test show")
        )
        window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = channel
        window.isHidden = false
        channel.loadViewIfNeeded()
        window.layoutIfNeeded()
    }

    static func make(count: Int, inPlaylist: Set<Int> = []) async throws -> ChannelHost {
        let (context, directory) = try await ShowListTestContext.make()
        let rss = "https://example.invalid/\(UUID().uuidString).xml"
        let episodes = (0..<count).map { index in
            FeedEpisodeRow(
                title: "Episode \(index)", duration: 1_800_000,
                enclosureUrl: "\(rss)/\(index).mp3", channelTitle: "Test show", rssFeedUrl: rss
            )
        }
        for index in inPlaylist.sorted() {
            try await context.database.playlistRepository().insertOrUpdateByIndex(
                ChannelPlaylistLogic.playlistRow(from: episodes[index], playlistId: ChannelPlaylistLogic.defaultPlaylistID),
                playlistId: ChannelPlaylistLogic.defaultPlaylistID, index: 0
            )
        }
        // Seed the session store so the page reuses a loaded model (no fetch).
        let entry = ChannelSessionStore.shared.entry(
            context: context, rssFeedURL: rss, seed: SubscriptionRow(rssFeedUrl: rss, title: "Test show")
        )
        entry.model.loadForTests(episodes: episodes)
        let host = ChannelHost(context: context, rssFeedURL: rss, directory: directory)
        try await host.settle()
        #expect(host.channel.displayedEpisodes.count == count)
        return host
    }

    func url(_ index: Int) -> String { "\(rssFeedURL)/\(index).mp3" }

    /// Episode `index` sits at item `index + 1` (item 0 is the order row).
    func card(_ index: Int) throws -> EpisodeCardCell {
        try #require(collection.cellForItem(at: IndexPath(item: index + 1, section: 0)) as? EpisodeCardCell)
    }

    func settle() async throws {
        try await Task.sleep(for: .milliseconds(450))
        window.layoutIfNeeded()
        collection.layoutIfNeeded()
    }

    func waitFor(_ condition: () -> Bool) async throws {
        for _ in 0..<40 where !condition() {
            try await Task.sleep(for: .milliseconds(50))
        }
    }

    func close() {
        controller.close(animated: false)
        channel.presentedViewController?.dismiss(animated: false)
        ChannelSessionStore.shared.remove(rssFeedURL: rssFeedURL)
        window.isHidden = true
        window.rootViewController = nil
        try? FileManager.default.removeItem(at: directory)
    }
}
