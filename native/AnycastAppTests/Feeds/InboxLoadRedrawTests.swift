import UIKit
import Foundation
import Testing
import Kingfisher
import AnycastKit
@testable import Anycast

/// The inbox load/redraw contract: automatic refreshes never move the list,
/// the header status line is one fixed line, card text is final on the first
/// layout, and a disk-cached cover is the real image on the first frame.
@MainActor
@Suite(.serialized)
struct InboxLoadRedrawTests {

    // MARK: - Refresh triggers

    @Test("Only user-initiated triggers reveal the refresh control")
    func triggerTable() {
        #expect(InboxRefreshTrigger.pull.revealsRefreshControl)
        #expect(InboxRefreshTrigger.tabRetapAtTop.revealsRefreshControl)
        #expect(!InboxRefreshTrigger.firstAppear.revealsRefreshControl)
        #expect(!InboxRefreshTrigger.delayedAuto.revealsRefreshControl)
        #expect(!InboxRefreshTrigger.periodicAuto.revealsRefreshControl)
    }

    // MARK: - Status line

    @Test("Status line: updating, N new, default")
    func statusLine() {
        let now = Date()
        let recent = now.addingTimeInterval(-5)
        #expect(InboxHeaderStatus.text(
            isUpdating: true, newCount: 3, lastRefresh: recent, episodeCount: 10, now: now
        ) == "Updating…")
        #expect(InboxHeaderStatus.text(
            isUpdating: false, newCount: 3, lastRefresh: recent, episodeCount: 10, now: now
        ) == "3 new · updated just now")
        #expect(InboxHeaderStatus.text(
            isUpdating: false, newCount: 0, lastRefresh: recent, episodeCount: 10, now: now
        ) == "updated just now · 10 unlistened")
        // Never nil and never empty: the first state reserves the line.
        #expect(InboxHeaderStatus.text(
            isUpdating: false, newCount: 0, lastRefresh: nil, episodeCount: 0, now: now
        ) == "updated — · 0 unlistened")
        // A count larger than the list is stale (rows left): not shown.
        #expect(InboxHeaderStatus.text(
            isUpdating: false, newCount: 4, lastRefresh: recent, episodeCount: 0, now: now
        ) == "updated just now · 0 unlistened")
    }

    @Test("New rows are those whose enclosure URL the list did not know")
    func newRowCount() {
        let rows = ["a", "b", "c"].map { FeedEpisodeRow(enclosureUrl: $0) } + [FeedEpisodeRow()]
        #expect(InboxHeaderStatus.newRowCount(known: ["a"], current: rows) == 2)
        #expect(InboxHeaderStatus.newRowCount(known: ["a", "b", "c"], current: rows) == 0)
    }

    // MARK: - Description resolver

    private nonisolated final class ParseCounter: @unchecked Sendable {
        private let lock = NSLock()
        private var seen: [String] = []
        func record(_ html: String) { lock.lock(); seen.append(html); lock.unlock() }
        var calls: [String] { lock.lock(); defer { lock.unlock() }; return seen }
    }

    private func row(_ url: String?, _ html: String?) -> FeedEpisodeRow {
        FeedEpisodeRow(description: html, enclosureUrl: url)
    }

    @Test("Plain text is resolved before render and reused without re-parsing")
    func resolverResolvesOnceAndReuses() async {
        let counter = ParseCounter()
        let parse: @Sendable (String) -> String = { html in counter.record(html); return "plain:" + html }
        let rows = [row("a", "<p>A</p>"), row("b", "<p>B</p>"), row("c", nil), row(nil, "<p>no url</p>")]

        let first = await InboxDescriptionResolver.resolve(rows: rows, existing: [:], parse: parse)
        #expect(Set(counter.calls) == ["<p>A</p>", "<p>B</p>"])
        #expect(InboxDescriptionResolver.plainText(for: rows[0], in: first) == "plain:<p>A</p>")
        #expect(InboxDescriptionResolver.plainText(for: rows[2], in: first) == "", "nil description is resolved empty")
        #expect(InboxDescriptionResolver.plainText(for: rows[3], in: first) == nil, "no URL: cell HTML fallback")

        // Same rows again: nothing is parsed.
        let second = await InboxDescriptionResolver.resolve(rows: rows, existing: first, parse: parse)
        #expect(counter.calls.count == 2, "resolved rows were parsed again")
        #expect(second == first)

        // One changed HTML re-parses only that row; a row that left drops out.
        let changed = [row("a", "<p>A2</p>"), row("b", "<p>B</p>")]
        let third = await InboxDescriptionResolver.resolve(rows: changed, existing: second, parse: parse)
        #expect(counter.calls.count == 3 && counter.calls.last == "<p>A2</p>")
        #expect(third["c"] == nil)
        #expect(InboxDescriptionResolver.plainText(for: changed[0], in: third) == "plain:<p>A2</p>")
        // A stale entry never answers for newer HTML.
        #expect(InboxDescriptionResolver.plainText(for: changed[0], in: second) == nil)
    }

    // MARK: - Hosted first layout

    private final class CardSource: NSObject, UICollectionViewDataSource {
        let count = 5
        func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int { count }
        func collectionView(
            _ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath
        ) -> UICollectionViewCell {
            let cell = collectionView.dequeueReusableCell(
                withReuseIdentifier: InboxEpisodeCardCell.reuseIdentifier, for: indexPath
            )
            let long = String(repeating: "A description that is long enough to wrap onto a second line. ", count: 4)
            let plain = indexPath.item.isMultiple(of: 2) ? long : "Short"
            (cell as? InboxEpisodeCardCell)?.configure(InboxCardContent(
                title: "Episode \(indexPath.item) with a title long enough to need a couple of lines in a card",
                showName: "Show", metaText: "1d ago · 30m",
                descriptionHTML: "<p>\(plain)</p>", imageURL: nil,
                descriptionPlainText: plain
            ))
            return cell
        }
    }

    private func heights(of collectionView: UICollectionView, count: Int) -> [CGFloat] {
        (0..<count).map { collectionView.cellForItem(at: IndexPath(item: $0, section: 0))?.frame.height ?? -1 }
    }

    @Test("Cards in a hosted list have their settled height on the first layout")
    func firstLayoutHeightsAreSettled() async throws {
        let scene = try #require(
            UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first,
            "self-sizing needs a connected scene"
        )
        let window = UIWindow(windowScene: scene)
        window.windowLevel = .alert + 1
        defer { window.isHidden = true; window.rootViewController = nil }

        let layout = UICollectionViewCompositionalLayout { _, environment in
            var config = UICollectionLayoutListConfiguration(appearance: .plain)
            config.showsSeparators = false
            config.backgroundColor = .clear
            return NSCollectionLayoutSection.list(using: config, layoutEnvironment: environment)
        }
        let collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        let source = CardSource()
        collectionView.register(InboxEpisodeCardCell.self, forCellWithReuseIdentifier: InboxEpisodeCardCell.reuseIdentifier)
        collectionView.dataSource = source
        let host = UIViewController()
        host.view.addSubview(collectionView)
        collectionView.frame = CGRect(x: 0, y: 0, width: 390, height: 2400)
        window.frame = CGRect(x: 0, y: 0, width: 390, height: 2400)
        window.rootViewController = host
        window.isHidden = false

        collectionView.layoutIfNeeded()
        let first = heights(of: collectionView, count: source.count)
        #expect(first.allSatisfy { $0 > 0 }, "cells not realised: \(first)")

        try await Task.sleep(nanoseconds: 300_000_000)
        collectionView.layoutIfNeeded()
        #expect(heights(of: collectionView, count: source.count) == first, "heights moved after first layout")

        collectionView.reloadData()
        collectionView.layoutIfNeeded()
        #expect(heights(of: collectionView, count: source.count) == first, "reload changed first-layout heights")
    }

    // MARK: - Artwork

    @Test("A disk-cached cover is the real image synchronously, not the placeholder")
    func diskCachedCoverIsSynchronous() async throws {
        let url = try #require(URL(string: "https://example.invalid/anycast-p0-\(UUID().uuidString).png"))
        let side: CGFloat = 36
        let cover = UIGraphicsImageRenderer(size: CGSize(width: 10, height: 10)).image { context in
            UIColor.red.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 10, height: 10))
        }
        let identifier = KingfisherParsedOptionsInfo(ArtworkSizing.processingOptions(side: side)).processor.identifier
        defer { ImageCache.default.removeImage(forKey: url.cacheKey, processorIdentifier: identifier) }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            ImageCache.default.store(
                cover, original: cover.pngData(), forKey: url.cacheKey,
                processorIdentifier: identifier, toDisk: true
            ) { _ in continuation.resume() }
        }
        ImageCache.default.clearMemoryCache()

        let view = UIImageView()
        view.setArtwork(url, title: "Z", side: side)
        let placeholder = ArtworkPlaceholder.image(for: "Z")
        let shown = try #require(view.image)
        #expect(shown !== placeholder, "the placeholder flashed on a disk hit")
        #expect(shown.size.width < placeholder.size.width, "not the cached cover: \(shown.size)")
        view.kf.cancelDownloadTask()
    }

    @Test("Cover sides bucket into three sizes")
    func artworkBuckets() {
        for side: CGFloat in [36, 44, 56, 64] { #expect(ArtworkSizing.bucket(for: side) == 64) }
        for side: CGFloat in [88, 120, 160] { #expect(ArtworkSizing.bucket(for: side) == 160) }
        for side: CGFloat in [161, 340, 400] { #expect(ArtworkSizing.bucket(for: side) == 400) }
    }
}

// MARK: - P1.1 chrome rows have their real height on the first pass

@MainActor
@Suite(.serialized)
struct InboxChromeLayoutTests {

    private final class Source: NSObject, UICollectionViewDataSource {
        let shelf = ShowsShelfView()
        let strip = CategoryStripView()
        func numberOfSections(in collectionView: UICollectionView) -> Int { 3 }
        func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
            section == 2 ? 3 : 1
        }
        func collectionView(
            _ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath
        ) -> UICollectionViewCell {
            switch indexPath.section {
            case 0:
                let cell = collectionView.dequeueReusableCell(withReuseIdentifier: ChromeHostingCell.reuseIdentifier, for: indexPath)
                (cell as? ChromeHostingCell)?.host(shelf)
                return cell
            case 1:
                let cell = collectionView.dequeueReusableCell(withReuseIdentifier: ChromeHostingCell.reuseIdentifier, for: indexPath)
                (cell as? ChromeHostingCell)?.host(strip)
                return cell
            default:
                let cell = collectionView.dequeueReusableCell(withReuseIdentifier: InboxEpisodeCardCell.reuseIdentifier, for: indexPath)
                (cell as? InboxEpisodeCardCell)?.configure(InboxCardContent(
                    title: "Episode", showName: "Show", metaText: "1d ago",
                    descriptionHTML: nil, imageURL: nil, descriptionPlainText: "A description"
                ))
                return cell
            }
        }
    }

    @Test("With shelf and strip, the first card sits where it settles")
    func firstLayoutCardMinYIsSettled() async throws {
        let scene = try #require(
            UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first,
            "self-sizing needs a connected scene"
        )
        let window = UIWindow(windowScene: scene)
        window.windowLevel = .alert + 1
        defer { window.isHidden = true; window.rootViewController = nil }

        let layout = UICollectionViewCompositionalLayout { index, environment in
            switch index {
            case 0: return InboxPageViewController.chromeSection(height: ShowsShelfLayout.itemSide, bottomInset: InboxEpisodeCardCell.verticalGap)
            case 1: return InboxPageViewController.chromeSection(height: CategoryStripView.chipHeight, bottomInset: InboxEpisodeCardCell.verticalGap)
            default:
                var config = UICollectionLayoutListConfiguration(appearance: .plain)
                config.showsSeparators = false
                config.backgroundColor = .clear
                return NSCollectionLayoutSection.list(using: config, layoutEnvironment: environment)
            }
        }
        let collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        let source = Source()
        source.strip.configure(categories: ["news", "comedy"], selected: nil)
        collectionView.register(ChromeHostingCell.self, forCellWithReuseIdentifier: ChromeHostingCell.reuseIdentifier)
        collectionView.register(InboxEpisodeCardCell.self, forCellWithReuseIdentifier: InboxEpisodeCardCell.reuseIdentifier)
        collectionView.dataSource = source
        let host = UIViewController()
        host.view.addSubview(collectionView)
        collectionView.frame = CGRect(x: 0, y: 0, width: 390, height: 1200)
        window.frame = CGRect(x: 0, y: 0, width: 390, height: 1200)
        window.rootViewController = host
        window.isHidden = false

        func frames() -> (shelf: CGRect, card: CGRect)? {
            guard let shelf = collectionView.cellForItem(at: IndexPath(item: 0, section: 0))?.frame,
                  let card = collectionView.cellForItem(at: IndexPath(item: 0, section: 2))?.frame
            else { return nil }
            return (shelf, card)
        }
        collectionView.layoutIfNeeded()
        let first = try #require(frames())
        #expect(first.shelf.height == ShowsShelfLayout.itemSide, "shelf row is \(first.shelf.height) pt")

        try await Task.sleep(nanoseconds: 300_000_000)
        collectionView.reloadData()
        collectionView.layoutIfNeeded()
        let settled = try #require(frames())
        #expect(first.card.minY == settled.card.minY, "card moved \(settled.card.minY - first.card.minY) pt after reload")
    }
}

