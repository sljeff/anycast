import UIKit
import Testing
import AnycastKit
@testable import Anycast

/// Reference baselines for the M3 screen states (05 §6.1 S1–S21).
///
/// These are REFERENCE captures, not pixel assertions: 05 §6.1 prescribes
/// structural comparison against the Flutter build per OS, and the accepted
/// A1–A9 adaptations make byte diffs meaningless. Each capture is written to
/// `__Snapshots__/ScreenBaselineCaptureTests/iOS-<major>/` and committed; a
/// test fails only when the capture could not be produced at all.
///
/// Gated: every test writes the committed baseline PNGs, so a plain
/// `xcodebuild test` on the Anycast scheme would silently churn them — the
/// suite only runs when SNAPSHOT_CAPTURE=1 is set in the test process
/// (`TEST_RUNNER_SNAPSHOT_CAPTURE=1 xcodebuild … test`, per native/README).
///
/// Data dependence: with the db_smoke fixture seeded (native/README) every
/// state renders with real content; a data precondition that trips during a
/// gated re-record records an issue (a silently skipped capture would leave
/// the committed baseline describing an older build). Network-fed screens
/// (Channel/Search/Discover) capture whatever the live fetch returned — the
/// reference is the layout, not the data.
@MainActor
struct ScreenBaselineCaptureTests {

    // MARK: - Shell / tabs

    @Test("S1 Inbox (shell: tab strip, cards, mini player)")
    func captureInbox() async throws {
        try await Self.withRoot { root in
            // The inbox reads its list asynchronously after the shell
            // installs; capture only once the seeded rows have landed —
            // an unseeded capture would overwrite the seeded baseline
            // with the empty state.
            guard (await Self.waitForInboxItems(in: root)) != nil else {
                Self.missingBaselineInput("seeded inbox rows (S1)")
                return
            }
            try await Self.capture("S1-inbox")
        }
    }

    @Test("S2 Inbox card expanded (action strip)")
    func captureInboxCardExpanded() async throws {
        try await Self.withRoot { root in
            guard let inbox = Self.find(InboxPageViewController.self, in: root) else {
                Self.missingBaselineInput("InboxPageViewController (S2)")
                return
            }
            guard let list = await Self.waitForInboxItems(in: root) else {
                Self.missingBaselineInput("seeded inbox rows (S2)")
                return
            }
            _ = inbox
            list.layoutIfNeeded()
            let visibleCard = list.indexPathsForVisibleItems.sorted().compactMap {
                list.cellForItem(at: $0) as? EpisodeCardCell
            }.first
            guard let cell = visibleCard else {
                Self.missingBaselineInput("a visible episode card (S2)")
                return
            }
            // The card's own tap closure is the expand path (the Dart whole-card
            // tap); the collection view selection delegate is not involved.
            cell.onCardTap?()
            try await Self.settle(0.8)
            try await Self.capture("S2-inbox-card-expanded")
        }
    }

    @Test("S3 Subscriptions list (library tab since the v2 IA flip)")
    func captureSubscriptions() async throws {
        try await Self.withRoot { root in
            guard let context = await Self.liveContext() else {
                Self.missingBaselineInput("live UIContext (S3)")
                return
            }
            context.tabs.select(2)
            try await Self.settle(1.2)
            try await Self.capture("S3-subscriptions")
            context.tabs.select(0)
        }
    }

    @Test("S6 Playlists (progress backdrop, download states)")
    func capturePlaylists() async throws {
        try await Self.withRoot { root in
            guard let context = await Self.liveContext() else {
                Self.missingBaselineInput("live UIContext")
                return
            }
            context.tabs.select(1)
            try await Self.settle(1.2)
            try await Self.capture("S6-playlists")
            context.tabs.select(0)
        }
    }

    @Test("Library screen (v2 tab; replaces the retired S8 Discover slot)")
    func captureLibrary() async throws {
        try await Self.withRoot { root in
            guard let context = await Self.liveContext() else {
                Self.missingBaselineInput("live UIContext")
                return
            }
            context.tabs.select(2)
            try await Self.settle(1.5)
            try await Self.capture("Library-library")
            context.tabs.select(0)
            try await Self.settle(0.5)
        }
    }

    // MARK: - Player (S11/S12/S13/S14)

