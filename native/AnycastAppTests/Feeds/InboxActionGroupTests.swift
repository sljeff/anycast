import UIKit
import Testing
import AnycastKit
@testable import Anycast

/// Real Inbox, SQLite, diffable provider and action handlers. Audio transport
/// and session activation are inert so Play does not touch the device's audio.
@MainActor
@Suite(.serialized)
struct InboxActionGroupTests {
    @Test("Body and VoiceOver toggle one group; cover opens Detail")
    func bodyAndCover() async throws {
        let host = try await Host.make(count: 12)
        defer { host.close() }
        let cell = try host.cell(1)
        let height = cell.cardFrameInCell.height
        cell.onCardTap?()
        try await host.settle()
        #expect(host.controller.selectedID == host.url(1))
        #expect(!host.group.isHidden && cell.actionGap == 68)
        #expect(abs(cell.bounds.height - height - 68) <= 0.5)
        #expect(host.group.circles.map(\.actionID) == ["play", "add", "remove", "details"])
        #expect(host.page.presentedViewController == nil)
        #expect(!cell.point(inside: CGPoint(x: 20, y: cell.cardFrameInCell.maxY + 20), with: nil))
        let title = try #require(descendants(cell).first { $0.accessibilityIdentifier == "inbox-episode-title" })
        #expect(title.accessibilityCustomActions?.map(\.name) == ["Play", "Add to playlist", "Remove from inbox", "Show details"])
        #expect(title.accessibilityActivate())
        try await host.settle()
        #expect(host.controller.selectedID == nil && cell.actionGap == 0)
        cell.onCoverTap?()
        try await host.settle()
        #expect(host.page.presentedViewController != nil)
        #expect(findDetail(host.page.presentedViewController))
    }

    @Test("Three rapid Removes apply once each and preserve the group screen y")
    func rapidRemove() async throws {
        let host = try await Host.make(count: 24)
        defer { host.close() }
        try await host.scroll(to: 8)
        try host.cell(8).onCardTap?()
        try await host.settle()
        let y = host.screenY
        let applies = host.page.snapshotApplyCount
        let remove = try #require(host.group.button(for: "remove"))
        for step in 0..<3 {
            remove.sendActions(for: .touchUpInside)
            #expect(host.controller.selectedID == host.url(9 + step))
            #expect(host.page.snapshotApplyCount == applies + step + 1)
            #expect(abs(host.screenY - y) <= 0.5)
            #expect(host.controller.isTravelling)
            let filler = try host.cell(8)
            let frame = filler.cardFrameInCell.offsetBy(dx: filler.frame.minX, dy: filler.frame.minY)
            for x in [frame.minX + 30, frame.maxX - 30] {
                #expect(host.collection.hitTest(CGPoint(x: x, y: frame.minY + 30), with: nil) is ListActionTouchSink)
            }
            #expect(host.page.presentedViewController == nil)
        }
        // The current removal is still durable in SQLite for Undo.
        let stored = try await host.context.database.feedRepository().listAll()
        #expect(stored.contains { $0.enclosureUrl == host.url(10) })
        try await host.settle()
        #expect(host.page.snapshotApplyCount == applies + 3, "settling earlier commits must not apply again")
        #expect(abs(host.screenY - y) <= 0.5)
    }