// MARK: - P1.2 list diff decision

struct InboxListDiffTests {

    private func plan(_ old: [String?], _ new: [String?], sections: Bool = true) -> InboxListDiff.Plan {
        InboxListDiff.plan(old: old, new: new, sectionsUnchanged: sections)
    }

    @Test("Rows that only appeared or left become inserts and removes")
    func insertsAndRemoves() {
        #expect(plan(["a", "b", "c"], ["n1", "n2", "a", "b", "c"]) == .batch(removes: [], inserts: [0, 1]))
        #expect(plan(["a", "b", "c"], ["a", "c"]) == .batch(removes: [1], inserts: []))
        #expect(plan(["a", "b", "c"], ["n", "a", "c", "z"]) == .batch(removes: [1], inserts: [0, 3]))
    }

    @Test("Identical lists need nothing")
    func unchanged() {
        #expect(plan(["a", "b"], ["a", "b"]) == .unchanged)
    }

    @Test("Everything else falls back to a reload")
    func fallbacks() {
        #expect(plan(["a", "b"], ["a", "n"], sections: false) == .reload, "sections changed")
        #expect(plan([], ["a"]) == .reload, "empty before")
        #expect(plan(["a"], []) == .reload, "empty after")
        #expect(plan(["a", nil], ["a", "b"]) == .reload, "nil url before")
        #expect(plan(["a", "b"], ["a", nil]) == .reload, "nil url after")
        #expect(plan(["a", "a"], ["a", "b"]) == .reload, "duplicate before")
        #expect(plan(["a", "b"], ["b", "b"]) == .reload, "duplicate after")
        #expect(plan(["a", "b", "c"], ["a", "c", "b"]) == .reload, "a row moved")
    }
}

