import UIKit
import Testing
import AnycastKit
@testable import Anycast

/// Regression guards for the shipped-UI defects fixed in this change set
/// (each test names the user-visible symptom it pins):
///
/// 1. Player main page collapsed at the top with one dead gap above the
///    page tab (Flutter parity is `MainAxisAlignment.spaceEvenly`).
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
/// 9. Playlist card expand animating from the layout's .estimated()
///    fallback height instead of the card's measured height (visible
///    shrink-then-expand; taller untouched cards twitched). The follow-up
///    two-phase fix then committed a deformed intermediate solve (the
///    expanded strip settled inside the still-collapsed item frame) — one
///    visible shrink frame on device; the strip targets now land
///    un-settled outside the animation transaction.
/// 10. Playlist whole-card drag reorder dying when the system drag session
///     hijacked a ≥ 0.5 s hold (square full-cell float, no drop handler);
///     interactive movement is now the single reorder path.
/// 11. Inbox add-to-playlist running the fly-in before the row left the
///     list (illogical order) and removing the row through a full
///     reloadData() that re-estimated every self-sizing card (neighbor
///     snap). The row now animates away first, then the ball flies.
/// 12. Mini player compact progress line starting under the artwork and
///     ending mid-air (inset by the capsule's cap radius, aligned to
///     nothing). The line now spans the whole content strip — leading at
///     the title's leading edge (one artwork-gap clear of the cover),
///     trailing at the play/pause glyph's VISIBLE trailing edge (the 44 pt
///     hit slot's edge would outrun the glyph and break the rounded cap).
///
/// Runs against the live shell with the seeded fixture; skips when the
/// shell or the seed is absent. Serialized: the suite drives the SHARED
/// key window.
@MainActor
@Suite(.serialized)
struct UIFixRegressionTests {

    // MARK: - Player page distribution (1) + thumb height (2)

    @Test("Player main page: square capped cover, balanced whitespace, centered play")
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

        // Square, capped at 356 pt (the v2 content-rail width) and
        // horizontally centered; on a 402 pt screen the cover fills the
        // full 24 pt-inset rail and aligns with the title/progress rows.
        #expect(abs(coverFrame.width - coverFrame.height) < 1.5, "cover is not square: \(coverFrame)")
        #expect(coverFrame.width <= 356.5, "cover exceeds its 356 pt cap: \(coverFrame.width)")
        #expect(abs(coverFrame.midX - page.bounds.midX) < 1, "cover is off center")

        // The whitespace above the cover equals the gap between the title
        // and the scrubber block (UI kit balance), unless a floor binds.
        let topGap = coverFrame.minY
        let middleGap = bottomFrame.minY - titleFrame.maxY
        #expect(topGap >= 24 - 0.5, "content is crammed against the sheet top: \(topGap)")
        #expect(middleGap >= 12 - 0.5, "title runs into the scrubber: \(middleGap)")
        if topGap > 24.5 && middleGap > 12.5 {
            #expect(abs(topGap - middleGap) < 2.0, "unbalanced: top \(topGap) vs middle \(middleGap)")
        }

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

