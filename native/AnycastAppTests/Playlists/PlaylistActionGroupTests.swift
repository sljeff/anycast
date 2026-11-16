import UIKit
import Testing
import AnycastKit
@testable import Anycast

/// Real Playlist wiring with a private SQLite memory database. No seeded app
/// database, audio playback, poll timers, or network requests are needed.
@Suite(.serialized)
@MainActor
struct PlaylistActionGroupTests {
    @Test("Card and VoiceOver toggles share one group below a 68 pt gap")
    func toggleCloseAndSwitch() async throws {
        let host = try await Host.make(count: 12)
        defer { host.close() }
        let first = try host.cell(2)
        let bodyHeight = first.cardFrameInCell.height
        first.onCardTap?()
        try await host.settle()
        #expect(host.controller.selectedID == host.url(2))
        #expect(first.actionGap == 68)
        #expect(abs(first.bounds.height - bodyHeight - 68) <= 0.5)
        #expect(abs(host.group.frame.minY - first.frame.minY - first.cardFrameInCell.maxY - 12) <= 0.5)
        #expect(host.group.superview === host.collection)
        #expect(host.collection.visibleCells.allSatisfy { $0.layer.zPosition > host.group.layer.zPosition })
        #expect(host.group.circles.map(\.actionID) == ["play", "transcript", "remove", "details"])
        #expect(host.group.button(for: "details")?.accessibilityLabel == "Details")
        let play = try #require(host.group.button(for: "play"))
        let overlay = try #require(play.contentHost.subviews.compactMap { $0 as? PlayPauseIconControl }.first)
        #expect(abs(overlay.bounds.width - overlay.size) <= 0.5)
        #expect(abs(overlay.bounds.height - overlay.size) <= 0.5)
        #expect(play.accessibilityLabel == overlay.accessibilityLabel)
        #expect(!overlay.isAccessibilityElement && !overlay.isUserInteractionEnabled)

        first.onCardTap?()
        try await host.settle()
        #expect(host.controller.selectedID == nil && host.group.isHidden)
        #expect(first.actionGap == 0)
        #expect(abs(first.bounds.height - bodyHeight) <= 0.5)

        let title = try #require(descendants(first).compactMap { $0 as? UILabel }.first {
            $0.accessibilityCustomActions?.contains { $0.name == "Move up" } == true
        })
        #expect(title.accessibilityCustomActions?.map(\.name)
                == ["Show details", "Move up", "Move down", "Play", "Transcribe with AI", "Remove"])
        #expect(title.accessibilityActivate())
        try await host.settle()
        #expect(host.controller.selectedID == host.url(2))
        let second = try host.cell(3)
        second.onCardTap?()
        try await host.settle()
        #expect(host.controller.selectedID == host.url(3))
        #expect(first.actionGap == 0 && second.actionGap == 68)
        #expect(host.group.button(for: "play") === play, "live hosts survive a selection change")
    }

    @Test("Three rapid deferred removes preserve the group and do not reconfigure survivors")
    func rapidRemovesFillFromBelow() async throws {
        let host = try await Host.make(count: 24)
        defer { host.close() }
        try await host.scroll(to: 8)
        // Production cards normally have equal heights. Synthetic plate minima
        // exercise the real self-sizing path with mixed heights, without changing
        // the cell provider or substituting a fake list/controller.
        try host.setHeight(164, at: 8)
        try host.setHeight(112, at: 9)
        try host.setHeight(148, at: 10)
        try host.setHeight(128, at: 11)
        host.collection.layoutIfNeeded()
        try host.cell(8).onCardTap?()
        try await host.settle()
        let y = host.screenY
        let originalCount = host.list.snapshotApplyCount
        let originalFloor = host.collection.contentSize.height + host.collection.contentInset.bottom
        for step in 0..<3 {
            let removed = try #require(host.controller.selectedID)
            let survivors = host.visibleCalls(excluding: removed)
            let calls = host.list.snapshotApplyCount
            // Real Remove circle -> binder's deferred path -> hideEpisode.
            host.group.button(for: "remove")?.sendActions(for: .touchUpInside)
            #expect(host.controller.selectedID == host.url(9 + step))
            #expect(host.list.snapshotApplyCount == calls + 1)
            #expect(abs(host.screenY - y) <= 0.5)
            #expect(abs(host.collection.contentSize.height + host.collection.contentInset.bottom - originalFloor) <= 0.5)
            host.expectUnconfigured(survivors)
        }
        #expect(host.list.snapshotApplyCount == originalCount + 3)
        // Commit callbacks can resync later (single PendingRemoval is batch 2).
        // The count above covers each synchronous visual removal transaction.
        await host.list.binder.commitPendingRemoval()
    }

    @Test("Removing the last card fills from above without moving the group")
    func lastCardFillsFromAbove() async throws {
        let host = try await Host.make(count: 20)
        defer { host.close() }
        try await host.scroll(to: 19)
        try host.cell(19).onCardTap?()
        try await host.settle()
        let y = host.screenY
        #expect(host.collection.contentOffset.y > 0)
        let calls = host.list.snapshotApplyCount
        host.list.hideEpisode(byEnclosureURL: host.url(19))
        #expect(host.controller.selectedID == host.url(18))
        #expect(abs(host.screenY - y) <= 0.5)
        #expect(host.list.snapshotApplyCount == calls + 1)
        try await host.settle()
        #expect(abs(host.screenY - y) <= 0.5)
    }

    @Test("At the top a shorter filler moves the group exactly by the height difference")
    func shorterFillerAtTop() async throws {
        let host = try await Host.make(count: 12)
        defer { host.close() }
        try host.setHeight(164, at: 0)
        try host.setHeight(112, at: 1)
        host.collection.layoutIfNeeded()
        let oldHeight = try host.cell(0).cardFrameInCell.height
        let fillerHeight = try host.cell(1).cardFrameInCell.height
        #expect(oldHeight > fillerHeight)
        try host.cell(0).onCardTap?()
        try await host.settle()
        let y = host.screenY
        let minimumOffset = -host.collection.adjustedContentInset.top
        #expect(abs(host.collection.contentOffset.y - minimumOffset) <= 0.5)
        host.list.hideEpisode(byEnclosureURL: host.url(0))
        // The scroll view cannot compensate past its top. This is the single
        // documented exception: the group moves by fillerHeight - oldHeight.
        let expectedY = y + fillerHeight - oldHeight
        #expect(abs(host.screenY - expectedY) <= 0.5)
        #expect(abs(host.collection.contentOffset.y - minimumOffset) <= 0.5)
        try await host.settle()
        #expect(abs(host.screenY - expectedY) <= 0.5, "no second correction after travel")
    }

    @Test("Travelling cover and body taps are consumed; the band retains the same circle")
    func travelRoutesTouches() async throws {
        let host = try await Host.make(count: 20)
        defer { host.close() }
        try await host.scroll(to: 8)
        try host.cell(8).onCardTap?()
        try await host.settle()
        let remove = try #require(host.group.button(for: "remove"))
        let bandPoint = host.group.convert(remove.center, to: host.collection)
        remove.sendActions(for: .touchUpInside)
        #expect(host.controller.isTravelling)
        let filler = try host.cell(8) // former item 9, resolved in the new snapshot
        let frame = filler.cardFrameInCell.offsetBy(dx: filler.frame.minX, dy: filler.frame.minY)
        for x in [frame.minX + 40, frame.maxX - 40] {
            let hit = host.collection.hitTest(CGPoint(x: x, y: frame.minY + 30), with: nil)
            #expect(hit is ListActionTouchSink, "neither the cover nor body recognizer may receive travel taps")
            (hit as? UIControl)?.sendActions(for: .touchUpInside)
            #expect(host.list.presentedViewController == nil)
            #expect(host.controller.selectedID == host.url(9))
        }
        let routed = host.collection.hitTest(bandPoint, with: nil)
        #expect(routed === remove)
        (routed as? UIControl)?.sendActions(for: .touchUpInside)
        #expect(host.controller.selectedID == host.url(10), "the retained circle acts on the filler identity")
        #expect(host.list.presentedViewController == nil)
        await host.list.binder.commitPendingRemoval()
    }

    @Test("Removing through empty closes the group and restores the owner's bottom inset")
    func removingUntilEmpty() async throws {
        let host = try await Host.make(count: 4)
        defer { host.close() }
        host.collection.contentInset.bottom = 23
        try host.cell(0).onCardTap?()
        try await host.settle()
        for index in 0..<4 {
            host.list.hideEpisode(byEnclosureURL: host.url(index))
        }
        #expect(host.list.episodes.isEmpty)
        #expect(host.controller.selectedID == nil)
        #expect(host.group.isHidden)
        #expect(host.collection.contentInset.bottom == 23)
        try await host.settle()
        #expect(!host.controller.isTravelling)
    }

    @Test("Unchanged reload keeps the gap; an externally vanished selection closes the group")
    func reloadKeepsIdentity() async throws {
        let host = try await Host.make(count: 12)
        defer { host.close() }
        try host.cell(2).onCardTap?()
        try await host.settle()
        let calls = host.visibleCalls()
        await host.list.reloadEpisodes()
        #expect(host.controller.selectedID == host.url(2))
        #expect(try host.cell(2).actionGap == 68)
        host.expectUnconfigured(calls)
        for index in [2, 3] {
            try await host.context.database.playlistRepository().removeEpisode(byEnclosureURL: host.url(index))
        }
        await host.list.reloadEpisodes()
        try await host.settle()
        // Not a user Remove (no consumeUserLeave): the group closes instead of
        // handing itself to a filler.
        #expect(host.controller.selectedID == nil)
        #expect(host.group.isHidden)
        let cells = host.collection.visibleCells.compactMap { $0 as? EpisodeCardCell }
        #expect(!cells.isEmpty)
        #expect(cells.allSatisfy { $0.actionGap == 0 }, "no cell may keep the 68 pt gap")
        #expect(!cells.contains { $0.actionGap == ListActionMetrics.gap })
    }

    @Test("Play from a closed group still plays: the row moves to the top")
    func playFromClosedGroupStillPlays() async throws {
        let host = try await Host.make(count: 6)
        defer { host.close() }
        #expect(host.controller.selectedID == nil)
        let cell = try host.cell(3)
        let play = try #require(cell.menuActions.first { $0.accessibilityLabel == "Play" })
        play.handler()
        // close(animated:completion:) must still run the completion with
        // nothing selected, which moves the episode to the head.
        var head: String?
        for _ in 0..<30 {
            try await Task.sleep(for: .milliseconds(50))
            head = try await host.context.database.playlistRepository().listEpisodes(playlistId: 1).first?.enclosureUrl
            if head == host.url(3) { break }
        }
        #expect(head == host.url(3))
    }

    @Test("Closed-group VoiceOver reorders resolve the current index and no-op at the edges")
    func accessibilityReorderResolvesIdentity() async throws {
        let host = try await Host.make(count: 5)
        defer { host.close() }
        let first = try host.cell(0)
        let next = try host.cell(1)
        var moves: [(Int, Int)] = []
        host.list.binder.reorderHandler = { moves.append(($0, $1)) }
        try #require(first.menuActions.first { $0.accessibilityLabel == "Move up" }).handler()
        #expect(moves.isEmpty)
        let moveUp = try #require(next.menuActions.first { $0.accessibilityLabel == "Move up" })
        moveUp.handler()
        #expect(moves.count == 1 && moves[0].0 == 1 && moves[0].1 == 0)
        host.list.hideEpisode(byEnclosureURL: host.url(0))
        moveUp.handler()
        #expect(moves.count == 1, "the retained action sees its new head position")
        let last = try host.cell(3)
        try #require(last.menuActions.first { $0.accessibilityLabel == "Move down" }).handler()
        #expect(moves.count == 1)
        #expect(host.controller.selectedID == nil)
    }

    @Test("Playlist card: 96 pt plate, 72 pt cover, no description, time before show")
    func playlistCardComposition() async throws {
        let host = try await Host.make(count: 3)
        defer { host.close() }
        let cell = try host.cell(0)
        #expect(abs(cell.cardFrameInCell.height - EpisodeCardCell.playlistRowHeight) <= 1)
        #expect(abs(cell.bounds.height - EpisodeCardCell.playlistRowHeight) <= 1)

        let views = descendants(cell)
        let cover = try #require(views.compactMap { $0 as? UIImageView }.first {
            $0.accessibilityLabel == "Episode details"
        })
        #expect(abs(cover.bounds.width - 72) <= 0.5 && abs(cover.bounds.height - 72) <= 0.5)

        let description = try #require(views.compactMap { $0 as? UILabel }.first {
            $0.accessibilityIdentifier == "episode-card-description"
        })
        #expect(description.isHidden, "the playlist card has no description line")

        let labels = views.compactMap { $0 as? UILabel }
        let time = try #require(labels.first { $0.text == "10m" })
        let show = try #require(labels.first { $0.text == "Test show" })
        let timeFrame = time.convert(time.bounds, to: cell)
        let showFrame = show.convert(show.bounds, to: cell)
        #expect(timeFrame.maxX <= showFrame.minX, "meta order is time · show")
        #expect(abs(timeFrame.midY - showFrame.midY) <= 1, "one meta row")
        let marker = views.compactMap { $0 as? UIImageView }.first { $0.accessibilityLabel == "Now playing" }
        if host.context.playback.currentEpisode?.enclosureUrl != host.url(0) {
            #expect(marker == nil || marker?.isHidden == true, "only the current episode shows the marker")
        }
    }

    @Test("List end: queue summary footer replaces the history capsule; a programmatic overscroll shows no orb")
    func endFooter() async throws {
        let host = try await Host.make(count: 3)
        defer { host.close() }
        let footer = try #require(host.collection.subviews.compactMap { $0 as? PlaylistEndFooterView }.first)
        let text = try #require(footer.displayedText)
        let speed = PlayerSliderMath.speedText(Double(host.context.playback.speed))
        #expect(text.hasPrefix("30 m left · done around "))
        #expect(text.hasSuffix(" at \(speed)"))
        #expect(footer.orbAlpha == 0)
        // The history capsule class is gone entirely (Inbox dropped it too).

        // Only a finger drag counts: a programmatic offset past the end must
        // neither show the orb nor open History.
        host.collection.contentOffset.y += 300
        #expect(footer.orbAlpha == 0)
        #expect(host.list.presentedViewController == nil)
    }

    private func descendants(_ view: UIView) -> [UIView] {
        view.subviews.flatMap { [$0] + descendants($0) }
    }

    @MainActor
    private final class Host {
        let context: UIContext
        let list: PlaylistEpisodeListViewController
        let window: UIWindow
        let directory: URL
        var collection: ListActionCollectionView { list.edgeScrollView as! ListActionCollectionView }
        var controller: ListActionController { list.actionController }
        var group: ListActionGroupView { controller.groupView }
        var screenY: CGFloat { group.frame.minY - collection.contentOffset.y }

        init(context: UIContext, directory: URL) {
            self.context = context
            self.directory = directory
            list = PlaylistEpisodeListViewController(context: context, playlistId: 1)
            window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
            window.rootViewController = list
            window.isHidden = false
            list.loadViewIfNeeded()
            collection.contentInsetAdjustmentBehavior = .never
            list.topChromeInset = 100
            window.layoutIfNeeded()
        }

        static func make(count: Int) async throws -> Host {
            // Preserve SQLite's literal memory path; fileURLWithPath would
            // absolutize it and accidentally create an on-disk file.
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
            for index in 0..<count {
                try await database.playlistRepository().insertOrUpdateByIndex(
                    PlaylistEpisodeRow(title: "Episode \(index)", duration: 600_000,
                                       enclosureUrl: "https://example.invalid/\(index).mp3", channelTitle: "Test show", playlistId: 1),
                    playlistId: 1, index: index
                )
            }
            let host = Host(context: context, directory: directory)
            await host.list.reloadEpisodes()
            try await host.settle()
            // Catch a viewDidLoad/viewWillAppear read that superseded our first.
            await host.list.reloadEpisodes()
            try await host.settle()
            #expect(host.list.visibleCount == count)
            return host
        }

        func url(_ originalIndex: Int) -> String { "https://example.invalid/\(originalIndex).mp3" }

        func cell(_ index: Int) throws -> EpisodeCardCell {
            try #require(collection.cellForItem(at: IndexPath(item: index, section: 0)) as? EpisodeCardCell)
        }

        func settle() async throws {
            try await Task.sleep(for: .milliseconds(450))
            window.layoutIfNeeded()
            collection.layoutIfNeeded()
        }

        func scroll(to index: Int) async throws {
            collection.scrollToItem(at: IndexPath(item: index, section: 0), at: .centeredVertically, animated: false)
            try await settle()
        }

        func setHeight(_ height: CGFloat, at index: Int) throws {
            let cell = try cell(index)
            let stack = try #require(cell.contentView.subviews.first as? UIStackView)
            let plate = try #require(stack.arrangedSubviews.first)
            plate.heightAnchor.constraint(equalToConstant: height).isActive = true
            collection.collectionViewLayout.invalidateLayout()
            collection.layoutIfNeeded()
            #expect(abs(cell.cardFrameInCell.height - height) <= 0.5)
        }

        func visibleCalls(excluding removed: String? = nil) -> [String: Int] {
            var result: [String: Int] = [:]
            for path in collection.indexPathsForVisibleItems {
                guard let url = list.episode(at: path)?.enclosureUrl, url != removed else { continue }
                result[url] = list.cellProviderCalls[url, default: 0]
            }
            return result
        }

        func expectUnconfigured(_ calls: [String: Int], sourceLocation: SourceLocation = #_sourceLocation) {
            for (url, count) in calls {
                #expect(list.cellProviderCalls[url, default: 0] == count,
                        "surviving cell \(url) was configured again", sourceLocation: sourceLocation)
            }
        }

        func close() {
            controller.close(animated: false)
            ToastPresenter.shared.dismissAction(capsuleIdentifier: "playlist-removal-capsule")
            window.isHidden = true
            window.rootViewController = nil
            try? FileManager.default.removeItem(at: directory)
        }
    }
}