    @Test("S11–S14 player pages and the lyrics demo state")
    func capturePlayerPages() async throws {
        try await Self.withRoot { root in
            guard let context = await Self.liveContext() else {
                Self.missingBaselineInput("live UIContext")
                return
            }
            guard context.playback.currentEpisode != nil || !context.playback.queue.isEmpty else {
                Self.missingBaselineInput("a seeded player pointer/queue (S11–S14)")
                return
            }
            context.openPlayerPage(from: root)
            try await Self.settle(2.0)
            try await Self.capture("S12-player-main")

            Self.showPage(0, in: root)
            try await Self.settle(0.8)
            try await Self.capture("S11-player-settings")

            Self.showPage(2, in: root)
            try await Self.settle(0.8)
            try await Self.capture("S13-player-subtitles")

            // Injected bilingual document drives the ready state (the demo
            // hook shared with AnycastAppTests/Subtitles).
            guard let subtitles = Self.find(SubtitlesPageViewController.self, in: root) else {
                Self.missingBaselineInput("SubtitlesPageViewController (S13b/S14)")
                return
            }
            subtitles.activateDemoDocument()
            try await Self.settle(1.5)
            try await Self.capture("S13b-lyrics-ready")
            // A drag-selection frame: the time bar rides the dragged line.
            guard let lyrics = Self.firstCollectionView(in: subtitles.view) else {
                Self.missingBaselineInput("lyrics collection view (S14)")
                return
            }
            lyrics.delegate?.scrollViewWillBeginDragging?(lyrics)
            lyrics.setContentOffset(
                CGPoint(x: 0, y: lyrics.contentOffset.y + 120), animated: false
            )
            lyrics.delegate?.scrollViewDidEndDragging?(lyrics, willDecelerate: false)
            try await Self.settle(0.6)
            try await Self.capture("S14-lyrics-drag-bar")
        }
    }

    // MARK: - Sheets

    @Test("S16 Settings (translation off/on variants are both reachable live)")
    func captureSettings() async throws {
        try await Self.withRoot { root in
            guard let context = await Self.liveContext() else {
                Self.missingBaselineInput("live UIContext")
                return
            }
            AppSheets.presentExpand(SettingsViewController(context: context), from: root)
            try await Self.settle(1.5)
            try await Self.capture("S16-settings")
        }
    }

    @Test("S7 History dialog")
    func captureHistoryDialog() async throws {
        try await Self.withRoot { root in
            guard let context = await Self.liveContext() else {
                Self.missingBaselineInput("live UIContext")
                return
            }
            HistoryDialogViewController.present(from: root, context: context)
            try await Self.settle(1.5)
            try await Self.capture("S7-history")
        }
    }

    @Test("S19 Import/Export dialog and import instructions")
    func captureImportExport() async throws {
        try await Self.withRoot { root in
            guard let context = await Self.liveContext() else {
                Self.missingBaselineInput("live UIContext")
                return
            }
            ImportExportDialogViewController.present(from: root, context: context)
            try await Self.settle(1.2)
            try await Self.capture("S19a-import-export")
        }
        try await Self.withRoot { root in
            ImportInstructionsViewController.present(from: root)
            try await Self.settle(1.2)
            try await Self.capture("S19b-import-instructions")
        }
    }

    @Test("S17/S18/S20/S21 login sheet (the same sheet serves the 401 path)")
    func captureLogin() async throws {
        try await Self.withRoot { root in
            guard let context = await Self.liveContext() else {
                Self.missingBaselineInput("live UIContext")
                return
            }
            context.presentLogin()
            try await Self.settle(1.5)
            try await Self.capture("S17-login")
        }
    }

    @Test("S5 Detail sheet")
    func captureDetail() async throws {
        try await Self.withRoot { root in
            DetailViewController.present(
                from: root,
                episode: .init(
                    title: "Reference episode — detail sheet layout",
                    channelTitle: "Reference channel",
                    pubDateMilliseconds: 1_756_000_000_000,
                    imageURL: nil,
                    rssFeedURL: "https://example.com/feed.rss",
                    enclosureURL: "https://example.com/episode.mp3",
                    descriptionHTML: "<p>Reference show notes with a <a href=\"https://example.com\">link</a>.</p>"
                ),
                actions: [],
                htmlRenderer: HTMLContentRenderer()
            )
            // The first WebKit HTML parse spins up a process (~3s) — poll
            // for the description instead of settling on a fixed clock. A
            // timed-out poll would capture a blank description over a good
            // baseline, so it records and skips instead.
            var descriptionLanded = false
            let deadline = Date().addingTimeInterval(10)
            while Date() < deadline {
                if let detail = Self.find(DetailViewController.self, in: root),
                   let text = Self.firstTextView(in: detail.view),
                   text.attributedText.length > 0 {
                    descriptionLanded = true
                    break
                }
                try? await Task.sleep(for: .milliseconds(250))
            }
            guard descriptionLanded else {
                Self.missingBaselineInput("parsed Detail description (S5)")
                return
            }
            try await Self.settle(0.5)
            try await Self.capture("S5-detail")
        }
    }