// MARK: - P1.3 the strip keeps its buttons when nothing changed

@MainActor
struct CategoryStripStabilityTests {

    private func buttons(in strip: CategoryStripView) -> [UIButton] {
        func walk(_ view: UIView) -> [UIButton] {
            (view as? UIButton).map { [$0] } ?? view.subviews.flatMap(walk)
        }
        return walk(strip)
    }

    @Test("Configuring with the same categories and selection keeps the same buttons")
    func sameInputKeepsButtons() {
        let strip = CategoryStripView()
        strip.configure(categories: ["news,comedy", "news"], selected: nil)
        let before = buttons(in: strip)
        #expect(before.count == 3)
        strip.configure(categories: ["comedy", "news"], selected: nil)
        let after = buttons(in: strip)
        #expect(before.count == after.count && zip(before, after).allSatisfy { $0 === $1 }, "buttons were rebuilt")
        // A different set rebuilds; a selection change alone keeps them.
        strip.configure(categories: ["news"], selected: nil)
        #expect(buttons(in: strip).count == 2)
        let two = buttons(in: strip)
        strip.configure(categories: ["news"], selected: "news")
        #expect(zip(two, buttons(in: strip)).allSatisfy { $0 === $1 })
        #expect(strip.currentSelection == "news")
    }
}