    @Test("Add leaves once, transfers the group to the filler and inserts durably")
    func addFills() async throws {
        let host = try await Host.make(count: 16)
        defer { host.close() }
        try await host.scroll(to: 5)
        try host.cell(5).onCardTap?()
        try await host.settle()
        let y = host.screenY
        let applies = host.page.snapshotApplyCount
        let add = try #require(host.group.button(for: "add"))
        let path = IndexPath(item: 5, section: host.cardSection)
        let origin = try #require(InboxPageViewController.resolvedFlyInStart(
            actionPath: path, identityPath: path, in: host.collection, window: host.window, addCircle: add
        ))
        let expected = add.convert(CGPoint(x: add.bounds.midX, y: add.bounds.midY), to: host.window)
        #expect(origin == expected)
        add.sendActions(for: .touchUpInside)
        try await host.waitUntil { host.controller.selectedID == host.url(6) }
        #expect(host.page.snapshotApplyCount == applies + 1)
        #expect(abs(host.screenY - y) <= 0.5)
        #expect(try host.cell(5).actionGap == 68)
        let stored = try await host.context.database.feedRepository().listAll()
        #expect(!stored.contains { $0.enclosureUrl == host.url(5) })
        let queued = try await host.context.database.playlistRepository().episode(byEnclosureURL: host.url(5))
        #expect(queued != nil)
        #expect(!descendants(host.window).contains { $0.accessibilityIdentifier == "inbox-removal-undo" })
        try await host.settle()
        #expect(host.page.snapshotApplyCount == applies + 1)
    }

    @Test("Play leaves once and closes instead of handing the group to a filler")
    func playCloses() async throws {
        let host = try await Host.make(count: 12)
        defer { host.close() }
        try host.cell(1).onCardTap?()
        try await host.settle()
        let applies = host.page.snapshotApplyCount
        host.group.button(for: "play")?.sendActions(for: .touchUpInside)
        try await host.waitUntil { host.page.snapshotApplyCount == applies + 1 }
        #expect(host.controller.selectedID == nil && host.group.isHidden)
        #expect(host.collection.visibleCells.compactMap { $0 as? InboxEpisodeCardCell }.allSatisfy { $0.actionGap == 0 })
        #expect(host.context.playback.currentEpisode?.enclosureUrl == host.url(1))
        #expect(host.context.playback.isPlaying)
        #expect(!descendants(host.window).contains { $0.accessibilityIdentifier == "inbox-removal-undo" })
    }

    @Test("Description budgets and heights are final at first display")
    func finalHeights() async throws {
        let host = try await Host.make(count: 12, variedText: true)
        defer { host.close() }
        let cells = try (0..<3).map { try host.cell($0) }
        let heights = cells.map(\.frame.height)
        #expect(heights[0] >= 92)
        for (index, lines) in [(1, 2), (2, 1)] {
            let description = try #require(descendants(cells[index]).compactMap { $0 as? UILabel }.first {
                $0.accessibilityIdentifier == "inbox-episode-description"
            })
            #expect(description.text == "Resolved preview with enough words to fill two lines and still have more to say.")
            #expect(description.numberOfLines == lines)
            #expect(description.bounds.height > 0)
            let title = try #require(descendants(cells[index]).compactMap { $0 as? UILabel }.first {
                $0.accessibilityIdentifier == "inbox-episode-title"
            })
            let actualTitleLines = Int(round(title.bounds.height / title.font.lineHeight))
            #expect(actualTitleLines == 3 - lines)
        }
        try await host.settle()
        #expect(cells.map(\.frame.height) == heights, "description must not arrive after first display")
        await host.page.reload()
        host.collection.layoutIfNeeded()
        #expect(try (0..<3).map { try host.cell($0).frame.height } == heights)
    }

    @Test("Refresh inserts preserve the selected group; shelf and strip never get gaps or a tail")
    func refreshWithChrome() async throws {
        let host = try await Host.make(count: 18, chrome: true)
        defer { host.close() }
        #expect(host.collection.numberOfSections == 3)
        #expect(host.cardSection == 2)
        let chromeCells = try (0..<2).map { section in
            try #require(host.collection.cellForItem(at: IndexPath(item: 0, section: section)))
        }
        #expect(chromeCells.allSatisfy { !($0 is any ListActionGapHosting) })
        #expect(!descendants(host.page.view).contains { $0.accessibilityIdentifier == "inbox-history-tail" })
        try await host.scroll(to: 5)
        try host.cell(5).onCardTap?()
        try await host.settle()
        let y = host.screenY
        let applies = host.page.snapshotApplyCount
        try await host.context.database.feedRepository().insertMany([
            FeedEpisodeRow(title: "New arrival", description: "<p>Already resolved before display.</p>",
                           enclosureUrl: "https://example.invalid/new.mp3", pubDate: 99_000)
        ])
        await host.page.reload()
        #expect(host.controller.selectedID == host.url(5))
        #expect(abs(host.screenY - y) <= 0.5)
        #expect(host.page.snapshotApplyCount == applies + 1)
        try await host.settle()
        #expect(abs(host.screenY - y) <= 0.5)
    }

    @Test("The last card closes the group and reveals the empty state without a tail")
    func lastCardLeaves() async throws {
        let host = try await Host.make(count: 1)
        defer { host.close() }
        try host.cell(0).onCardTap?()
        try await host.settle()
        let applies = host.page.snapshotApplyCount
        host.group.button(for: "remove")?.sendActions(for: .touchUpInside)
        #expect(host.page.snapshotApplyCount == applies + 1)
        #expect(host.collection.numberOfItems(inSection: host.cardSection) == 0)
        #expect(host.controller.selectedID == nil && host.group.isHidden)
        #expect(host.collection.backgroundView is InboxEmptyStateView)
        try await host.settle()
        #expect(host.collection.backgroundView?.alpha == 1)
        #expect(host.collection.numberOfSections == 1)
    }

    private func descendants(_ view: UIView) -> [UIView] {
        view.subviews.flatMap { [$0] + descendants($0) }
    }
    private func findDetail(_ controller: UIViewController?) -> Bool {
        guard let controller else { return false }
        return controller is DetailViewController || controller.children.contains { findDetail($0) }
    }

    @MainActor
    private final class Host {
        let context: UIContext
        let page: InboxPageViewController
        let window: UIWindow
        let directory: URL
        let collection: ListActionCollectionView
        var controller: ListActionController { page.actionController }
        var group: ListActionGroupView { controller.groupView }
        var screenY: CGFloat { group.frame.minY - collection.contentOffset.y }
        var cardSection: Int { collection.numberOfSections - 1 }

        init(context: UIContext, directory: URL) throws {
            self.context = context
            self.directory = directory
            page = InboxPageViewController(context: context)
            let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
            window = UIWindow(windowScene: scene)
            window.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
            window.windowLevel = .alert + 1
            window.rootViewController = page
            page.loadViewIfNeeded()
            collection = try #require(page.view.subviews.compactMap { $0 as? ListActionCollectionView }.first)
            window.isHidden = false
            window.layoutIfNeeded()
        }

        static func make(count: Int, variedText: Bool = false, chrome: Bool = false) async throws -> Host {
            let memoryURL = try #require(URL(string: "file::memory:"))
            #expect(memoryURL.path == ":memory:")
            let database = try await AppDatabase.openAt(memoryURL, localeIdentifier: "en_US")
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let paths = ApplicationPaths(documents: directory, applicationSupport: directory,
                                         temporary: directory, caches: directory)
            let settings = AppSettings.defaults(localeIdentifier: "en_US")
            let api = APIClient(client: HTTPClient(), tokenProvider: { nil })
            let cache = EpisodeCacheStore(meta: CacheMetaDatabase(queue: nil), directory: directory, maxObjects: { 10 })
            let playback = PlaybackService(
                engine: Engine(), cache: CachedAudio(), store: DatabasePlaybackStore(database: database),
                settings: settings, session: AudioSessionController(backend: SilentSession()),
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
            let rows = (0..<count).map { index in
                FeedEpisodeRow(
                    title: variedText && index == 2 ? "A deliberately long episode title that fills two lines of the card" : "Episode \(index)",
                    description: variedText && index > 0 ? "<p>Resolved <b>preview</b> with enough words to fill two lines and still have more to say.</p>" : nil,
                    duration: 600_000, enclosureUrl: "https://example.invalid/\(index).mp3",
                    pubDate: Int64(count - index) * 1_000, channelTitle: "Test show"
                )
            }
            try await database.feedRepository().insertMany(rows)
            if chrome {
                // No feed URL: the shelf/strip render, with no RSS network request.
                try await database.subscriptionRepository().addMany([SubscriptionRow(title: "Test show", categories: "news")])
            }
            let host = try Host(context: context, directory: directory)
            // Read the same production load path. Capture heights as soon as
            // the first snapshot has laid out; no settle before the height test.
            try await host.waitUntil {
                host.collection.numberOfSections == (chrome ? 3 : 1)
                    && host.collection.numberOfItems(inSection: host.cardSection) == count
            }
            host.window.layoutIfNeeded()
            host.collection.layoutIfNeeded()
            #expect(host.collection.numberOfItems(inSection: host.cardSection) == count)
            return host
        }

        func url(_ index: Int) -> String { "https://example.invalid/\(index).mp3" }
        func cell(_ index: Int) throws -> InboxEpisodeCardCell {
            try #require(collection.cellForItem(at: IndexPath(item: index, section: cardSection)) as? InboxEpisodeCardCell)
        }
        func settle() async throws {
            try await Task.sleep(for: .milliseconds(450))
            window.layoutIfNeeded()
            collection.layoutIfNeeded()
        }
        func scroll(to index: Int) async throws {
            collection.scrollToItem(at: IndexPath(item: index, section: cardSection), at: .centeredVertically, animated: false)
            try await settle()
        }
        func waitUntil(_ condition: () -> Bool) async throws {
            for _ in 0..<200 {
                if condition() { return }
                try await Task.sleep(for: .milliseconds(10))
            }
            try #require(condition(), "Inbox action did not finish")
        }
        func close() {
            controller.close(animated: false)
            ToastPresenter.shared.dismissAction(capsuleIdentifier: "inbox-removal-capsule")
            page.dismiss(animated: false)
            window.isHidden = true
            window.rootViewController = nil
            let playback = context.playback
            Task { await playback.clear() }
            try? FileManager.default.removeItem(at: directory)
        }
    }

    @MainActor
    private final class Engine: PlaybackEngine {
        var events: (@MainActor (PlaybackEngineEvent) -> Void)?
        var hasItem = false
        var rate: Float = 1
        var positionMilliseconds: Int64 = 0
        var durationMilliseconds: Int64? = 600_000
        var bufferedMilliseconds: Int64 = 600_000
        func load(url: URL, initialPositionMilliseconds: Int64) { hasItem = true }
        func playImmediately() { events?(.playingChanged(true)) }
        func pause() { events?(.playingChanged(false)) }
        func unload() { hasItem = false }
        func seek(toMilliseconds: Int64) { positionMilliseconds = toMilliseconds }
        func setDesiredSpeed(_ speed: Float) { rate = speed }
    }

    private actor CachedAudio: EpisodeCaching {
        func cachedFile(for url: String) async -> URL? { URL(fileURLWithPath: "/unused-test-audio") }
        func startDownload(url: String, onProgress: @escaping @Sendable (Double?) -> Void) async -> Task<URL, Error> {
            Task { throw URLError(.unsupportedURL) }
        }
        func remove(url: String) async {}
    }

    nonisolated private final class SilentSession: AudioSessionController.Backend, @unchecked Sendable {
        func setCategoryPlayback() throws {}
        func activate() async throws {}
        func deactivate(notifyOthers: Bool) async throws {}
        func setInterruptionHandler(_ handler: @escaping @Sendable (AudioSessionController.Interruption) -> Void) {}
        func setRouteChangeHandler(_ handler: @escaping @Sendable (AudioSessionController.RouteChange) -> Void) {}
    }
}