    @Test("S4 Channel expanded and collapsed header")
    func captureChannel() async throws {
        try await Self.withRoot { root in
            guard let context = await Self.liveContext() else {
                Self.missingBaselineInput("live UIContext")
                return
            }
            let subscriptions = (try? await context.database.subscriptionRepository().listAll()) ?? []
            guard let subscription = subscriptions.first, let rssURL = subscription.rssFeedUrl else {
                Self.missingBaselineInput("a seeded subscription (S4)")
                return
            }
            ChannelViewController.present(
                from: root, context: context, rssFeedURL: rssURL, seed: subscription
            )
            try await Self.settle(4.0)
            try await Self.capture("S4a-channel-expanded")

            guard let channel = Self.find(ChannelViewController.self, in: root),
                  let list = Self.firstCollectionView(in: channel.view)
            else {
                Self.missingBaselineInput("channel list for the collapsed frame (S4b)")
                return
            }
            let maxOffset = max(
                0,
                list.contentSize.height + list.adjustedContentInset.bottom
                    + list.adjustedContentInset.top - list.bounds.height
            )
            list.setContentOffset(CGPoint(x: 0, y: maxOffset), animated: false)
            list.delegate?.scrollViewDidScroll?(list)
            try await Self.settle(0.8)
            try await Self.capture("S4b-channel-collapsed")
        }
    }

    @Test("S9 Search sheet (channels/episodes tabs)")
    func captureSearch() async throws {
        try await Self.withRoot { root in
            guard let context = await Self.liveContext() else {
                Self.missingBaselineInput("live UIContext")
                return
            }
            SearchPageViewController.present(from: root, context: context, searchText: "news")
            try await Self.settle(4.0)
            try await Self.capture("S9-search")
        }
    }

    @Test("S15 Chat sheet with a scripted reply")
    func captureChat() async throws {
        try await Self.withRoot { root in
            guard let context = await Self.liveContext() else {
                Self.missingBaselineInput("live UIContext")
                return
            }
            let transport = ScriptedChatTransport()
            let conversation = ChatConversation(transport: transport)
            let controller = ChatViewController(
                context: context,
                episodeTitle: "Reference episode — transcript chat",
                enclosureURL: "demo://enclosure",
                conversation: conversation
            )
            AppSheets.presentExpand(controller, from: root)
            try await Self.settle(1.0)
            await conversation.send("What does this episode argue?", enclosureURL: "demo://enclosure")
            try await Self.settle(1.5)
            try await Self.capture("S15-chat")
        }
    }

    // MARK: - Helpers

    /// A deterministic scripted transport for the chat reference capture.
    final class ScriptedChatTransport: ChatTransport {
        func chat(
            enclosureURL: String, input: String, history: [[String: String]]
        ) async -> ChatTransportOutcome {
            .reply("The episode argues that reference layouts should be captured, not diffed.")
        }
    }

    /// A data-dependent precondition tripped during a gated re-record: the
    /// committed baseline is NOT refreshed while the test stays green — it
    /// keeps describing an older build (or a wrong screen would overwrite
    /// it). Record it so a re-record run fails loudly instead.
    private static func missingBaselineInput(_ what: String) {
        Issue.record("baseline input missing — capture skipped: \(what)")
    }

    /// Presents nothing itself: prepares a clean root, runs `body`, then
    /// tears every sheet down so captures do not bleed into each other.
    private static func withRoot(_ body: (UIViewController) async throws -> Void) async throws {
        // Capture gate: see the class doc — baseline writing is an explicit
        // re-record step, never a side effect of an ordinary test run. Early
        // return (not XCTSkip): Swift Testing records a thrown XCTSkip as a
        // failure on this toolchain, and the suite's convention for
        // not-runnable states is a silent vacuous pass.
        let captureEnabled = ProcessInfo.processInfo.environment["SNAPSHOT_CAPTURE"] == "1"
            || ProcessInfo.processInfo.environment["TEST_RUNNER_SNAPSHOT_CAPTURE"] == "1"
        guard captureEnabled else {
            print("[snapshot] gated: set SNAPSHOT_CAPTURE=1 to re-record committed baselines")
            return
        }
        // The window can still be attaching when a single test runs alone —
        // poll instead of skipping the capture silently.
        var root: UIViewController?
        for _ in 0..<40 {
            if let found = shellRoot() { root = found; break }
            try? await Task.sleep(for: .milliseconds(500))
        }
        guard let root else {
            Issue.record("app shell not ready; no capture produced")
            return
        }
        await dismissAll()
        try await body(root)
        await dismissAll()
    }