// MARK: - P1.4 loading rule

@MainActor
struct LoadingRuleTests {

    @Test("Discover page: what each state shows")
    func contentLoadReducer() {
        func d(_ content: Bool, _ fetching: Bool, _ failed: Bool, _ due: Bool) -> ContentLoadDisplay {
            ContentLoadReducer.display(hasContent: content, isFetching: fetching, updateFailed: failed, skeletonDue: due)
        }
        // Rows stay through a refresh and through a failed one.
        #expect(d(true, true, false, false) == .content)
        #expect(d(true, true, false, true) == .content)
        #expect(d(true, false, false, false) == .content)
        #expect(d(true, false, true, false) == .contentWithRetry)
        // Nothing to show: blank inside 300 ms, skeleton after, empty state when done.
        #expect(d(false, true, false, false) == .blank)
        #expect(d(false, true, false, true) == .skeleton)
        #expect(d(false, false, true, true) == .emptyError)
        #expect(d(false, false, false, false) == .emptyError)
    }

    @Test("Channel body: rows at once, skeleton only with a title after the delay")
    func channelBodyReducer() {
        func d(_ rows: Bool, _ loading: Bool, _ title: Bool, _ due: Bool) -> ChannelBodyDisplay {
            ChannelBodyReducer.display(hasEpisodes: rows, isLoading: loading, hasTitle: title, skeletonDue: due)
        }
        #expect(d(true, true, true, false) == .rows, "inbox rows show while the fetch runs")
        #expect(d(false, true, true, false) == .blank)
        #expect(d(false, true, true, true) == .skeleton)
        #expect(d(false, true, false, true) == .blank, "no title: the full-page spinner owns loading")
        #expect(d(false, false, true, true) == .empty)
    }

