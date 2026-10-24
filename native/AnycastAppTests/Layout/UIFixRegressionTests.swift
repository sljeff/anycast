import UIKit
import Testing
import AnycastKit
@testable import Anycast

/// Regression guards for the shipped-UI defects fixed in this change set
/// (each test names the user-visible symptom it pins):
///
/// 1. Player main page collapsed at the top with one dead gap above the
///    page tab (now one 28 pt rhythm below the cover with the slack above it).
/// 2. Player progress thumb/glow halo rendering as a dark ring over the
///    track (removed: the played segment's rounded head is the indicator)
///    and the square-cornered stub the head became during the first
///    seconds of playback (the head is now always a full semicircle).
/// 3. (Retired with the V2 IA flip — Discover left the tab shell, 09
///    §3.5; the ChipTabBarView indicator guard it motivated lives on
///    through SearchPage's use.)
/// 4. Playlist card progress strip running through the card's rounded
///    corners.
/// 5. Playlist Detail sheet play button rendered as an empty white circle
///    (blank strip icon reused outside the strip's live overlay).
/// 6. Card expand leaving item heights un-resized (strip overflowing
///    neighbor cards) and later taps failing to expand — Inbox went
///    strip-less (09 §7a-C1, case 6a guards the native wiring); the
///    resize walk now runs on the playlist list, which keeps its strip.
/// 7. Mini player nested capsule-in-capsule when hosted by the iOS 26+
///    tab accessory (the system glass must be the only chrome).
/// 8. Channel subscribe button spinning through the feed fetch and
///    rendering as a pointed lens instead of a capsule.
///
/// Runs against the live shell with the seeded fixture; skips when the
/// shell or the seed is absent. Serialized: the suite drives the SHARED
/// key window.
@MainActor
@Suite(.serialized)
struct UIFixRegressionTests {

    // MARK: - Player page distribution (1) + thumb height (2)

    @Test("Player main page: square column-width cover, 28 pt rhythm, centered play")
    func playerPageDistribution() async throws {
        guard let context = await Self.liveContext(),
              let window = Self.keyWindow() else {
            print("[uifix] shell not ready; skipping"); return
        }
        guard let presenter = await Self.settledTopPresenter(in: window) ?? window.rootViewController else {
            print("[uifix] shell not ready; skipping"); return
        }
        PlayerPageContainer.present(from: presenter, context: context)
        try await Self.settle(window, seconds: 1.2)
        defer {
            window.rootViewController?.topMostPresented().dismiss(animated: false)
        }

        guard let player = Self.find(PlayerPageContainer.self, in: window.rootViewController),
              let main = Self.find(PlayerMainPageViewController.self, in: player) else {
            Issue.record("player sheet did not present"); return
        }
        guard let page = main.view else {
            Issue.record("player main page has no view"); return
        }
        // Generous settle: the balance is measured to 2 pt — on a busy
        // simulator a mid-presentation snapshot reads compressed gaps.
        try await Self.settle(window, seconds: 2.0)

        guard let cover = Self.firstView(
            in: page, where: { ($0 as? UIImageView)?.accessibilityLabel == "Episode artwork" }
        ), let titleRow = Self.firstView(
            in: page, where: { $0.accessibilityLabel == "Share episode" }
        )?.superview, let progress = Self.firstView(
            in: page, where: { $0 is PlayerProgressBarView }
        ), let playPause = Self.firstView(
            in: page, where: { ($0 as? UIButton)?.accessibilityLabel == "Play or pause" }
        ) else {
            Issue.record("player main page blocks not found"); return
        }
        guard let bottomStack = progress.superview else {
            Issue.record("scrubber has no host stack"); return
        }

        func frameInPage(_ v: UIView) -> CGRect { page.convert(v.bounds, from: v) }
        let coverFrame = frameInPage(cover)
        let titleFrame = frameInPage(titleRow)
        let bottomFrame = frameInPage(bottomStack)
        let playFrame = frameInPage(playPause)

        // Square, at most the 24 pt content column's width, horizontally centered.
        #expect(abs(coverFrame.width - coverFrame.height) < 1.5, "cover is not square: \(coverFrame)")
        #expect(coverFrame.width <= page.bounds.width - 48 + 0.5, "cover exceeds the column: \(coverFrame.width)")
        #expect(abs(coverFrame.midX - page.bounds.midX) < 1, "cover is off center")

        // One 28 pt VISIBLE rhythm (subtitle → track, labels → transport,
        // transport → selector); the frames carry the hidden slack, so the
        // frame gaps are 28 - 24 and 28 - 13 (the page ends at the selector's
        // top). Slack sits above the cover.
        let topGap = coverFrame.minY
        let middleGap = bottomFrame.minY - titleFrame.maxY
        let bottomGap = page.bounds.maxY - bottomFrame.maxY
        #expect(topGap >= 24 - 0.5, "content is crammed against the sheet top: \(topGap)")
        #expect(abs(middleGap - 4) < 1.0, "title → scrubber frame gap is \(middleGap), expected 4")
        #expect(abs(bottomGap - 15) < 1.0, "transport → selector frame gap is \(bottomGap), expected 15")

        // Play sits exactly on the page's center line.
        #expect(abs(playFrame.midX - page.bounds.midX) < 1, "play is off center: \(playFrame.midX)")
        await Self.capture(window, name: "uifix-player-page")
    }