    @Test("Mini player: one silhouette — accessory hosts no own chrome, standalone is a capsule")
    func miniPlayerSingleChrome() async {
        guard let context = await Self.liveContext() else {
            print("[uifix] shell not ready; skipping"); return
        }
        // (style, expected capsule background alpha, expected side margin)
        let cases: [(PlayerBarView.HostingStyle, CGFloat, CGFloat)] = [
            (.systemAccessory, 0, 0),
            (.standalone, 0.10, 12),
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
            // Same capsule contour in both styles — a flatter standalone
            // radius (the old 16) made the bar read as a different element
            // on sheet-hosted screens than in the system accessory.
            #expect(abs(capsule.layer.cornerRadius - 29) < 0.5,
                    "\(style): corner radius \(capsule.layer.cornerRadius) is not a capsule (29)")
        }
    }

    // MARK: - Mini player compact progress line (12)

    /// The compact styles' thin progress line spans the whole content
    /// strip: leading at the title's leading edge (one artwork-gap clear
    /// of the cover), trailing at the play/pause slot's trailing edge.
    /// The standalone style keeps its full-height fill.
    @Test("Mini player progress line runs from the title's leading to the play/pause trailing edge")
    func miniPlayerProgressLineAnchoredToControls() async {
        guard let context = await Self.liveContext() else {
            print("[uifix] shell not ready; skipping"); return
        }
        for style: PlayerBarView.HostingStyle in [.systemAccessory, .capsule] {
            let bar = context.makePlayerBar(style: style)
            bar.frame = CGRect(x: 0, y: 0, width: 320, height: PlayerBarView.barHeight)
            bar.layoutIfNeeded()
            guard let capsule = bar.subviews.first,
                  let backdrop = capsule.subviews.compactMap({ $0 as? EpisodeProgressBackdrop }).first,
                  let cover = capsule.subviews.compactMap({ $0 as? UIImageView }).first,
                  let title = capsule.subviews
                    .compactMap({ $0 as? UILabel })
                    .first(where: { $0.accessibilityIdentifier == "mini-player-title" }),
                  let playPause = capsule.subviews.compactMap({ $0 as? PlayPauseIconControl }).first else {
                Issue.record("\(style): mini player subviews missing"); continue
            }
            #expect(abs(backdrop.frame.minX - title.frame.minX) < 0.5,
                    "\(style): line leading \(backdrop.frame.minX) ≠ title leading \(title.frame.minX)")
            #expect(abs(backdrop.frame.maxX - (playPause.frame.maxX - playPause.glyphInset)) < 0.5,
                    "\(style): line trailing \(backdrop.frame.maxX) ≠ play/pause glyph trailing \(playPause.frame.maxX - playPause.glyphInset)")
            #expect(backdrop.frame.minX > cover.frame.maxX,
                    "\(style): line leading \(backdrop.frame.minX) reaches under the artwork (ends \(cover.frame.maxX))")
            // Inside the capsule's straight-walled region: at the line's
            // height the rounded cap has already curved inward past
            // bounds.maxX - 10, so the end must clear that contour.
            #expect(backdrop.frame.maxX <= capsule.bounds.maxX - 10,
                    "\(style): line trailing \(backdrop.frame.maxX) breaks into the rounded cap (\(capsule.bounds.maxX))")
        }

        // Standalone keeps the full-height fill (sheet bars, 03 §2.9).
        let standalone = context.makePlayerBar(style: .standalone)
        standalone.frame = CGRect(x: 0, y: 0, width: 320, height: PlayerBarView.barHeight)
        standalone.layoutIfNeeded()
        if let capsule = standalone.subviews.first,
           let fill = capsule.subviews.compactMap({ $0 as? EpisodeProgressBackdrop }).first {
            // fill.frame is capsule-local; compare against the capsule's
            // own bounds (capsule.frame carries the 12 pt host margin).
            #expect(abs(fill.frame.minX - capsule.bounds.minX) < 0.5
                    && abs(fill.frame.maxX - capsule.bounds.maxX) < 0.5,
                    "standalone fill must still span the capsule")
        } else {
            Issue.record("standalone: fill backdrop missing")
        }
    }

    // MARK: - Card progress backdrop corners (4)

    @Test("Card progress backdrop clips inside the rounded card corners")
    func cardBackdropClippedToCorners() {
        let cell = EpisodeCardCell(frame: CGRect(x: 0, y: 0, width: 354, height: 104))
        cell.configure(
            EpisodeCardContent(
                title: "Episode", channelTitle: "Channel", rightText: "12m left",
                descriptionHTML: nil, imageURL: nil,
                showsProgressBackdrop: true,
                progressFraction: 0.6,
                descriptionPlainText: "Description"
            ),
            actions: []
        )
        cell.layoutIfNeeded()

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: cell.bounds.size, format: format)
        let image = renderer.image { context in
            cell.layer.render(in: context.cgContext)
        }
        guard let cg = image.cgImage else {
            Issue.record("cell render failed"); return
        }
        let pixel = { (x: Int, y: Int) -> (UInt8, UInt8, UInt8, UInt8) in
            var data = [UInt8](repeating: 0, count: 4)
            guard let ctx = CGContext(
                data: &data, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return (0, 0, 0, 0) }
            ctx.interpolationQuality = .none
            ctx.draw(
                cg,
                in: CGRect(
                    x: -CGFloat(x), y: -CGFloat(y),
                    width: cell.bounds.width, height: cell.bounds.height
                )
            )
            return (data[0], data[1], data[2], data[3])
        }
        // Inside the 20 pt corner radius the bottom-left corner must be
        // empty (the backdrop no longer paints through the rounded edge)…
        let corner = pixel(2, 100)
        #expect(corner.3 == 0, "progress strip paints the rounded corner (alpha \(corner.3))")
        // …while the strip itself still paints at the bottom center.
        let center = pixel(177, 100)
        #expect(center.3 > 200, "progress strip missing at the bottom edge (alpha \(center.3))")
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
            .filter { $0.accessibilityLabel == "Play" }
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

    // MARK: - 7, sheet chrome safe area

    /// The search sheet was the one screen whose player bar pinned to the
    /// RAW bottom edge (under the home indicator) — every other page
    /// anchors to the safe area. Guards the anchor itself, because the bar
    /// hides when nothing plays and its frame cannot be asserted.
    @Test("Search sheet player bar anchors to the safe area, not the raw bottom")
    func searchSheetPlayerBarRespectsSafeArea() async throws {
        guard let context = await Self.liveContext(),
              let window = Self.keyWindow() else {
            print("[uifix] shell not ready; skipping"); return
        }
        let sheet = SearchPageViewController(context: context, searchText: "safe-area")
        sheet.modalPresentationStyle = .pageSheet
        let presenter = await Self.settledTopPresenter(in: window) ?? window.rootViewController
        presenter?.present(sheet, animated: false)
        defer { presenter?.dismiss(animated: false) }
        try await Self.settle(window, seconds: 0.6)

        guard let bar = Self.firstView(in: sheet.view, where: { $0 is PlayerBarView }),
              let host = bar.superview as? UIView else {
            Issue.record("player bar not found in the search sheet"); return
        }
        let bottomAnchor = host.constraints.first {
            ($0.firstItem as? UIView) === bar && $0.firstAttribute == .bottom
        }
        guard let bottomAnchor else {
            Issue.record("player bar has no bottom constraint on its host"); return
        }
        let target = bottomAnchor.secondItem
        #expect(
            target is UILayoutGuide
                && (target as? UILayoutGuide)?.identifier == "UIViewSafeAreaLayoutGuide",
            "player bar bottom must anchor to the safe area guide, got: \(String(describing: target))"
        )
    }

    // MARK: - 9. Expand animation source height (playlist list)

    /// The expand/collapse must animate from the card's CURRENT measured
    /// height. A global `invalidateLayout()` inside the animation
    /// transaction discarded the compositional layout's measured item
    /// sizes, so the animator's before-values fell back to the
    /// `.estimated(112)` height: a taller tapped card visibly shrank
    /// before expanding, and taller untouched cards twitched toward the
    /// estimate. The two-phase fix for that then committed a second
    /// shrink source: the unanimated constraint settle solved the expanded
    /// strip inside the still-collapsed item frame, deforming the card
    /// body for one visible frame on device. The animator now applies the
    /// strip targets UN-settled outside the animation transaction (the
    /// re-measure needs the constants outside it) and animates one
    /// targeted invalidation inside — no solve ever runs against the
    /// stale item frame. Pinned here by three probes: the animation's
    /// from-value (the layer animation's `fromValue` when present, else
    /// early presentation-layer samples), mid-transition card-body
    /// stillness (never below its pre-tap height — kills both shrink
    /// mechanisms empirically), and the settled +stripHeight outcome.
    @Test("Playlist strip expand animates from the card's current height; neighbors hold still")
    func playlistStripExpandAnimatesFromCurrentHeight() async throws {
        guard let context = await Self.liveContext(),
              let window = Self.keyWindow() else {
            print("[uifix] shell not ready; skipping"); return
        }
        let queue = (try? await context.database.playlistRepository()
            .listEpisodes(playlistId: ChannelPlaylistLogic.defaultPlaylistID)) ?? []
        guard queue.count >= 1,
              let presenter = await Self.settledTopPresenter(in: window) ?? window.rootViewController else {
            print("[uifix] seeded playlist empty; skipping"); return
        }

        // Seed one deterministically TALL card at the END of the playlist.
        // The defect only reads on a card taller than the .estimated()
        // fallback (estimate < actual — the buggy animation ran estimate →
        // expanded instead of measured → expanded); the fixture's own
        // spread is not guaranteed, this row is. A full two-line title and
        // two-line description push the text column past the 80 pt cover,
        // so the card self-sizes above `cardRowHeight`.
        let tallURL = "https://example.com/uifix-tall-card.mp3"
        let tallRow = PlaylistEpisodeRow(
            title: String(repeating: "A wrapped two-line title. ", count: 4),
            description: String(repeating: "A long description body that wraps twice. ", count: 6),
            duration: 3_600_000,
            enclosureUrl: tallURL,
            pubDate: 1_760_000_000_000,
            channelTitle: "UIFix",
            rssFeedUrl: "https://example.com/uifix.xml",
            playlistId: ChannelPlaylistLogic.defaultPlaylistID,
            playedDuration: 0
        )
        try? await context.database.playlistRepository().insertOrUpdateByIndex(
            tallRow, playlistId: ChannelPlaylistLogic.defaultPlaylistID, index: queue.count
        )
        // Best-effort net for early exits; the happy path awaits its own
        // cleanup first (idempotent delete by URL).
        defer {
            Task { try? await context.database.playlistRepository().removeEpisodeCascade(byEnclosureURL: tallURL) }
        }

        let list = PlaylistEpisodeListViewController(
            context: context, playlistId: ChannelPlaylistLogic.defaultPlaylistID
        )
        list.modalPresentationStyle = .pageSheet
        presenter.present(list, animated: false)
        defer { presenter.dismiss(animated: false) }
        try await Self.settle(window, seconds: 1.2)

        guard let collection = Self.firstView(in: list.view, where: { $0 is UICollectionView })
                as? UICollectionView else {
            Issue.record("playlist collection not found"); return
        }

        func itemHeight(_ item: Int) -> CGFloat {
            collection.collectionViewLayout.layoutAttributesForItem(
                at: IndexPath(item: item, section: 0)
            )?.frame.height ?? 0
        }
        /// The card plate (the stack's first arranged subview) — the body
        /// the intermediate-state deformation compresses.
        func cardBody(of cell: EpisodeCardCell) -> UIView? {
            (cell.contentView.subviews.first as? UIStackView)?.arrangedSubviews.first
        }

        let target = IndexPath(item: collection.numberOfItems(inSection: 0) - 1, section: 0)
        collection.scrollToItem(at: target, at: .top, animated: false)
        try await Self.settle(window, seconds: 0.4)
        let targetBefore = itemHeight(target.item)
        // The estimate-vs-actual gap is the defect condition — assert it,
        // do not skip on it: the seeded row exists precisely to guarantee
        // it.
        guard targetBefore > EpisodeCardCell.cardRowHeight + 10 else {
            Issue.record(
                "seeded tall card measured \(targetBefore) — not above the .estimated() fallback \(EpisodeCardCell.cardRowHeight); the from-height probe cannot discriminate"
            )
            return
        }
        let neighbors = collection.indexPathsForVisibleItems
            .filter { $0.section == 0 && $0 != target }
            .sorted { $0.item < $1.item }
        let neighborsBefore = neighbors.compactMap { path -> (Int, CGFloat)? in
            guard collection.cellForItem(at: path) != nil else { return nil }
            return (path.item, itemHeight(path.item))
        }
        guard let cell = collection.cellForItem(at: target) as? EpisodeCardCell,
              let body = cardBody(of: cell) else {
            Issue.record("target card cell not visible"); return
        }
        let bodyBefore = body.frame.height
        guard !neighborsBefore.isEmpty else {
            Issue.record("no visible neighbor card — the neighbor-stillness probe has nothing to track")
            return
        }

        cell.onCardTap?()

        // Proof a real animation ran, captured synchronously at t≈0: the
        // layer must carry the resize animation (Core Animation keys it
        // "bounds.size"; the system's own self-sizing pass adds a second
        // "-2" copy), and the MODEL must already sit at the final size
        // while the PRESENTATION layer still shows the pre-tap height —
        // an animated transition, not a snap. Mid-animation presentation
        // SAMPLING is not usable as a probe here: the two overlapping
        // resize animations blend in the presentation layer and can read
        // far outside [from, to] mid-flight (observed 25⅔ pt between
        // 137⅔ and 197⅔); the synchronous t≈0 read below is immune
        // because the main thread has not yielded, so the last committed
        // presentation is exactly the pre-tap state.
        guard let resizeAnimation = cell.layer.animation(forKey: "bounds.size") as? CABasicAnimation else {
            Issue.record("the expand produced no bounds.size animation — the item never animated")
            return
        }
        #expect(cell.frame.height > targetBefore + EpisodeCardCell.stripHeight - 8,
                "model height \(cell.frame.height) did not reach \(targetBefore + EpisodeCardCell.stripHeight) at t≈0")
        // The RENDERED from-value: at t≈0 the presentation layer still
        // shows the pre-tap height (within a few points) while the model
        // is already at the final size — the resize visibly starts AT the
        // measured height, never at the .estimated() fallback. (The
        // animations' DECLARED fromValues are additive deltas from the
        // system's overlapping self-sizing pass — observed 25⅔ = measured
        // − estimate — and are not pinnable; the presentation layer is
        // what the user sees.)
        if let presentedAtStart = cell.layer.presentation()?.frame.height {
            #expect(abs(presentedAtStart - targetBefore) < 8,
                    "presentation at \(presentedAtStart) at t≈0 — not the card's measured height \(targetBefore)")
        }
        #expect(abs(resizeAnimation.duration - 0.2) < 0.05,
                "expand animation duration \(resizeAnimation.duration) is not the animator's 0.2 s cadence")
        if let secondary = cell.layer.animation(forKey: "bounds.size-2") as? CABasicAnimation {
            print("[uifix] resize animations: primary from \(String(describing: resizeAnimation.fromValue)) additive=\(resizeAnimation.isAdditive), secondary from \(String(describing: secondary.fromValue)) additive=\(secondary.isAdditive)")
        }
        for _ in 0..<2 {
            try await Task.sleep(for: .milliseconds(25))
            // Card body never compresses: neither the model layer (an
            // unanimated forced settle committing the deformed solve) nor
            // the presentation layer (an animation whose from-value is the
            // deformed solve) may dip below the pre-tap height.
            let bodyPresented = body.layer.presentation()?.frame.height ?? body.frame.height
            #expect(body.frame.height > bodyBefore - 1,
                    "card body model height \(body.frame.height) dipped below pre-tap \(bodyBefore) mid-expand")
            #expect(bodyPresented > bodyBefore - 1,
                    "card body presented height \(bodyPresented) dipped below pre-tap \(bodyBefore) mid-expand")
            // Neighbors animate nothing: presentation stays on their item
            // height, and their item height never moves toward the estimate.
            for path in neighbors {
                guard let other = collection.cellForItem(at: path) else { continue }
                let otherPresented = other.layer.presentation()?.frame.height ?? other.frame.height
                #expect(abs(otherPresented - itemHeight(path.item)) < 4,
                        "neighbor \(path.item) animated mid-expand (presented \(otherPresented), item \(itemHeight(path.item)))")
                #expect(abs(itemHeight(path.item) - (neighborsBefore.first(where: { $0.0 == path.item })?.1 ?? itemHeight(path.item))) < 4,
                        "neighbor \(path.item) item height drifted toward the estimate")
            }
        }

        // Settled: exactly +stripHeight on the tapped card, neighbors intact.
        try await Self.settle(window, seconds: 0.5)
        #expect(abs(itemHeight(target.item) - (targetBefore + EpisodeCardCell.stripHeight)) < 8,
                "expanded height \(itemHeight(target.item)) != collapsed \(targetBefore) + strip \(EpisodeCardCell.stripHeight)")
        let settledBody = cardBody(of: cell)?.frame.height ?? 0
        #expect(abs(settledBody - bodyBefore) < 1,
                "settled card body height changed: \(settledBody) vs pre-tap \(bodyBefore)")
        for (item, before) in neighborsBefore {
            #expect(abs(itemHeight(item) - before) < 1,
                    "neighbor \(item) changed height \(before) → \(itemHeight(item))")
        }

        // Restore the fixture: the seeded tall row leaves the playlist it
        // was appended to (awaited, so later serialized tests read clean).
        try? await context.database.playlistRepository().removeEpisodeCascade(byEnclosureURL: tallURL)
    }

    // MARK: - 9b. Off-screen collapse (scroll-back settling)

    /// The animator's targeted invalidation only reaches VISIBLE items.
    /// When card A expands, scrolls fully off-screen, and card B is then
    /// expanded (the coordinator logically collapses A), nothing told the
    /// layout solver to drop A's measured +strip item size. On scroll-back
    /// A's cell reconfigures collapsed (strip constant 0) — if its item
    /// kept the stale expanded size, the top/bottom-pinned stack stretches
    /// the card plate to fill the taller item.
    ///
    /// Measured on iOS 27: the stretch does NOT occur. The stale measured
    /// size dies with the cell — once A's cell leaves the visible set and
    /// recycles, the compositional layout re-resolves the item's estimated
    /// dimension against the freshly configured (collapsed) cell when it
    /// reappears: A settles at exactly its collapsed height with an
    /// unstretched plate (137⅔ → 137⅔ in both this run and every retry).
    /// No completion-phase invalidation of the previous path is needed;
    /// this test pins that behavior so a future UIKit change that keeps
    /// the stale size surfaces here instead of on users.
    @Test("Playlist strip expand: off-screen collapse settles on scroll-back")
    func playlistStripExpandOffscreenCollapseSettlesOnScrollBack() async throws {
        guard let context = await Self.liveContext(),
              let window = Self.keyWindow() else {
            print("[uifix] shell not ready; skipping"); return
        }
        let queue = (try? await context.database.playlistRepository()
            .listEpisodes(playlistId: ChannelPlaylistLogic.defaultPlaylistID)) ?? []
        guard queue.count >= 2,
              let presenter = await Self.settledTopPresenter(in: window) ?? window.rootViewController else {
            print("[uifix] seeded playlist < 2; skipping"); return
        }

        // Seed filler rows so the list MUST scroll: the viewport (~874 pt)
        // has to be overflowable to push card A fully off-screen.
        let fillerURLs = (0..<6).map { "https://example.com/uifix-filler-\($0).mp3" }
        for (offset, url) in fillerURLs.enumerated() {
            let row = PlaylistEpisodeRow(
                title: "UIFix filler \(offset)",
                description: "Filler row for the scroll-back probe.",
                duration: 3_600_000,
                enclosureUrl: url,
                pubDate: 1_760_000_000_000,
                channelTitle: "UIFix",
                rssFeedUrl: "https://example.com/uifix.xml",
                playlistId: ChannelPlaylistLogic.defaultPlaylistID,
                playedDuration: 0
            )
            try? await context.database.playlistRepository().insertOrUpdateByIndex(
                row, playlistId: ChannelPlaylistLogic.defaultPlaylistID, index: queue.count + offset
            )
        }
        defer {
            Task {
                for url in fillerURLs {
                    try? await context.database.playlistRepository().removeEpisodeCascade(byEnclosureURL: url)
                }
            }
        }

        let list = PlaylistEpisodeListViewController(
            context: context, playlistId: ChannelPlaylistLogic.defaultPlaylistID
        )
        list.modalPresentationStyle = .pageSheet
        presenter.present(list, animated: false)
        defer { presenter.dismiss(animated: false) }
        try await Self.settle(window, seconds: 1.2)

        guard let collection = Self.firstView(in: list.view, where: { $0 is UICollectionView })
                as? UICollectionView else {
            Issue.record("playlist collection not found"); return
        }
        func itemHeight(_ item: Int) -> CGFloat {
            collection.collectionViewLayout.layoutAttributesForItem(
                at: IndexPath(item: item, section: 0)
            )?.frame.height ?? 0
        }
        func cardPlate(_ cell: EpisodeCardCell) -> UIView? {
            (cell.contentView.subviews.first as? UIStackView)?.arrangedSubviews.first
        }

        // Expand card A (item 0).
        let pathA = IndexPath(item: 0, section: 0)
        collection.scrollToItem(at: pathA, at: .top, animated: false)
        try await Self.settle(window, seconds: 0.3)
        let collapsedA = itemHeight(0)
        guard let cellA = collection.cellForItem(at: pathA) as? EpisodeCardCell,
              let plateBefore = cardPlate(cellA) else {
            Issue.record("card A not visible"); return
        }
        let plateHeightBefore = plateBefore.frame.height
        cellA.onCardTap?()
        try await Self.settle(window, seconds: 0.5)
        #expect(abs(itemHeight(0) - collapsedA - EpisodeCardCell.stripHeight) < 8,
                "card A did not expand (item \(itemHeight(0)), collapsed \(collapsedA))")

        // Push A fully off-screen, then expand card B — the coordinator
        // collapses A while nothing visible represents it. The criterion
        // is the collection view's VISIBLE set (the same bounds-based set
        // the animator drives); UIKit keeps buffer cells materialized
        // slightly past the viewport, so cellForItem alone is not proof.
        let lastIndex = collection.numberOfItems(inSection: 0) - 1
        let pathB = IndexPath(item: lastIndex, section: 0)
        collection.scrollToItem(at: pathB, at: .top, animated: false)
        try await Self.settle(window, seconds: 0.4)
        guard !collection.indexPathsForVisibleItems.contains(pathA) else {
            Issue.record("card A never left the visible set — the filler rows do not overflow the viewport")
            return
        }
        guard let cellB = collection.cellForItem(at: pathB) as? EpisodeCardCell else {
            Issue.record("card B not visible"); return
        }
        cellB.onCardTap?()
        try await Self.settle(window, seconds: 0.5)

        // Scroll back: A must settle COLLAPSED — item height restored, no
        // stretched plate.
        collection.scrollToItem(at: pathA, at: .top, animated: false)
        try await Self.settle(window, seconds: 0.5)
        let settledA = itemHeight(0)
        guard let cellAReturned = collection.cellForItem(at: pathA) as? EpisodeCardCell,
              let plateReturned = cardPlate(cellAReturned) else {
            Issue.record("card A did not come back on screen"); return
        }
        print("[uifix] off-screen collapse: item \(collapsedA) → settled \(settledA); plate \(plateHeightBefore) → \(plateReturned.frame.height)")
        #expect(abs(settledA - collapsedA) < 4,
                "card A's item settled at \(settledA) after scroll-back, not its collapsed height \(collapsedA)")
        #expect(abs(plateReturned.frame.height - plateHeightBefore) < 2,
                "card A's plate stretched on scroll-back (\(plateHeightBefore) → \(plateReturned.frame.height))")

        // Fixture restore (awaited; the defer Task above is the early-exit net).
        for url in fillerURLs {
            try? await context.database.playlistRepository().removeEpisodeCascade(byEnclosureURL: url)
        }
    }

    /// The intermediate-state mechanism, pinned deterministically (no
    /// shell): settling the expanded strip inside a still-collapsed cell
    /// frame over-constrains the layout — the committed solve deforms the
    /// card (body compressed or strip squashed away from its 60 pt target).
    /// The animator's deferred settle (`settleLayout: false`) leaves the
    /// cell's solved geometry untouched, so the single animated batch pass
    /// is the first and only solve that sees the new constraints.
    @Test("Strip target: forced settle deforms a collapsed cell; deferred settle does not solve")
    func stripTargetSettleDeformsCollapsedCell() {
        func makeCard() -> (EpisodeCardCell, UIView, UIView) {
            let cell = EpisodeCardCell(
                frame: CGRect(x: 0, y: 0, width: 354, height: EpisodeCardCell.cardRowHeight)
            )
            cell.configure(
                EpisodeCardContent(
                    title: "Episode", channelTitle: "Channel", rightText: "12m left",
                    descriptionHTML: nil, imageURL: nil, descriptionPlainText: "Description"
                ),
                actions: [EpisodeCardAction(
                    icon: UIImage(), accessibilityLabel: "Play"
                ) {}]
            )
            cell.layoutIfNeeded()
            let arranged = (cell.contentView.subviews.first as? UIStackView)?.arrangedSubviews ?? []
            return (cell, arranged.first!, arranged.last!)
        }

        // Forced settle (the retired Phase 1): the expanded strip must fit
        // inside the collapsed frame — impossible; the solve breaks. Either
        // the card body compresses below its pre-expand height or the strip
        // lands short of its 60 pt target — both are the deformed
        // intermediate state.
        let (forced, forcedBody, forcedStrip) = makeCard()
        let forcedBefore = forcedBody.frame.height
        UIView.performWithoutAnimation { forced.setExpanded(true) }
        let deformed = abs(forcedBody.frame.height - forcedBefore) > 0.5
            || abs(forcedStrip.frame.height - EpisodeCardCell.stripHeight) > 0.5
        print("[uifix] forced settle: body \(forcedBefore) → \(forcedBody.frame.height), strip → \(forcedStrip.frame.height)")
        #expect(deformed,
                "forced settle inside a collapsed frame solved cleanly (body \(forcedBefore) → \(forcedBody.frame.height), strip \(forcedStrip.frame.height)) — the intermediate-state hypothesis would be unfounded")

        // Deferred settle (the animator path): the target lands, no solve
        // runs — the body keeps its collapsed geometry until the batch's
        // own animated pass.
        let (deferred, deferredBody, _) = makeCard()
        let deferredBefore = deferredBody.frame.height
        deferred.setExpanded(true, settleLayout: false)
        #expect(abs(deferredBody.frame.height - deferredBefore) < 0.5,
                "deferred settle moved the card body (\(deferredBefore) → \(deferredBody.frame.height)) before any layout pass")
    }

    // MARK: - 10. Whole-card drag reorder (the interactive-movement path)

    /// The 150 ms whole-card drag drives `beginInteractiveMovementForItem`
    /// → `updateInteractiveMovementTargetPosition` → `endInteractiveMovement`;
    /// commits land in the diffable `reorderingHandlers`. This drives the
    /// same API sequence a finger drag drives and asserts the reorder
    /// reaches the database and survives the list's own reload. Also pins
    /// the single-path rule: system drag & drop stays off (a system drag
    /// session used to hijack holds ≥ 0.5 s, lift a square full-cell
    /// preview, and silently drop the reorder).
    @Test("Playlist reorder: interactive movement commits through reorderingHandlers and persists")
    func playlistInteractiveMovementReorderPersists() async throws {
        guard let context = await Self.liveContext(),
              let window = Self.keyWindow() else {
            print("[uifix] shell not ready; skipping"); return
        }
        let queue = (try? await context.database.playlistRepository()
            .listEpisodes(playlistId: ChannelPlaylistLogic.defaultPlaylistID)) ?? []
        let beforeURLs = queue.compactMap(\.enclosureUrl)
        guard beforeURLs.count >= 3,
              let presenter = await Self.settledTopPresenter(in: window) ?? window.rootViewController else {
            print("[uifix] seeded playlist < 3; skipping"); return
        }

        let list = PlaylistEpisodeListViewController(
            context: context, playlistId: ChannelPlaylistLogic.defaultPlaylistID
        )
        list.modalPresentationStyle = .pageSheet
        presenter.present(list, animated: false)
        defer { presenter.dismiss(animated: false) }
        try await Self.settle(window, seconds: 1.2)

        guard let collection = Self.firstView(in: list.view, where: { $0 is UICollectionView })
                as? UICollectionView else {
            Issue.record("playlist collection not found"); return
        }

        // The single-path rule: no system drag session may run over this
        // list (it raced the 150 ms gesture and killed the reorder).
        #expect(!collection.dragInteractionEnabled,
                "system drag & drop must stay disabled on the playlist list")
        #expect(collection.dragDelegate == nil,
                "no drag delegate may be installed on the playlist list")

        // Drive the exact API sequence dragGestureFired drives: lift the
        // head, move it to the last slot, drop.
        let last = IndexPath(item: beforeURLs.count - 1, section: 0)
        guard let lastAttributes = collection.collectionViewLayout.layoutAttributesForItem(at: last) else {
            Issue.record("last item attributes missing"); return
        }
        #expect(collection.beginInteractiveMovementForItem(at: IndexPath(item: 0, section: 0)),
                "interactive movement did not begin")
        try await Task.sleep(for: .milliseconds(80))
        collection.updateInteractiveMovementTargetPosition(
            CGPoint(x: lastAttributes.frame.midX, y: lastAttributes.frame.maxY - 5)
        )
        try await Task.sleep(for: .milliseconds(80))
        collection.endInteractiveMovement()
        // The commit chain (repository write → playback steps → reload)
        // runs in a Task; settle before reading the database.
        try await Self.settle(window, seconds: 2.0)

        let expected = Array(beforeURLs.dropFirst()) + [beforeURLs[0]]
        let afterURLs = (try? await context.database.playlistRepository()
            .listEpisodes(playlistId: ChannelPlaylistLogic.defaultPlaylistID))?
            .compactMap(\.enclosureUrl) ?? []
        #expect(afterURLs == expected,
                "interactive movement did not persist (after \(afterURLs), expected \(expected))")
        #expect(list.episodes.compactMap(\.enclosureUrl) == expected,
                "the in-memory list did not follow the reorder (\(list.episodes.compactMap(\.enclosureUrl)))")

        // Restore the seeded order — this writes the LIVE app container; a
        // leftover reorder would skew later runs' head-episode assumptions.
        for (index, row) in queue.enumerated() {
            try await context.database.playlistRepository()
                .insertOrUpdateByIndex(row, playlistId: ChannelPlaylistLogic.defaultPlaylistID, index: index)
        }
    }

    // MARK: - 11. Inbox add-to-playlist: animated removal precedes the fly-in

    /// The add flow's shape: the playlist insert commits FIRST (kill-window
    /// safety), the row animates away (a batch delete that keeps the
    /// surviving rows' measured sizes — the old no-animation reloadData()
    /// re-estimated every self-sizing card and the neighbors snapped), THEN
    /// the ball flies. Pins the visual order (the fly overlay appears only
    /// after the row VISUALLY leaves the list), the neighbor stillness
    /// (tracked by cell identity, not position), the collection view's own
    /// row count, and the database outcome, then restores the fixture.
    @Test("Inbox add-to-playlist: row animates away first, then the fly-in")
    func inboxAddToPlaylistRemovesRowBeforeFlyIn() async throws {
        guard let context = await Self.liveContext(),
              let window = Self.keyWindow() else {
            print("[uifix] shell not ready; skipping"); return
        }
        context.tabs.select(0)
        try await Self.settle(window, seconds: 1.5)

        guard let inbox = Self.find(InboxPageViewController.self, in: window.rootViewController),
              let collection = Self.firstView(in: inbox.view, where: { $0 is UICollectionView })
                as? UICollectionView else {
            print("[uifix] inbox missing; skipping"); return
        }
        let rowsBefore = (try? await context.database.feedRepository().listAll()) ?? []
        // A card that is not the currently playing episode — adding the
        // playing episode is the skip-insert branch and never lands in the
        // playlist.
        let playingURL = context.playback.currentEpisode?.enclosureUrl
        guard let episodeIndex = rowsBefore.firstIndex(where: {
            guard let url = $0.enclosureUrl, !url.isEmpty else { return false }
            return url != playingURL
        }) else {
            print("[uifix] seeded inbox empty; skipping"); return
        }
        let episodeRow = rowsBefore[episodeIndex]
        guard let url = episodeRow.enclosureUrl else { return }

        // Resolve the card's index path: card cells all share the cards
        // section; the displayed order is the repository order (no filter).
        guard let cardSection = collection.indexPathsForVisibleItems
            .first(where: { collection.cellForItem(at: $0) is InboxEpisodeCardCell })?.section,
              let cell = collection.cellForItem(
                  at: IndexPath(item: episodeIndex, section: cardSection)
              ) as? InboxEpisodeCardCell else {
            print("[uifix] target card not visible; skipping"); return
        }
        guard let add = cell.menuActions.first(where: { $0.accessibilityLabel == "Add to playlist" }) else {
            Issue.record("card carries no add action"); return
        }

        // Identity-tracked cells: after the delete, positions shift, so the
        // probes follow the CELL OBJECTS (the removed card's cell and one
        // surviving neighbor) instead of index paths.
        weak let removedCell = cell
        let neighborCandidate = collection.indexPathsForVisibleItems
            .filter { $0 != IndexPath(item: episodeIndex, section: cardSection) }
            .sorted { $0.item < $1.item }
            .compactMap { collection.cellForItem(at: $0) as? InboxEpisodeCardCell }
            .first
        guard let neighbor = neighborCandidate else {
            Issue.record("no second visible inbox card — the neighbor-stillness probe has nothing to track")
            return
        }
        weak let neighborCell = neighbor

        // The collection view's OWN count (the visual list), not the data
        // source's.
        let cardsCountBefore = collection.numberOfItems(inSection: cardSection)

        add.handler()

        // Order probes. The fly overlay's MODEL frame is its 24×24 endpoint
        // from the moment the flight commits — the 200×48 capsule exists
        // only in the presentation layer, so that is where the probe looks.
        func flyOverlayPresent() -> Bool {
            window.subviews.contains { sub in
                sub.frame.width < 32 && sub.frame.height < 32
                    && (sub.layer.presentation()?.frame.width ?? 0) > 60
            }
        }
        // The deleted cell's VISUAL disappearance. UIKit parks the recycled
        // cell as a hidden, zero-alpha subview of the collection view (its
        // `window` stays non-nil), so the probe watches the fade-out end
        // state instead of view teardown.
        func removedCellVisuallyGone() -> Bool {
            guard let removedCell else { return true }
            return removedCell.isHidden || removedCell.alpha < 0.05
        }
        var commitTime: TimeInterval?      // batch commits (count drops)
        var goneTime: TimeInterval?        // delete animation ends (cell leaves the window)
        var flyTime: TimeInterval?
        var neighborHeights: [CGFloat] = []
        let start = Date()
        while Date().timeIntervalSince(start) < 3 {
            let elapsed = Date().timeIntervalSince(start)
            if commitTime == nil,
               collection.numberOfItems(inSection: cardSection) == cardsCountBefore - 1 {
                commitTime = elapsed
            }
            if goneTime == nil, removedCellVisuallyGone() { goneTime = elapsed }
            if flyTime == nil, flyOverlayPresent() { flyTime = elapsed }
            if let neighborCell { neighborHeights.append(neighborCell.frame.height) }
            if commitTime != nil, goneTime != nil, flyTime != nil { break }
            try await Task.sleep(for: .milliseconds(30))
        }
        #expect(commitTime != nil, "collection view row count never decreased")
        #expect(flyTime != nil, "fly-in overlay never appeared")
        #expect(goneTime != nil, "the removed card's cell never faded out")
        if let commit = commitTime, let fly = flyTime {
            #expect(fly >= commit - 0.05,
                    "fly-in (\(fly)s) ran before the delete committed (\(commit)s)")
        }
        // The visual claim itself: the ball leaves only once the row has
        // visibly gone (the fly starts in the delete-animation completion).
        if let gone = goneTime, let fly = flyTime {
            #expect(fly >= gone - 0.1,
                    "fly-in (\(fly)s) started before the row left the screen (\(gone)s)")
        }
        // Neighbor stillness by identity: the surviving cell's height never
        // moves through the whole flow (a reloadData() would re-estimate
        // it; the animated delete keeps it).
        #expect(!neighborHeights.isEmpty, "the neighbor probe never sampled its cell")
        #expect(neighborHeights.allSatisfy { abs($0 - (neighborHeights.first ?? $0)) < 1.5 },
                "neighbor card height changed mid-removal (\(neighborHeights)) — the list re-estimated its cards")

        // Settled: exactly one row gone VISUALLY (collection view count, the
        // removed cell off-screen), and the episode moved inbox → default
        // playlist in the database.
        try await Self.settle(window, seconds: 1.5)
        #expect(collection.numberOfItems(inSection: cardSection) == cardsCountBefore - 1,
                "collection view count \(collection.numberOfItems(inSection: cardSection)) != \(cardsCountBefore - 1)")
        #expect(removedCellVisuallyGone(), "the removed card's cell is still visible after the settle")
        if let removedCell {
            #expect(!collection.visibleCells.contains(removedCell),
                    "the removed card's cell still reports as visible after the settle")
        }
        #expect(neighborCell?.window != nil,
                "the surviving neighbor cell left the screen — the wrong row was deleted")
        let inboxAfter = (try? await context.database.feedRepository().listAll()) ?? []
        #expect(!inboxAfter.contains { $0.enclosureUrl == url }, "episode stayed in the inbox")
        let playlistAfter = (try? await context.database.playlistRepository()
            .listEpisodes(playlistId: ChannelPlaylistLogic.defaultPlaylistID)) ?? []
        #expect(playlistAfter.contains { $0.enclosureUrl == url },
                "episode never landed in the playlist")

        // Restore the fixture (the live container must not leak this add):
        // back out of the playlist, return the inbox row.
        try? await context.database.playlistRepository().removeEpisodeCascade(byEnclosureURL: url)
        try? await context.database.feedRepository().insertMany([episodeRow])
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

    // MARK: - Subscribe capsule shape (8)

    @Test("Subscribe capsule radius cannot exceed half its 40 pt height")
    func subscribeButtonCapsuleShape() {
        let button = SubscriptionCapsuleButton()
        button.frame = CGRect(x: 0, y: 0, width: 160, height: 40)
        #expect(button.layer.cornerRadius <= button.frame.height / 2 + 0.5,
                "radius \(button.layer.cornerRadius) exceeds half the height — an oversized continuous radius renders as a pointed lens, not a capsule")
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