    @Test("The Discover cache round-trips and tells when a list changed")
    func cacheRoundTrip() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("DiscoverCacheTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = DiscoverChannelCache(directory: directory)
        #expect(cache.load(categoryID: "1301", country: "us") == nil)

        let rows = [
            SubscriptionRow(rssFeedUrl: "https://a/feed", title: "A", description: "about a", imageUrl: "https://a/i.png", author: "Ann"),
            SubscriptionRow(rssFeedUrl: "https://b/feed", title: "B"),
        ]
        cache.save(rows, categoryID: "1301", country: "us")
        let loaded = try #require(cache.load(categoryID: "1301", country: "us"))
        #expect(!DiscoverChannelCache.differs(loaded, rows))
        #expect(cache.load(categoryID: "1301", country: "cn") == nil, "per country")
        #expect(cache.load(categoryID: "9999", country: "us") == nil, "per category")

        var changed = rows
        changed[1].title = "B2"
        #expect(DiscoverChannelCache.differs(loaded, changed))
        #expect(DiscoverChannelCache.differs(loaded, Array(rows.dropLast())))
    }

    @Test("The delay fires after the threshold and not when cancelled first")
    func loadingDelay() async throws {
        let delay = LoadingDelay()
        var fired = 0
        delay.start(after: 0.05) { fired += 1 }
        try await Task.sleep(nanoseconds: 150_000_000)
        #expect(fired == 1 && delay.isDue)

        delay.cancel()
        #expect(!delay.isDue)
        delay.start(after: 0.05) { fired += 1 }
        delay.cancel()
        try await Task.sleep(nanoseconds: 150_000_000)
        #expect(fired == 1, "a cancelled delay must not fire")
        #expect(LoadingDelay.threshold == 0.3)
    }

    @Test("Skeleton rows have the real row heights")
    func skeletonHeights() {
        let podcast = PodcastCardCell(frame: CGRect(x: 0, y: 0, width: 358, height: 88))
        podcast.configureSkeleton()
        let podcastHeight = podcast.contentView.systemLayoutSizeFitting(
            CGSize(width: 358, height: UIView.layoutFittingCompressedSize.height),
            withHorizontalFittingPriority: .required, verticalFittingPriority: .fittingSizeLevel
        ).height

        let real = PodcastCardCell(frame: CGRect(x: 0, y: 0, width: 358, height: 88))
        real.configure(PodcastCardContent(
            rssFeedURL: "u", title: "A title",
            description: String(repeating: "A long description that wraps onto two lines. ", count: 3), imageURL: nil
        ))
        let realHeight = real.contentView.systemLayoutSizeFitting(
            CGSize(width: 358, height: UIView.layoutFittingCompressedSize.height),
            withHorizontalFittingPriority: .required, verticalFittingPriority: .fittingSizeLevel
        ).height
        #expect(podcastHeight == realHeight, "skeleton \(podcastHeight) vs real \(realHeight)")

        let episode = ChannelEpisodeRowCell(frame: CGRect(x: 0, y: 0, width: 358, height: 70))
        episode.configureSkeleton()
        let episodeHeight = episode.contentView.systemLayoutSizeFitting(
            CGSize(width: 358, height: UIView.layoutFittingCompressedSize.height),
            withHorizontalFittingPriority: .required, verticalFittingPriority: .fittingSizeLevel
        ).height
        #expect(episodeHeight == ChannelEpisodeRowCell.minimumHeight, "channel skeleton row is \(episodeHeight)")
    }
}

