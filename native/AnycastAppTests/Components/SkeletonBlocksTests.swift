import UIKit
import Testing
import AnycastKit
@testable import Anycast

/// The shared skeleton: its blocks are drawn from the real cell's geometry,
/// every sweep shares one clock, Reduce Motion stills it, and the network
/// lists show it only after the 300 ms rule.
@MainActor
struct SkeletonBlocksTests {

    private static let width: CGFloat = 358

    // MARK: - Geometry: the blocks are the real card's frames

    /// The Show card (Channel page) and the search card (the same card with
    /// the show name in its meta line): the skeleton's cover block is the
    /// loaded cover's frame and radius, its two title bars sit in the loaded
    /// two-line title's lines, and its meta bar sits on the loaded meta line.
    @Test("Show card skeleton blocks follow the loaded Show card", arguments: [false, true])
    func showCardGeometry(showsChannel: Bool) throws {
        let frame = CGRect(x: 0, y: 0, width: Self.width, height: EpisodeCardCell.showRowHeight)
        let skeleton = EpisodeCardCell(frame: frame)
        skeleton.configureSkeleton()
        skeleton.layoutIfNeeded()

        let real = EpisodeCardCell(frame: frame)
        real.configure(EpisodeCardContent(
            title: String(repeating: "A long episode title that wraps ", count: 4),
            channelTitle: showsChannel ? "Some Show" : "", rightText: "Nov 14 · 42 min",
            descriptionHTML: nil, imageURL: nil, showsChannel: showsChannel, layout: .show
        ), actions: [])
        real.layoutIfNeeded()

        let overlay = try #require(Self.overlay(in: skeleton))
        overlay.refreshBlocks()
        let blocks = overlay.blocks
        #expect(blocks.count == 4, "cover, two title lines, meta")

        // Cover.
        let cover = try #require(Self.coverView(in: real))
        #expect(blocks[0].frame == cover.frame)
        #expect(blocks[0].cornerRadius == cover.layer.cornerRadius)
        #expect(blocks[0].cornerRadius == Radius.md)

        // Title: two bars, one per line of the loaded two-line title.
        let title = try #require(Self.label(in: real) { $0.numberOfLines == 2 })
        let titleFrame = title.convert(title.bounds, to: real.contentView)
        #expect(titleFrame.height >= 2 * TypographyV2.emphasis.font().lineHeight - 0.5, "two real lines")
        let lineHeight = titleFrame.height / 2
        for (index, fraction) in [CGFloat(1), 0.6].enumerated() {
            let block = blocks[1 + index]
            let line = CGRect(x: titleFrame.minX, y: titleFrame.minY + CGFloat(index) * lineHeight,
                              width: titleFrame.width, height: lineHeight)
            #expect(line.contains(block.frame), "title bar \(index) \(block.frame) in line \(line)")
            #expect(abs(block.frame.midY - line.midY) <= 0.5)
            #expect(block.frame.minX == titleFrame.minX)
            #expect(abs(block.frame.width - titleFrame.width * fraction) <= 0.5)
            #expect(block.cornerRadius == block.frame.height / 2)
        }

        // Meta: on the loaded meta label's line.
        let meta = try #require(Self.label(in: real) { $0.text == "Nov 14 · 42 min" })
        let metaFrame = meta.convert(meta.bounds, to: real.contentView)
        #expect(abs(blocks[3].frame.midY - metaFrame.midY) <= 0.5)
        #expect(blocks[3].frame.height < metaFrame.height)

        // Nothing leaves the card, and the card is the loaded card's size.
        for block in blocks { #expect(overlay.bounds.contains(block.frame)) }
        #expect(overlay.bounds.height == EpisodeCardCell.showRowHeight)
    }

    @Test("Channel row skeleton blocks follow the loaded row")
    func channelRowGeometry() throws {
        let frame = CGRect(x: 0, y: 0, width: Self.width, height: PodcastCardCell.rowHeight)
        let skeleton = PodcastCardCell(frame: frame)
        skeleton.configureSkeleton()
        skeleton.layoutIfNeeded()

        let real = PodcastCardCell(frame: frame)
        real.configure(PodcastCardContent(
            rssFeedURL: "u", title: "A title",
            description: String(repeating: "A long description that wraps onto two lines. ", count: 3), imageURL: nil
        ))
        real.layoutIfNeeded()

        let overlay = try #require(Self.overlay(in: skeleton))
        overlay.refreshBlocks()
        let blocks = overlay.blocks
        #expect(blocks.count == 4, "cover, title, two description lines")

        let cover = try #require(Self.coverView(in: real))
        #expect(blocks[0].frame == cover.frame)
        #expect(blocks[0].cornerRadius == Radius.sm)

        let title = try #require(Self.label(in: real) { $0.numberOfLines == 1 })
        let titleFrame = title.convert(title.bounds, to: real.contentView)
        #expect(abs(blocks[1].frame.midY - titleFrame.midY) <= 0.5)
        #expect(blocks[1].frame.minX == titleFrame.minX)

        let description = try #require(Self.label(in: real) { $0.numberOfLines == 2 })
        let descriptionFrame = description.convert(description.bounds, to: real.contentView)
        let lineHeight = descriptionFrame.height / 2
        for index in 0..<2 {
            let block = blocks[2 + index]
            let midY = descriptionFrame.minY + (CGFloat(index) + 0.5) * lineHeight
            #expect(abs(block.frame.midY - midY) <= 0.5, "description bar \(index)")
        }
        #expect(blocks[2].frame.width == descriptionFrame.width)
        #expect(blocks[3].frame.width < blocks[2].frame.width)
        for block in blocks { #expect(overlay.bounds.contains(block.frame)) }
    }

    // MARK: - The sweep

    @Test("Reduce Motion: static blocks and no animation")
    func reduceMotion() throws {
        let host = Self.window()
        defer { host.window.isHidden = true }
        let overlay = host.overlay

        overlay.reduceMotion = { true }
        #expect(!overlay.blocks.isEmpty, "the blocks still draw")
        #expect(overlay.sweepAnimation == nil)

        overlay.reduceMotion = { false }
        #expect(overlay.sweepAnimation != nil)

        // The setting turning on removes a running sweep.
        overlay.reduceMotion = { true }
        NotificationCenter.default.post(name: Motion.reduceMotionDidChange, object: nil)
        #expect(overlay.sweepAnimation == nil)
    }

    @Test("Every skeleton shares one sweep clock and phase")
    func sharedClock() async throws {
        let first = Self.window()
        defer { first.window.isHidden = true }
        try await Task.sleep(for: .milliseconds(120))
        let second = Self.window()
        defer { second.window.isHidden = true }

        let a = try #require(first.overlay.sweepAnimation)
        let b = try #require(second.overlay.sweepAnimation)
        #expect(a.duration == SkeletonClock.period && b.duration == SkeletonClock.period)
        #expect(SkeletonClock.period == 1.4)
        #expect(a.repeatCount == .infinity && b.repeatCount == .infinity)
        // One begin time for both, though they were created 120 ms apart.
        #expect(abs(a.beginTime - b.beginTime) < 0.000_001)
        #expect(abs(a.beginTime - SkeletonClock.epoch) < 0.000_001)
        #expect(a.animations?.count == 2)

        let phase = SkeletonClock.phase()
        #expect(phase >= 0 && phase < 1)
        // A full period later is the same phase.
        let now = CACurrentMediaTime()
        let later = SkeletonClock.phase(at: now + SkeletonClock.period)
        #expect(abs(SkeletonClock.phase(at: now) - later) < 0.000_001)
    }

    @Test("A hidden skeleton does not run; showing it again re-arms the sweep")
    func hiddenStops() throws {
        let host = Self.window()
        defer { host.window.isHidden = true }
        #expect(host.overlay.sweepAnimation != nil)
        host.overlay.isHidden = true
        #expect(host.overlay.sweepAnimation == nil)
        host.overlay.isHidden = false
        #expect(host.overlay.sweepAnimation != nil)
    }

    // MARK: - The 300 ms rule, generalized

    @Test("LoadingDelay.update: nothing inside the threshold, the skeleton after, reset when done")
    func loadingDelayUpdate() async throws {
        let delay = LoadingDelay()
        var fired = 0
        #expect(!delay.update(isLoading: false) { fired += 1 }, "not loading shows nothing")
        #expect(!delay.isRunning)

        #expect(!delay.update(isLoading: true) { fired += 1 }, "inside the threshold nothing shows")
        #expect(delay.isRunning)
        #expect(!delay.update(isLoading: true) { fired += 1 }, "repeated renders do not restart or show it")
        #expect(fired == 0)
        try await Task.sleep(for: .milliseconds(450))
        #expect(fired == 1, "one due callback")
        #expect(delay.update(isLoading: true) { fired += 1 }, "past the threshold the skeleton shows")
        #expect(fired == 1)

        #expect(!delay.update(isLoading: false) { fired += 1 })
        #expect(!delay.isDue)

        // A fetch that ends inside the threshold never shows anything.
        #expect(!delay.update(isLoading: true) { fired += 1 })
        #expect(!delay.update(isLoading: false) { fired += 1 })
        try await Task.sleep(for: .milliseconds(450))
        #expect(fired == 1, "a cancelled delay must not fire")
        #expect(!delay.update(isLoading: false) { fired += 1 })
    }

    // MARK: - Search pages show the skeleton through the rule

    @Test("Search pages: no skeleton for a fast fetch, skeleton rows past 300 ms, no spinner")
    func searchPagesSkeleton() async throws {
        let host = try await PlaylistActionGroupTests.Host.make(count: 0)
        defer { host.close() }
        let context = host.context

        for slow in [false, true] {
            let delay: Duration = slow ? .milliseconds(900) : .milliseconds(60)
            let model = SearchPageViewModel(
                searchText: "q",
                fetchChannels: { _ in try await Task.sleep(for: delay); return [] },
                fetchEpisodes: { _ in try await Task.sleep(for: delay); return [] }
            )
            let channels = SearchChannelsPageViewController(context: context, viewModel: model)
            let episodes = SearchEpisodesPageViewController(context: context, viewModel: model)
            let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
            let pager = UIViewController()
            window.rootViewController = pager
            window.isHidden = false
            for page in [channels, episodes] {
                pager.addChild(page)
                page.view.frame = window.bounds
                pager.view.addSubview(page.view)
                page.didMove(toParent: pager)
            }
            model.search()
            window.layoutIfNeeded()
            #expect(!channels.showsSkeleton && !episodes.showsSkeleton, "nothing inside 300 ms")

            try await Task.sleep(for: .milliseconds(slow ? 450 : 200))
            window.layoutIfNeeded()
            if slow {
                #expect(channels.showsSkeleton && episodes.showsSkeleton, "skeleton past 300 ms")
                let channelList = try #require(Self.collection(in: channels.view))
                channelList.layoutIfNeeded()
                #expect(channelList.numberOfItems(inSection: 0) == SearchChannelsPageViewController.skeletonRowCount)
                let episodeList = try #require(Self.collection(in: episodes.view))
                episodeList.layoutIfNeeded()
                #expect(episodeList.numberOfItems(inSection: 0) == SearchEpisodesPageViewController.skeletonRowCount)
                let card = try #require(episodeList.cellForItem(at: IndexPath(item: 0, section: 0)) as? EpisodeCardCell)
                let overlay = try #require(Self.overlay(in: card))
                #expect(!overlay.isHidden && !overlay.blocks.isEmpty)
                #expect(overlay.sweepAnimation != nil, "the sweep runs in a window")
            } else {
                #expect(!channels.showsSkeleton && !episodes.showsSkeleton, "a fast fetch never showed it")
            }
            #expect(!Self.hasSpinner(channels.view) && !Self.hasSpinner(episodes.view), "no spinner in either page")

            try await Task.sleep(for: .milliseconds(slow ? 700 : 100))
            #expect(!channels.showsSkeleton && !episodes.showsSkeleton, "done: the skeleton is gone")
            window.isHidden = true
        }
    }

    // MARK: - Helpers

    private static func window() -> (window: UIWindow, overlay: SkeletonBlocksView) {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 200))
        let controller = UIViewController()
        window.rootViewController = controller
        window.isHidden = false
        let bar = UILabel(frame: CGRect(x: 16, y: 16, width: 200, height: 22))
        bar.text = "Placeholder"
        controller.view.addSubview(bar)
        let overlay = SkeletonBlocksView(frame: controller.view.bounds)
        overlay.shapes = [.lines(bar, [0.8])]
        controller.view.addSubview(overlay)
        window.layoutIfNeeded()
        overlay.layoutIfNeeded()
        return (window, overlay)
    }

    private static func overlay(in view: UIView) -> SkeletonBlocksView? {
        all(in: view).compactMap { $0 as? SkeletonBlocksView }.first
    }

    private static func coverView(in cell: UIView) -> UIImageView? {
        all(in: cell).compactMap { $0 as? UIImageView }.first { $0.bounds.width >= 56 }
    }

    private static func label(in view: UIView, where match: (UILabel) -> Bool) -> UILabel? {
        all(in: view).compactMap { $0 as? UILabel }.first(where: match)
    }

    private static func collection(in view: UIView) -> UICollectionView? {
        all(in: view).compactMap { $0 as? UICollectionView }.first
    }

    private static func hasSpinner(_ view: UIView) -> Bool {
        all(in: view).contains { $0 is UIActivityIndicatorView }
    }

    private static func all(in view: UIView) -> [UIView] {
        view.subviews + view.subviews.flatMap { all(in: $0) }
    }
}