    /// The shell root (RootViewController), base for every presentation.
    private static func shellRoot() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let window = scenes.flatMap(\.windows).first { $0.isKeyWindow }
        return window?.rootViewController
    }

    private static func liveContext() async -> UIContext? {
        for _ in 0..<40 {
            if let context = (UIApplication.shared.delegate as? AppDelegate)?.environment.uiContext {
                return context
            }
            try? await Task.sleep(for: .milliseconds(500))
        }
        return nil
    }

    private static func dismissAll() async {
        guard let base = shellRoot() else { return }
        while let presented = base.presentedViewController {
            presented.dismiss(animated: false)
            try? await Task.sleep(for: .milliseconds(150))
        }
    }

    private static func settle(_ seconds: Double) async throws {
        try await Task.sleep(for: .seconds(seconds))
    }

    /// Polls the inbox list until it has rows (the DB read is async). Returns
    /// the list once non-empty, or nil after the timeout (unseeded runs).
    private static func waitForInboxItems(
        in root: UIViewController, timeout: Double = 8
    ) async -> UICollectionView? {
        guard let inbox = find(InboxPageViewController.self, in: root),
              let list = firstCollectionView(in: inbox.view)
        else { return nil }
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if list.numberOfItems(inSection: 0) > 0 { return list }
            try? await Task.sleep(for: .milliseconds(250))
        }
        return nil
    }

    /// Shows a player page by walking the pager's data source — deterministic
    /// and independent of the capsule's private tap plumbing.
    private static func showPage(_ index: Int, in root: UIViewController) {
        guard let container = find(PlayerPageContainer.self, in: root),
              let pager = find(UIPageViewController.self, in: container),
              var current = pager.viewControllers?.first
        else { return }
        if index == 0 {
            // Page 0: walk back until the data source runs out.
            var steps = 0
            while steps < 8, let previous = pager.dataSource?.pageViewController(
                pager, viewControllerBefore: current
            ) {
                current = previous
                steps += 1
            }
        } else if index > 0 {
            var steps = 0
            while steps < index, let next = pager.dataSource?.pageViewController(
                pager, viewControllerAfter: current
            ) {
                current = next
                steps += 1
            }
        }
        pager.setViewControllers([current], direction: .forward, animated: false)    }

    // MARK: - Capture

    private static func capture(
        _ name: String, file: StaticString = #filePath
    ) async throws {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        guard let window = scenes.flatMap(\.windows).first(where: \.isKeyWindow) else {
            Issue.record("no key window for capture \(name)")
            return
        }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 2
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(bounds: window.bounds, format: format)
        var image = renderer.image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        if image.isUniformColor {
            // The render server can return a black drawHierarchy frame while a
            // transition is pending; layer.render composites on the CPU and
            // does not depend on the window being screen-visible.
            image = renderer.image { ctx in
                window.layer.render(in: ctx.cgContext)
            }
        }
        // A still-uniform frame is a blank screen, not a usable reference.
        #expect(!image.isUniformColor, "capture \(name) produced a blank frame")
        let data = try #require(image.pngData())

        let fileURL = URL(fileURLWithPath: file.description)
        let directory = fileURL.deletingLastPathComponent()
            .appendingPathComponent("__Snapshots__")
            .appendingPathComponent(fileURL.deletingPathExtension().lastPathComponent)
            .appendingPathComponent(SnapshotBaseline.osDirectoryName)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("\(name).png")
        try data.write(to: url)
        #expect(FileManager.default.fileExists(atPath: url.path))
        print("[screens] wrote \(url.path) (\(data.count) bytes)")
    }

    // MARK: - Hierarchy lookups

    private static func find<T: UIViewController>(_ type: T.Type, in root: UIViewController?) -> T? {
        guard let root else { return nil }
        if let match = root as? T { return match }
        for child in root.children {
            if let match = find(type, in: child) { return match }
        }
        if let match = find(type, in: root.presentedViewController) { return match }
        return nil
    }

    private static func firstTextView(in view: UIView?) -> UITextView? {
        guard let view else { return nil }
        if let text = view as? UITextView { return text }
        for subview in view.subviews {
            if let match = firstTextView(in: subview) { return match }
        }
        return nil
    }

    private static func firstCollectionView(in view: UIView?) -> UICollectionView? {
        guard let view else { return nil }
        if let list = view as? UICollectionView { return list }
        for subview in view.subviews {
            if let match = firstCollectionView(in: subview) { return match }
        }
        return nil
    }

}

private extension UIImage {
    /// Whether every pixel is the same color — the signature of a failed
    /// `drawHierarchy` capture (a solid black frame), not of real content.
    var isUniformColor: Bool {
        guard let cgImage else { return false }
        var pixels = [UInt8](repeating: 0, count: 4 * 4 * 4)
        guard let context = CGContext(
            data: &pixels, width: 4, height: 4,
            bitsPerComponent: 8, bytesPerRow: 16,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return false }
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: 4, height: 4))
        return pixels.allSatisfy { $0 == pixels[0] }
    }
}