// MARK: - P2.0 the data commits inside the batch

@MainActor
@Suite(.serialized)
struct InboxBatchCommitTests {

    private final class Model: NSObject, UICollectionViewDataSource {
        var rows: [String] = []
        func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int { rows.count }
        func collectionView(
            _ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath
        ) -> UICollectionViewCell {
            let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "c", for: indexPath)
            let label = (cell.contentView.subviews.first as? UILabel) ?? {
                let label = UILabel()
                label.frame = CGRect(x: 0, y: 0, width: 300, height: 40)
                cell.contentView.addSubview(label)
                return label
            }()
            label.text = rows[indexPath.item]
            return cell
        }
    }

    private func host(rows: [String]) throws -> (UICollectionView, Model, UIWindow) {
        let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.windowLevel = .alert + 1
        let layout = UICollectionViewCompositionalLayout { _, environment in
            var config = UICollectionLayoutListConfiguration(appearance: .plain)
            config.showsSeparators = false
            return NSCollectionLayoutSection.list(using: config, layoutEnvironment: environment)
        }
        let collectionView = UICollectionView(frame: CGRect(x: 0, y: 0, width: 390, height: 800), collectionViewLayout: layout)
        collectionView.register(UICollectionViewCell.self, forCellWithReuseIdentifier: "c")
        let model = Model()
        model.rows = rows
        collectionView.dataSource = model
        let controller = UIViewController()
        controller.view.addSubview(collectionView)
        window.rootViewController = controller
        window.isHidden = false
        collectionView.layoutIfNeeded()
        return (collectionView, model, window)
    }

    private func texts(_ collectionView: UICollectionView, _ model: Model) -> [String?] {
        (0..<model.rows.count).map {
            (collectionView.cellForItem(at: IndexPath(item: $0, section: 0))?.contentView.subviews.first as? UILabel)?.text
        }
    }

    private func apply(
        _ new: [String], on collectionView: UICollectionView, model: Model, animated: Bool,
        gate: UpdateGate? = nil, completion: @escaping () -> Void = {}
    ) {
        guard case .batch(let removes, let inserts) = InboxListDiff.plan(
            old: model.rows, new: new, sectionsUnchanged: true
        ) else { Issue.record("expected a batch"); return }
        gate?.begin()
        InboxBatchUpdate.apply(
            to: collectionView, section: 0, removes: removes, inserts: inserts, animated: animated,
            commit: { model.rows = new },
            completion: { completion(); gate?.end() }
        )
    }

    @Test("A pending layout pass does not see post-change counts")
    func pendingLayoutBeforeBatch() async throws {
        let (collectionView, model, window) = try host(rows: ["a", "b", "c", "d", "e"])
        defer { window.isHidden = true; window.rootViewController = nil }
        collectionView.setNeedsLayout()
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            apply(["x", "a", "c", "e", "y"], on: collectionView, model: model, animated: false) { continuation.resume() }
        }
        collectionView.layoutIfNeeded()
        #expect(collectionView.numberOfItems(inSection: 0) == 5)
        #expect(texts(collectionView, model) == ["x", "a", "c", "e", "y"])
    }

    @Test("A second update while the first still animates waits and lands consistently")
    func secondUpdateWhileAnimating() async throws {
        let (collectionView, model, window) = try host(rows: ["a", "b", "c", "d", "e"])
        defer { window.isHidden = true; window.rootViewController = nil }
        let gate = UpdateGate()
        var firstDone = false
        apply(["a", "c", "d", "e"], on: collectionView, model: model, animated: true, gate: gate) { firstDone = true }
        // The first batch is animating: park the second, with a layout pass pending.
        collectionView.setNeedsLayout()
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            gate.submitOrDefer {
                #expect(firstDone, "the second update must wait for the first")
                self.apply(["n", "a", "d", "e", "m"], on: collectionView, model: model, animated: true) { continuation.resume() }
            }
        }
        collectionView.layoutIfNeeded()
        #expect(model.rows == ["n", "a", "d", "e", "m"])
        #expect(collectionView.numberOfItems(inSection: 0) == 5)
        #expect(texts(collectionView, model) == ["n", "a", "d", "e", "m"])
    }

    @Test("The gate keeps only the newest parked work")
    func gateNewestWins() {
        let gate = UpdateGate()
        var ran: [Int] = []
        gate.begin()
        gate.submitOrDefer { ran.append(1) }
        gate.submitOrDefer { ran.append(2) }
        #expect(ran.isEmpty)
        gate.end()
        #expect(ran == [2] && !gate.isBusy)
        gate.submitOrDefer { ran.append(3) }
        #expect(ran == [2, 3])
    }
}

