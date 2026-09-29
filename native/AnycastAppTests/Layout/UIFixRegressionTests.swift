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
/// 3. Discover category indicator parked at the strip's left edge until
///    the first selection change.
/// 4. Playlist card progress strip running through the card's rounded
///    corners.
/// 5. Playlist Detail sheet play button rendered as an empty white circle
///    (blank strip icon reused outside the strip's live overlay).
/// 6. Inbox card expand leaving item heights un-resized (strip overflowing
///    neighbor cards) and later taps failing to expand.
/// 7. Mini player nested capsule-in-capsule when hosted by the iOS 26+
///    tab accessory (the system glass must be the only chrome).
/// 8. Channel subscribe button spinning through the feed fetch and
///    rendering as a pointed lens instead of a capsule.
///
/// Runs against the live shell with the seeded fixture; skips when the
/// shell, the seed, or (Discover only) the category network fetch is
/// absent. Serialized: the suite drives the SHARED key window.
@MainActor
@Suite(.serialized)
struct UIFixRegressionTests {

    // MARK: - Player page distribution (1) + thumb height (2)

    @Test("Player main page: square cover and five equal spaceEvenly gaps")
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
        try await Self.settle(window, seconds: 0.5)

        guard let cover = Self.firstView(
            in: page, where: { ($0 as? UIImageView)?.accessibilityLabel == "Episode artwork" }
        ), let titleBar = Self.firstView(
            in: page, where: { ($0 as? UIButton)?.accessibilityLabel == "Open channel" }
        )?.superview, let progress = Self.firstView(
            in: page, where: { $0 is PlayerProgressBarView }
        ), let playPause = Self.firstView(
            in: page, where: { ($0 as? UIButton)?.accessibilityLabel == "Play or pause" }
        )?.superview else {
            Issue.record("player main page blocks not found"); return
        }