    @Test("Progress bar has no thumb/glow layers; the played head spans the full track")
    func progressBarThumbRemoved() {
        let bar = PlayerProgressBarView()
        bar.frame = CGRect(x: 0, y: 0, width: 320, height: 60)
        bar.layoutIfNeeded()

        // Layer order per init: track, buffered, played — inside the bar
        // container, and nothing else.
        let shapes = (bar.barContainer.layer.sublayers ?? []).compactMap { $0 as? CAShapeLayer }
        #expect(shapes.count == 3,
                "expected exactly track/buffered/played shape layers, found \(shapes.count)")

        // Fraction 1: the played capsule reaches the trailing cap; the
        // head travels the full width (no thumb inset resurrecting it).
        bar.update(positionMilliseconds: 120_000, bufferedMilliseconds: 120_000, durationMilliseconds: 120_000)
        bar.layoutIfNeeded()
        guard let playedBox = shapes[2].path?.boundingBox else {
            Issue.record("played layer has no path at full position"); return
        }
        #expect(abs(playedBox.width - 320) < 0.5,
                "played head stops short of the trailing cap: \(playedBox.width)")

        // Fraction 0: nothing is drawn (no zero-width nub).
        bar.update(positionMilliseconds: 0, bufferedMilliseconds: 0, durationMilliseconds: 120_000)
        bar.layoutIfNeeded()
        #expect(shapes[2].path == nil || shapes[2].path!.isEmpty,
                "a visible remnant is drawn at position zero")
    }

    @Test("Progress bar head stays round at the start of playback")
    func progressBarRoundHeadAtStart() {
        let bar = PlayerProgressBarView()
        bar.frame = CGRect(x: 0, y: 0, width: 320, height: 60)
        bar.layoutIfNeeded()

        // ~1% in: the fill rect is a few points wide, but the unioned head
        // circle keeps the path a full track-height (12 pt) wide — a plain rounded rect
        // clamps its corner radius to width/2 and rendered a square stub.
        bar.update(positionMilliseconds: 1_200, bufferedMilliseconds: 0, durationMilliseconds: 120_000)
        bar.layoutIfNeeded()
        let shapes = (bar.barContainer.layer.sublayers ?? []).compactMap { $0 as? CAShapeLayer }
        guard let playedBox = shapes[2].path?.boundingBox else {
            Issue.record("played layer has no path near position zero"); return
        }
        #expect(abs(playedBox.width - 12) < 0.5,
                "narrow played segment is \(playedBox.width) pt wide — the head is not a full circle")
        #expect(playedBox.minX < 0,
                "the head circle should extend past the track's leading cap (the container clips it)")

        // The container does the clipping (corner radius == half the bar).
        #expect(bar.barContainer.clipsToBounds, "bar container does not clip")
        #expect(abs(bar.barContainer.layer.cornerRadius - 6) < 0.5,
                "bar container corner radius is not a capsule")
    }

    @Test("Rendered progress head follows the capsule contour at the start")
    func progressBarRenderedRoundHead() throws {
        let bar = PlayerProgressBarView()
        bar.frame = CGRect(x: 0, y: 0, width: 320, height: 60)
        bar.layoutIfNeeded()
        // width 25: the head circle spans the leading cap and ends in a
        // round head at x≈25. A square-cornered stub would light the bar's
        // top/bottom edges at the left; the clipped round head does not.
        bar.update(positionMilliseconds: 9_375, bufferedMilliseconds: 0, durationMilliseconds: 120_000)
        bar.layoutIfNeeded()

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: bar.bounds.size, format: format)
        let image = renderer.image { bar.layer.render(in: $0.cgContext) }
        guard let cg = image.cgImage else {
            Issue.record("render produced no CGImage"); return
        }
        var pixels = [UInt8](repeating: 0, count: 320 * 60 * 4)
        pixels.withUnsafeMutableBytes { raw in
            guard let ctx = CGContext(
                data: raw.baseAddress, width: 320, height: 60, bitsPerComponent: 8,
                bytesPerRow: 320 * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return }
            ctx.draw(cg, in: CGRect(x: 0, y: 0, width: 320, height: 60))
        }
        func channels(_ x: Int, _ y: Int) -> (Int, Int, Int) {
            let base = y * 320 * 4 + x * 4
            return (Int(pixels[base]), Int(pixels[base + 1]), Int(pixels[base + 2]))
        }
        func isWhite(_ x: Int, _ y: Int) -> Bool {
            let (r, g, b) = channels(x, y)
            return r + g + b > 700
        }

        // The resting 6 pt track is centered at y 20 in the top 40 pt touch
        // band (times sit below); the head ends at x≈25.
        #expect(isWhite(15, 20), "head mid-height not filled: px=\(channels(15, 20))")
        #expect(!isWhite(2, 2), "white reaches the bar's top-left — square stub or clip leak: px=\(channels(2, 2))")
        #expect(!isWhite(2, 26), "white reaches the bar's bottom-left — square stub or clip leak: px=\(channels(2, 26))")
        #expect(!isWhite(35, 20), "white extends past the round head: px=\(channels(35, 20))")

        // Diagnostic capture (same convention as capture()): the bar at a
        // start-of-playback fraction, for offline visual inspection.
        if let data = image.pngData() {
            let url = URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent("uifix-progress-start.png")
            try? data.write(to: url)
            print("[uifix] wrote \(url.path)")
        }
    }

    // MARK: - Mini player chrome (7)

    @Test("Mini player: one silhouette — accessory hosts no own chrome, capsule paints opaque sand")
    func miniPlayerSingleChrome() async {
        guard let context = await Self.liveContext() else {
            print("[uifix] shell not ready; skipping"); return
        }
        // (style, expected capsule background alpha, expected side margin)
        let cases: [(PlayerBarView.HostingStyle, CGFloat, CGFloat)] = [
            (.systemAccessory, 0, 0),
            (.capsule, 1, 0),
        ]
        for (style, expectedAlpha, expectedMargin) in cases {
            let bar = context.makePlayerBar(style: style)
            bar.frame = CGRect(x: 0, y: 0, width: 320, height: 58)
            bar.layoutIfNeeded()
            guard let capsule = bar.subviews.first else {
                Issue.record("\(style): capsule container missing"); continue
            }
            var alpha: CGFloat = 1
            capsule.backgroundColor?.getWhite(nil, alpha: &alpha)
            #expect(abs(alpha - expectedAlpha) < 0.011,
                    "\(style): capsule background alpha \(alpha), expected \(expectedAlpha)")
            #expect(abs(capsule.frame.minX - expectedMargin) < 0.5,
                    "\(style): leading margin \(capsule.frame.minX), expected \(expectedMargin)")
            #expect(abs(capsule.frame.maxX - (320 - expectedMargin)) < 0.5,
                    "\(style): trailing edge \(capsule.frame.maxX), expected \(320 - expectedMargin)")
            // Same capsule contour in both styles, so the bar reads as one
            // element on sheet-hosted screens and in the system accessory.
            #expect(abs(capsule.layer.cornerRadius - 29) < 0.5,
                    "\(style): corner radius \(capsule.layer.cornerRadius) is not a capsule (29)")
        }
    }

    // MARK: - Card progress meter (4)

    private func meter(in cell: EpisodeCardCell) -> UIView? {
        func find(_ view: UIView) -> UIView? {
            if view.accessibilityIdentifier == "episode-card-meter" { return view }
            for subview in view.subviews { if let hit = find(subview) { return hit } }
            return nil
        }
        return find(cell)
    }

    private func card(showsProgress: Bool, fraction: Double, rightText: String) -> EpisodeCardCell {
        let cell = EpisodeCardCell(frame: CGRect(x: 0, y: 0, width: 370, height: EpisodeCardCell.cardRowHeight))
        cell.configure(
            EpisodeCardContent(
                title: "Episode", channelTitle: "Channel", rightText: rightText,
                descriptionHTML: nil, imageURL: nil,
                showsProgress: showsProgress,
                progressFraction: fraction,
                descriptionPlainText: "Description"
            ),
            actions: []
        )
        cell.layoutIfNeeded()
        return cell
    }

    @Test("Card progress: a 36 × 4 meter inside the plate, only once played")
    func cardProgressMeter() {
        let played = card(showsProgress: true, fraction: 0.36, rightText: "32m left")
        let shown = meter(in: played)
        #expect(shown?.isHidden == false)
        #expect(shown?.bounds.size == CGSize(width: 36, height: 4))
        #expect(shown?.accessibilityLabel == "36 percent played")
        if let shown {
            let frame = shown.convert(shown.bounds, to: played)
            #expect(played.bounds.contains(frame), "meter sits inside the card")
        }

        let unplayed = card(showsProgress: true, fraction: 0, rightText: "42m")
        #expect(meter(in: unplayed)?.isHidden == true, "an unplayed episode shows its duration only")

        let plain = card(showsProgress: false, fraction: 0.5, rightText: "4d ago · 30m")
        #expect(meter(in: plain)?.isHidden == true, "non-playlist cards never show the meter")

        // Live progress turns the meter on for the current episode.
        unplayed.updateLiveProgress(fraction: 0.1, rightText: "38m left")
        #expect(meter(in: unplayed)?.isHidden == false)
    }

    // MARK: - Playlist Detail play button (5)

    @Test("Playlist Detail sheet: play action button carries a real icon")
    func playlistDetailPlayButtonIcon() async throws {
        guard let context = await Self.liveContext(),
              let window = Self.keyWindow() else {
            print("[uifix] shell not ready; skipping"); return
        }
        let queue = (try? await context.database.playlistRepository()
            .listEpisodes(playlistId: ChannelPlaylistLogic.defaultPlaylistID)) ?? []
        guard queue.count >= 1 else {
            print("[uifix] seeded playlist empty; skipping"); return
        }

        let list = PlaylistEpisodeListViewController(
            context: context, playlistId: ChannelPlaylistLogic.defaultPlaylistID
        )
        list.modalPresentationStyle = .pageSheet
        let presenter = await Self.settledTopPresenter(in: window) ?? window.rootViewController
        presenter?.present(list, animated: false)
        try await Self.settle(window, seconds: 1.5)
        // Tear down from the PRESENTING side: `list.dismiss` only removes
        // the topmost presentation ABOVE the list when something was
        // presented from it (the Detail sheet below taps a cover) — the
        // list itself then stays up and silently swallows the next test's
        // presentation attempt.
        defer { presenter?.dismiss(animated: false) }

        guard let collection = Self.firstView(in: list.view, where: { $0 is UICollectionView })
                as? UICollectionView else {
            Issue.record("playlist collection not found"); return
        }
        guard let path = collection.indexPathsForVisibleItems.sorted(by: { $0.item < $1.item }).first,
              let cell = collection.cellForItem(at: path) as? EpisodeCardCell else {
            Issue.record("playlist card not visible"); return
        }
        cell.onCoverTap?()
        try await Self.settle(window, seconds: 1.2)

        guard let detail = Self.find(DetailViewController.self, in: window.rootViewController) else {
            Issue.record("detail sheet did not present"); return
        }
        let playButtons = detail.view.subviewsRecursive()
            .compactMap { $0 as? UIButton }
            .filter { $0.accessibilityIdentifier == "detail-play" }
        guard let play = playButtons.first else {
            Issue.record("detail play button not found"); return
        }
        let iconSize = (play.configuration?.image ?? play.currentImage)?.size ?? .zero
        #expect(iconSize.width > 1 && iconSize.height > 1,
                "detail play button icon is blank (\(iconSize))")
        await Self.capture(window, name: "uifix-detail-play-icon")
    }

    // MARK: - Inbox native-first card interactions (6a)

    @Test("Inbox card: tap opens Detail; context menu + more button carry the 3 actions")
    func inboxNativeCardInteractions() async throws {
        guard let context = await Self.liveContext(),
              let window = Self.keyWindow() else {
            print("[uifix] shell not ready; skipping"); return
        }
        context.tabs.select(0)
        try await Self.settle(window, seconds: 1.5)

        // Locate the first visible card wherever the chrome sections put
        // it (the embedded Inbox hides its own header).
        guard let inbox = Self.find(InboxPageViewController.self, in: window.rootViewController),
              let collection = Self.firstView(in: inbox.view, where: { $0 is UICollectionView })
                as? UICollectionView,
              let path = collection.indexPathsForVisibleItems.sorted().first(where: {
                  collection.cellForItem(at: $0) is InboxEpisodeCardCell
              }) else {
            print("[uifix] seeded inbox missing; skipping"); return
        }
        guard let cell = collection.cellForItem(at: path) as? InboxEpisodeCardCell else {
            Issue.record("inbox card not visible"); return
        }

        // VoiceOver parity: the context-menu payload is mirrored onto the
        // card as custom actions (09 §7a-C1).
        #expect(cell.menuActions.count == 3,
                "menu actions not mirrored (count \(cell.menuActions.count))")

        // The more button pulls the same menu down (批次1).
        let moreTitles = cell.moreButton.menu?.children.compactMap { ($0 as? UIAction)?.title }
        #expect(moreTitles == ["Play", "Add to playlist", "Remove from inbox"],
                "more menu children \(moreTitles ?? [])")

        // The long-press menu itself: Play / Add to playlist / Remove from inbox.
        guard let menu = inbox.contextMenu(at: path) else {
            Issue.record("no context menu for inbox card 0"); return
        }
        let titles = menu.children.compactMap { ($0 as? UIAction)?.title }
        #expect(titles == ["Play", "Add to playlist", "Remove from inbox"],
                "menu children \(titles)")

        // Leading swipe adds to the playlist (UI kit swipe right).
        let leading = inbox.leadingSwipeActions(at: path)?.actions ?? []
        #expect(leading.count == 1 && leading.first?.title == "Add to playlist",
                "leading swipe actions \(leading.map { $0.title ?? "" })")

        // Trailing swipe surface (批次1 list-section half): a single
        // destructive Remove action.
        let swipeActions = inbox.trailingSwipeActions(at: path)?.actions ?? []
        #expect(swipeActions.count == 1 && swipeActions.first?.style == .destructive
                && swipeActions.first?.title == "Remove",
                "swipe actions \(swipeActions.map { $0.title ?? "" })")

        // Whole-card tap now opens the Detail sheet (was: strip toggle).
        cell.onCardTap?()
        try await Self.settle(window, seconds: 1.2)
        guard let detail = Self.find(DetailViewController.self, in: window.rootViewController) else {
            Issue.record("card tap did not present Detail"); return
        }
        await Self.capture(window, name: "uifix-inbox-card-detail")
        detail.dismiss(animated: false)
        try await Self.settle(window, seconds: 0.5)
    }

    // MARK: - Strip expand reliability (6, playlist list)

    /// The strip-resize corruption guard. Inbox went strip-less (09 §7a-C1),
    /// so the walk runs on the playlist episode list — the strips that
    /// remain (Channel/Search/Playlist/History) share the cell + animator.
    @Test("Playlist strip expand: every toggle resizes item heights, no stuck cards")
    func playlistStripExpandReliability() async throws {
        guard let context = await Self.liveContext(),
              let window = Self.keyWindow() else {
            print("[uifix] shell not ready; skipping"); return
        }
        let queue = (try? await context.database.playlistRepository()
            .listEpisodes(playlistId: ChannelPlaylistLogic.defaultPlaylistID)) ?? []
        guard queue.count >= 3 else {
            print("[uifix] seeded playlist < 3; skipping"); return
        }

        let list = PlaylistEpisodeListViewController(
            context: context, playlistId: ChannelPlaylistLogic.defaultPlaylistID
        )
        list.modalPresentationStyle = .pageSheet
        let presenter = await Self.settledTopPresenter(in: window) ?? window.rootViewController
        presenter?.present(list, animated: false)
        // Same teardown rule as case 5: dismiss from the presenting side.
        defer { presenter?.dismiss(animated: false) }
        try await Self.settle(window, seconds: 1.2)

        guard let collection = Self.firstView(in: list.view, where: { $0 is UICollectionView })
                as? UICollectionView else {
            Issue.record("playlist collection not found"); return
        }

        func height(at item: Int) -> CGFloat {
            collection.collectionViewLayout.layoutAttributesForItem(
                at: IndexPath(item: item, section: 0)
            )?.frame.height ?? 0
        }
        // Collapsed heights per card (titles wrap to two lines, so cards
        // differ in height).
        let collapsedHeights = (0..<min(3, collection.numberOfItems(inSection: 0))).map(height(at:))

        // Walk a toggle sequence across three cards — the shipped defect
        // surfaced as a later toggle failing to resize (or to expand at
        // all) after an earlier expand/collapse.
        let sequence = [0, 1, 2, 1, 0, 2, 0]
        for (step, item) in sequence.enumerated() {
            collection.scrollToItem(
                at: IndexPath(item: item, section: 0), at: .top, animated: false
            )
            try await Self.settle(window, seconds: 0.3)
            guard let cell = collection.cellForItem(at: IndexPath(item: item, section: 0))
                    as? EpisodeCardCell else {
                Issue.record("step \(step): cell \(item) not visible"); continue
            }
            cell.onCardTap?()
            try await Self.settle(window, seconds: 0.5)

            let expandedHeight = height(at: item)
            #expect(expandedHeight > collapsedHeights[item] + 40,
                    "step \(step): item \(item) expanded to \(expandedHeight) (collapsed \(collapsedHeights[item]))")
            for other in collapsedHeights.indices where other != item {
                #expect(abs(height(at: other) - collapsedHeights[other]) < 8,
                        "step \(step): item \(other) did not collapse (\(height(at: other)))")
            }
            // The expanded cell's own frame must match its item height —
            // the strip must never outgrow the cell.
            guard let expandedCell = collection.cellForItem(
                at: IndexPath(item: item, section: 0)
            ) as? EpisodeCardCell else { continue }
            #expect(abs(expandedCell.frame.height - expandedHeight) < 3,
                    "step \(step): cell frame \(expandedCell.frame.height) ≠ item \(expandedHeight)")
            if step == 0 {
                await Self.capture(window, name: "uifix-playlist-expanded")
            }
        }
    }

    // MARK: - Podcast tab shows shelf

    @Test("Shows shelf: a cover opens its Channel; All shows opens the sheet and a show opens its Channel")
    func showsShelfOpensChannelAndSheet() async throws {
        guard let context = await Self.liveContext(),
              let window = Self.keyWindow() else {
            print("[uifix] shell not ready; skipping"); return
        }
        context.tabs.select(0)
        try await Self.settle(window, seconds: 1.5)
        guard let inbox = Self.find(InboxPageViewController.self, in: window.rootViewController),
              let shelf = Self.firstView(in: inbox.view, where: { $0 is ShowsShelfView }) as? ShowsShelfView,
              let cover = shelf.subviewsRecursive()
                .first(where: { $0.accessibilityIdentifier == "shows-shelf-cover-0" }) as? UIControl,
              let allShows = shelf.subviewsRecursive()
                .first(where: { $0.accessibilityIdentifier == "shows-shelf-all" }) as? UIControl
        else {
            print("[uifix] seeded subscriptions missing; skipping"); return
        }
        defer { window.rootViewController?.dismiss(animated: false) }

        cover.sendActions(for: .touchUpInside)
        try await Self.settle(window, seconds: 1.5)
        #expect(Self.find(ChannelViewController.self, in: window.rootViewController) != nil,
                "a shelf cover did not open its Channel")
        window.rootViewController?.dismiss(animated: false)
        try await Self.settle(window, seconds: 0.8)

        allShows.sendActions(for: .touchUpInside)
        try await Self.settle(window, seconds: 1.5)
        guard let sheet = Self.find(ShowsSheetViewController.self, in: window.rootViewController),
              let grid = Self.firstView(in: sheet.view, where: { $0 is UICollectionView })
                as? UICollectionView else {
            Issue.record("All shows did not open the Shows sheet"); return
        }
        #expect(sheet.sheetPresentationController?.prefersGrabberVisible == true)
        grid.delegate?.collectionView?(grid, didSelectItemAt: IndexPath(item: 0, section: 0))
        try await Self.settle(window, seconds: 2.0)
        #expect(Self.find(ShowsSheetViewController.self, in: window.rootViewController) == nil,
                "the sheet did not dismiss after a show was picked")
        #expect(Self.find(ChannelViewController.self, in: window.rootViewController) != nil,
                "a show picked in the sheet did not open its Channel")
    }

    // MARK: - Helpers

    private static func liveContext() async -> UIContext? {
        for _ in 0..<40 {
            if let context = (UIApplication.shared.delegate as? AppDelegate)?.environment.uiContext {
                return context
            }
            try? await Task.sleep(for: .milliseconds(500))
        }
        return nil
    }

    private static func keyWindow() -> UIWindow? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)
    }

    private static func settle(_ window: UIWindow, seconds: Double) async throws {
        window.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(UInt64(seconds * 1000)))
        window.layoutIfNeeded()
    }

    private static func settledTopPresenter(in window: UIWindow) async -> UIViewController? {
        for _ in 0..<40 {
            let top = window.rootViewController?.topMostPresented()
            if let top, top.view.window != nil, !top.isBeingPresented,
               top.transitionCoordinator == nil {
                return top
            }
            try? await Task.sleep(for: .milliseconds(250))
        }
        return nil
    }

    private static func find<T: UIViewController>(
        _ type: T.Type, in root: UIViewController?
    ) -> T? {
        if let match = root as? T { return match }
        for child in root?.children ?? [] {
            if let found = find(type, in: child) { return found }
        }
        if let presented = root?.presentedViewController {
            return find(type, in: presented)
        }
        return nil
    }

    private static func firstView(
        in view: UIView, where predicate: (UIView) -> Bool
    ) -> UIView? {
        if predicate(view) { return view }
        for subview in view.subviews {
            if let found = firstView(in: subview, where: predicate) { return found }
        }
        return nil
    }

    /// Diagnostic capture into NSTemporaryDirectory (same convention as the
    /// t3-visual smoke suites); not an assertion.
    private static func capture(_ window: UIWindow, name: String) async {
        let format = UIGraphicsImageRendererFormat()
        format.scale = window.screen.scale
        let renderer = UIGraphicsImageRenderer(bounds: window.bounds, format: format)
        let image = renderer.image { context in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        guard let data = image.pngData() else { return }
        let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("\(name).png")
        try? data.write(to: url)
        print("[uifix] wrote \(url.path)")
    }

}

private extension UIView {
    func subviewsRecursive() -> [UIView] {
        var found: [UIView] = []
        for subview in subviews {
            found.append(subview)
            found.append(contentsOf: subview.subviewsRecursive())
        }
        return found
    }
}

private extension UIViewController {
    func topMostPresented() -> UIViewController {
        var top = self
        while let next = top.presentedViewController { top = next }
        return top
    }
}