// MARK: - P2.1 the Channel header colour

@MainActor
struct ChannelHeaderColorTests {

    private func gradient(in header: ChannelHeaderView) -> CAGradientLayer? {
        header.layer.sublayers?.compactMap { $0 as? CAGradientLayer }.first
    }

    @Test("The first colour is set outright; a later one crossfades")
    func crossfadeOnlyWhenColourLands() throws {
        let header = ChannelHeaderView(frame: CGRect(x: 0, y: 0, width: 390, height: 300))
        let channel = SubscriptionRow(rssFeedUrl: "u", title: "T")
        let known = UIColor(red: 0.2, green: 0.5, blue: 0.3, alpha: 1)
        header.configure(channel: channel, dominant: known)
        let layer = try #require(gradient(in: header))
        #expect(layer.animation(forKey: "headerColorFade") == nil, "a known colour must not fade")

        header.configure(channel: channel, dominant: known)
        #expect(layer.animation(forKey: "headerColorFade") == nil, "an unchanged colour must not fade")

        header.configure(channel: channel, dominant: UIColor(red: 0.8, green: 0.2, blue: 0.2, alpha: 1))
        if Motion.reduceMotion {
            #expect(layer.animation(forKey: "headerColorFade") == nil)
        } else {
            let fade = try #require(layer.animation(forKey: "headerColorFade") as? CABasicAnimation)
            #expect(fade.duration == Motion.standard)
        }
    }
}

// MARK: - P2.2 the player backdrop keeps its image while the next loads

@MainActor
@Suite(.serialized)
struct PlayerBackdropTests {

    private func store(_ color: UIColor, side: CGFloat, key: URL) async -> UIImage {
        let image = UIGraphicsImageRenderer(size: CGSize(width: side, height: side)).image { context in
            color.setFill(); context.fill(CGRect(x: 0, y: 0, width: side, height: side))
        }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            ImageCache.default.store(image, original: image.pngData(), forKey: key.cacheKey, toDisk: true) { _ in
                continuation.resume()
            }
        }
        return image
    }

    @Test("Changing the backdrop URL never shows an empty frame")
    func keepsOldImageUntilNewIsReady() async throws {
        let first = try #require(URL(string: "https://example.invalid/p2-backdrop-a-\(UUID().uuidString).png"))
        let second = try #require(URL(string: "https://example.invalid/p2-backdrop-b-\(UUID().uuidString).png"))
        _ = await store(.red, side: 10, key: first)
        _ = await store(.blue, side: 20, key: second)
        defer {
            ImageCache.default.removeImage(forKey: first.cacheKey)
            ImageCache.default.removeImage(forKey: second.cacheKey)
        }
        ImageCache.default.clearMemoryCache()

        let view = UIImageView(frame: CGRect(x: 0, y: 0, width: 100, height: 100))
        view.setBackdrop(first)
        for _ in 0..<100 where view.image == nil { try await Task.sleep(nanoseconds: 20_000_000) }
        let shownFirst = try #require(view.image, "first backdrop never loaded")

        ImageCache.default.clearMemoryCache()   // force the disk path: the load is not instant
        view.setBackdrop(second)
        #expect(view.image != nil, "the backdrop went empty while the next image loaded")
        #expect(view.image === shownFirst || view.image?.size == shownFirst.size, "the old backdrop was replaced early")

        for _ in 0..<100 where view.image?.size == shownFirst.size { try await Task.sleep(nanoseconds: 20_000_000) }
        #expect(view.image?.size != shownFirst.size, "the new backdrop never arrived")
    }
}