        // Cover is square at the content width (the old cap vs stretch
        // conflict squashed it below the design width).
        #expect(abs(cover.bounds.width - cover.bounds.height) < 1.5,
                "cover is not square: \(cover.bounds)")

        func frameInPage(_ v: UIView) -> CGRect { page.convert(v.bounds, from: v) }
        let coverFrame = frameInPage(cover)
        let titleFrame = frameInPage(titleBar)
        let progressFrame = frameInPage(progress)
        let transportFrame = frameInPage(playPause)

        // The four content blocks + page edges must share the height
        // through five EQUAL gaps (spaceEvenly).
        let gap = { (a: CGFloat, b: CGFloat) in b - a }
        let gaps: [CGFloat] = [
            gap(8, coverFrame.minY),                       // above the cover (8 pt stack margin)
            gap(coverFrame.maxY, titleFrame.minY),
            gap(titleFrame.maxY, progressFrame.minY),
            gap(progressFrame.maxY, transportFrame.minY),
            gap(transportFrame.maxY, page.bounds.height - 8), // below the transport (8 pt margin)
        ]
        for (index, value) in gaps.enumerated() {
            #expect(abs(value - gaps[0]) < 2.0,
                    "gap \(index) (\(value)) is not even with gap 0 (\(gaps[0]))")
        }
        #expect(gaps[0] > 8, "content is crammed against the sheet top: \(gaps[0])")
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
        // circle keeps the path a full 40 pt wide — a plain rounded rect
        // clamps its corner radius to width/2 and rendered a square stub.
        bar.update(positionMilliseconds: 1_200, bufferedMilliseconds: 0, durationMilliseconds: 120_000)
        bar.layoutIfNeeded()
        let shapes = (bar.barContainer.layer.sublayers ?? []).compactMap { $0 as? CAShapeLayer }
        guard let playedBox = shapes[2].path?.boundingBox else {
            Issue.record("played layer has no path near position zero"); return
        }
        #expect(abs(playedBox.width - 40) < 0.5,
                "narrow played segment is \(playedBox.width) pt wide — the head is not a full circle")
        #expect(playedBox.minX < 0,
                "the head circle should extend past the track's leading cap (the container clips it)")

        // The container does the clipping (corner radius == half the bar).
        #expect(bar.barContainer.clipsToBounds, "bar container does not clip")
        #expect(abs(bar.barContainer.layer.cornerRadius - 20) < 0.5,
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

        // Bar occupies view y 20…60; head circle centered at (25, 40).
        #expect(isWhite(15, 40), "head mid-height not filled: px=\(channels(15, 40))")
        #expect(!isWhite(2, 22), "white reaches the bar's top-left — square stub or clip leak: px=\(channels(2, 22))")
        #expect(!isWhite(2, 59), "white reaches the bar's bottom-left — square stub or clip leak: px=\(channels(2, 59))")
        #expect(!isWhite(35, 40), "white extends past the round head: px=\(channels(35, 40))")

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

    // MARK: - Discover indicator (3)

    @Test("Discover indicator sits under the selected category on first layout")
    func discoverIndicatorInitialPosition() async throws {
        guard let context = await Self.liveContext(),
              let window = Self.keyWindow() else {
            print("[uifix] shell not ready; skipping"); return
        }
        context.tabs.select(2)
        try await Self.settle(window, seconds: 3)
        defer { context.tabs.select(0) }

        guard let discover = Self.find(DiscoverViewController.self, in: window.rootViewController),
              let strip = Self.firstView(in: discover.view, where: { $0 is UnderlineTabBarView }),
              let tabBar = strip as? UnderlineTabBarView,
              let label = Self.firstView(
                  in: tabBar, where: { view in
                      guard let label = view as? UILabel else { return false }
                      return !(label.text ?? "").isEmpty
                  }
              ) else {
            print("[uifix] discover categories not loaded (network?); skipping"); return
        }
        try await Self.settle(window, seconds: 0.5)

        let indicatorMidX = tabBar.convert(
            tabBar.indicator.frame, from: tabBar.indicator.superview
        ).midX
        let labelMidX = tabBar.convert(label.bounds, from: label).midX
        #expect(abs(indicatorMidX - labelMidX) < 2.0,
                "indicator (\(indicatorMidX)) not centered under the selected label (\(labelMidX))")
        await Self.capture(window, name: "uifix-discover")
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
        defer { list.dismiss(animated: false) }

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
        let iconSize = play.currentImage?.size ?? .zero
        #expect(iconSize.width > 1 && iconSize.height > 1,
                "detail play button icon is blank (\(iconSize))")
        await Self.capture(window, name: "uifix-detail-play-icon")
    }

    // MARK: - Inbox expand reliability (6)

    @Test("Inbox expand: every toggle resizes item heights, no stuck cards")
    func inboxExpandReliability() async throws {
        guard let context = await Self.liveContext(),
              let window = Self.keyWindow() else {
            print("[uifix] shell not ready; skipping"); return
        }
        context.tabs.select(0)
        try await Self.settle(window, seconds: 1.5)

        guard let inbox = Self.find(InboxPageViewController.self, in: window.rootViewController),
              let collection = Self.firstView(in: inbox.view, where: { $0 is UICollectionView })
                as? UICollectionView,
              collection.numberOfItems(inSection: 0) >= 3 else {
            print("[uifix] seeded inbox missing; skipping"); return
        }

        func height(at item: Int) -> CGFloat {
            collection.collectionViewLayout.layoutAttributesForItem(
                at: IndexPath(item: item, section: 0)
            )?.frame.height ?? 0
        }
        let collapsed = height(at: 0)

        // Walk a toggle sequence across three cards — the shipped defect
        // surfaced as a later toggle failing to resize (or to expand at
        // all) after an earlier expand/collapse.
        let sequence = [0, 1, 2, 1, 0, 2, 0]
        for (step, item) in sequence.enumerated() {
            guard let cell = collection.cellForItem(at: IndexPath(item: item, section: 0))
                    as? EpisodeCardCell else {
                Issue.record("step \(step): cell \(item) not visible"); continue
            }
            cell.onCardTap?()
            try await Self.settle(window, seconds: 0.5)

            let expandedHeight = height(at: item)
            #expect(expandedHeight > collapsed + 40,
                    "step \(step): item \(item) expanded to \(expandedHeight) (collapsed \(collapsed))")
            for other in 0..<min(3, collection.numberOfItems(inSection: 0)) where other != item {
                #expect(abs(height(at: other) - collapsed) < 8,
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
                await Self.capture(window, name: "uifix-inbox-expanded")
            }
        }
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
