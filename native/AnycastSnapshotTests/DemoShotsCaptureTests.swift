import UIKit
import Testing
import AnycastKit
@testable import Anycast

/// Puppeteer for the demo-content screenshots (native/scripts/demo_shots.sh).
///
/// The test drives the live app (running in demo mode, see DemoNetwork.swift)
/// to each state, then hands over to the shell script: it writes
/// <dir>/<name>.ready and waits for <dir>/<name>.done, while the script takes a
/// real simulator screenshot (status bar included) in between. Gated by
/// DEMO_SHOTS_DIR (TEST_RUNNER_DEMO_SHOTS_DIR from xcodebuild), so a normal
/// test run does nothing.
@MainActor
struct DemoShotsCaptureTests {

    @Test("Demo content shots")
    func captureDemoShots() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard let directory = environment["DEMO_SHOTS_DIR"] ?? environment["TEST_RUNNER_DEMO_SHOTS_DIR"],
              !directory.isEmpty
        else {
            print("[demo-shots] gated: set DEMO_SHOTS_DIR to capture")
            return
        }
        let output = URL(fileURLWithPath: directory)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

        guard DemoMode.isActive else {
            Issue.record("demo mode is not active: pass ANYCAST_DEMO_CONTENT=1")
            return
        }
        var root: UIViewController?
        for _ in 0..<40 {
            if let found = Self.shellRoot() { root = found; break }
            try? await Task.sleep(for: .milliseconds(500))
        }
        guard let root, let context = await Self.liveContext() else {
            Issue.record("app shell not ready")
            return
        }
        PlusDebug.state = .member
        let style: UIUserInterfaceStyle = environment["TEST_RUNNER_DEMO_SHOTS_APPEARANCE"] == "dark"
            || environment["DEMO_SHOTS_APPEARANCE"] == "dark" ? .dark : .light
        for scene in UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }) {
            for window in scene.windows { window.overrideUserInterfaceStyle = style }
        }
        try await Self.settle(1.0)
        await Self.dismissAll()
        let transcriptPosition = try #require(context.playback.currentEpisode?.playedDuration)

        // 01 Inbox, paused
        context.tabs.select(0)
        _ = await Self.waitForInboxItems(in: root)
        try await Self.settle(2.5)
        try await Self.shot("01-inbox", in: output)

        // 02 Inbox with the hero playing (mini player shows pause)
        if let episode = context.playback.currentEpisode {
            await context.playback.playByEpisode(episode)
        }
        try await Self.settle(2.5)
        try await Self.shot("02-inbox-playing", in: output)

        // 03 Player main page at 1.25x with a sleep timer
        context.playback.setSpeed(1.25)
        context.sleepTimer.setCountdown(minutes: 30)
        context.openPlayerPage(from: root)
        try await Self.settle(2.0)
        for index in 0..<4 {
            Self.showPage(index, in: root)
            if let pager = Self.find(UIPageViewController.self, in: root),
               Self.find(PlayerMainPageViewController.self, in: pager.viewControllers?.first) != nil {
                break
            }
        }
        try await Self.settle(1.5)
        try await Self.shot("03-player", in: output)

        // 04 Transcript following, 05 long-press line menu
        Self.showPage(2, in: root)
        await context.playback.seek(transcriptPosition)
        try await Self.settle(1.0)
        if let subtitles = Self.find(SubtitlesPageViewController.self, in: root),
           let list = Self.firstCollectionView(in: subtitles.view) {
            for _ in 0..<40 where list.numberOfSections == 0 || list.numberOfItems(inSection: 0) == 0 {
                try? await Task.sleep(for: .milliseconds(250))
            }
        }
        try await Self.settle(2.0)
        try await Self.shot("04-transcript", in: output)

        // Ask AI: capture the completed conversation with both sets of jump buttons.
        if let subtitles = Self.find(SubtitlesPageViewController.self, in: root) {
            subtitles.openChat()
            try await Self.settle(1.5)
            if let chat = Self.find(ChatViewController.self, in: root) {
                let scriptData = try Data(contentsOf: URL.documentsDirectory.appending(path: "demo/api/chat.json"))
                let script = try JSONSerialization.jsonObject(with: scriptData) as? [String: Any]
                let followUp = try #require(script?["followUpQuestion"] as? String)
                let replies = try #require(script?["replies"] as? [[String: String]])
                try #require(replies.count >= 2)
                let enclosure = try #require(context.playback.currentEpisode?.enclosureUrl)
                let conversation = ChatThreadStore.shared.conversation(for: enclosure) {
                    APIClientChatTransport(api: context.api)
                }
                for (index, question) in [ChatExamplePrompts.summarize, followUp].enumerated() {
                    chat.sendExampleQuestion(question)
                    for _ in 0..<40 {
                        if !conversation.isLoading, conversation.messages.count == (index + 1) * 2 { break }
                        try await Self.settle(0.25)
                    }
                    try #require(!conversation.isLoading)
                    try #require(conversation.messages.count == (index + 1) * 2)
                    let reply = try #require(conversation.messages.last)
                    try #require(reply.author == .ai && !EpisodeChapters.timestamps(in: reply.text).isEmpty)
                    try #require(reply.text == replies[index]["result"])
                }
                try await Self.settle(1.0)
                try await Self.shot("05-ask-ai", in: output)
            }
            await Self.dismissAll()
        }

        // 07 Library: shows + Moments + recently played.
        context.tabs.select(0)
        let subscriptions = (try? await context.database.subscriptionRepository().listAll()) ?? []
        LibrarySheetViewController.present(
            from: Self.topPresenter(root), context: context,
            shows: ShowsShelfLayout.ordered(subscriptions), onSelect: { _ in }
        )
        try await Self.settle(1.5)
        if let sheet = Self.find(LibrarySheetViewController.self, in: root)?.sheetPresentationController {
            sheet.animateChanges { sheet.selectedDetentIdentifier = .large }
            try await Self.settle(1.0)
        }
        try await Self.shot("06-library-moments", in: output)
        await Self.dismissAll()

        // 08 Discover
        context.tabs.select(2)
        try await Self.settle(2.5)
        try await Self.shot("07-discover", in: output)

        // 09 Playlist queue
        context.tabs.select(1)
        try await Self.settle(3.0)
        try await Self.shot("08-playlist", in: output)

        // 10 Settings, 11 "Charts from" country picker
        context.tabs.select(0)
        AppSheets.presentExpand(SettingsViewController(context: context), from: Self.topPresenter(root))
        try await Self.settle(2.0)
        try await Self.shot("09-settings", in: output)
        if let settingsPage = Self.find(SettingsViewController.self, in: root) {
            let sheet = SettingsOptionSheetViewController(
                title: SettingsPageModel.title(for: .country),
                options: SettingsPageModel.sortedCountries().map { ($0.name, $0.code) },
                selectedCode: context.settingsBox.current.countryCode
            )
            sheet.present(from: settingsPage)
            try await Self.settle(1.5)
            try await Self.shot("10-charts-from", in: output)
        }
        await Self.dismissAll()

        // 12 Import OPML confirm sheet with our own demo subscriptions
        let entries = subscriptions.dropLast(2).compactMap { show -> OPMLParser.Entry? in
            guard let title = show.title, let url = show.rssFeedUrl else { return nil }
            return OPMLParser.Entry(title: title, xmlURL: url)
        }
        let plan = ImportPlan(entries: entries, alreadyFollowed: 2)
        root.present(ImportSheetViewController(context: context, plan: plan, filename: "My Podcasts.opml"), animated: false)
        try await Self.settle(1.5)
        try await Self.shot("11-import-opml", in: output)
        await Self.dismissAll()

        FileManager.default.createFile(atPath: output.appendingPathComponent("finished").path, contents: Data())
    }

    // MARK: - Hand-over to the script

    private static func shot(_ name: String, in directory: URL) async throws {
        let ready = directory.appendingPathComponent("\(name).ready")
        let done = directory.appendingPathComponent("\(name).done")
        FileManager.default.createFile(atPath: ready.path, contents: Data())
        for _ in 0..<120 where !FileManager.default.fileExists(atPath: done.path) {
            try? await Task.sleep(for: .milliseconds(250))
        }
        #expect(FileManager.default.fileExists(atPath: done.path), "shot \(name) was not taken")
    }

    // MARK: - Navigation helpers (small copy of ScreenBaselineCaptureTests')

    private static func shellRoot() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        return scenes.flatMap(\.windows).first { $0.isKeyWindow }?.rootViewController
    }

    private static func topPresenter(_ root: UIViewController) -> UIViewController {
        var top = root
        while let next = top.presentedViewController { top = next }
        return top
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

    private static func waitForInboxItems(in root: UIViewController, timeout: Double = 10) async -> UICollectionView? {
        guard let inbox = find(InboxPageViewController.self, in: root),
              let list = firstCollectionView(in: inbox.view)
        else { return nil }
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if list.numberOfSections >= 3, list.numberOfItems(inSection: list.numberOfSections - 2) > 0 {
                return list
            }
            try? await Task.sleep(for: .milliseconds(250))
        }
        return nil
    }

    /// Moves the pager the way a capsule tap does, so the capsule highlight
    /// follows the page.
    private static func showPage(_ index: Int, in root: UIViewController) {
        find(PlayerPageContainer.self, in: root)?.selectPage(index)
    }

    private static func find<T: UIViewController>(_ type: T.Type, in root: UIViewController?) -> T? {
        guard let root else { return nil }
        if let match = root as? T { return match }
        for child in root.children {
            if let match = find(type, in: child) { return match }
        }
        return find(type, in: root.presentedViewController)
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
