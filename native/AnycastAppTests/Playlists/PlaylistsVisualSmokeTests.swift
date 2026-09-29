import UIKit
import Testing
import AnycastKit
@testable import Anycast

/// Hosted visual smoke for the playlists tab (05 §6.1 S6 — progress-backdrop
/// cards, download states; S7 history dialog): presents the page over the
/// live shell with the db_smoke-seeded queue, captures the list, an
/// expanded-strip state, a programmatic reorder, and the history dialog.
/// Skips silently when the startup DAG has no context or the seeded queue
/// is empty (unseeded simulator).
@MainActor
struct PlaylistsVisualSmokeTests {

    @Test("Playlists tab: list, expanded strip, reorder, history dialog")
    func playlistsScreenshots() async throws {
        guard let context = await Self.liveUIContext() else { return }
        let queue = (try? await context.database.playlistRepository()
            .listEpisodes(playlistId: ChannelPlaylistLogic.defaultPlaylistID)) ?? []
        guard queue.count >= 2, let presenter = Self.rootPresenter() else { return }

        // Show tab 1 and let the page build.
        context.tabs.select(1)
        try await Task.sleep(for: .seconds(2))

        let playlistsPage = Self.findPlaylistsPage(from: presenter)
        let list = Self.currentListPage(in: playlistsPage)
        await Self.captureWindow(name: "t3-playlists-list")
        guard let list else { return }

        // Expanded strip state (card tap toggles the action buttons).
        if let collectionView = Self.firstCollectionView(in: list.view) {
            let firstVisible = collectionView.indexPathsForVisibleItems
                .filter { $0.section == 0 }
                .sorted { $0.item < $1.item }
                .first
            if let firstVisible,
               let cell = collectionView.cellForItem(at: firstVisible) as? EpisodeCardCell {
                cell.onCardTap?()
                try await Task.sleep(for: .milliseconds(700))
                await Self.captureWindow(name: "t3-playlists-expanded")

                // The a11y reorder path doubles as the programmatic move:
                // head down one slot (K26 + source-swap route).
                list.performReorder(from: 0, to: 1)
                try await Task.sleep(for: .milliseconds(800))
                await Self.captureWindow(name: "t3-playlists-reordered")

                // Assert the reorder persisted, then restore the seeded
                // order — this writes the LIVE app container, and a leftover
                // reorder would skew later runs' head-episode assumptions.
                let after = try? await context.database.playlistRepository()
                    .listEpisodes(playlistId: ChannelPlaylistLogic.defaultPlaylistID)
                let beforeURLs = queue.compactMap(\.enclosureUrl)
                if beforeURLs.count >= 2, let afterURLs = after?.compactMap(\.enclosureUrl),
                   afterURLs.count >= 2 {
                    #expect(
                        afterURLs[0] == beforeURLs[1] && afterURLs[1] == beforeURLs[0],
                        "reorder did not persist head-down-one-slot")
                }
                // Restore the seeded order. Errors propagate: a silently
                // failed restore must fail the test, not the next run.
                for (index, row) in queue.enumerated() {
                    try await context.database.playlistRepository()
                        .insertOrUpdateByIndex(
                            row, playlistId: ChannelPlaylistLogic.defaultPlaylistID, index: index)
                }
            }
        }

        // History dialog (presented the way Settings will present it).
        let history = HistoryDialogViewController(context: context)
        history.modalPresentationStyle = .overCurrentContext
        history.modalTransitionStyle = .crossDissolve
        presenter.present(history, animated: true)
        try await Task.sleep(for: .seconds(2))
        await Self.captureWindow(name: "t3-history-dialog")
        await MainActor.run { history.dismiss(animated: false) }
        try await Task.sleep(for: .milliseconds(400))
    }

    // MARK: - Helpers

    @MainActor
    private static func liveUIContext() async -> UIContext? {
        for _ in 0..<40 {
            if let context = (UIApplication.shared.delegate as? AppDelegate)?.environment.uiContext {
                return context
            }
            try? await Task.sleep(for: .milliseconds(500))
        }
        return nil
    }

    @MainActor
    private static func rootPresenter() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let window = scenes.flatMap(\.windows).first { $0.isKeyWindow }
        return window?.rootViewController?.topMostPresented()
    }

    @MainActor
    private static func findPlaylistsPage(from root: UIViewController) -> PlaylistsPageViewController? {
        if let page = root as? PlaylistsPageViewController { return page }
        for child in root.children {
            if let found = findPlaylistsPage(from: child) { return found }
        }
        if let presented = root.presentedViewController {
            return findPlaylistsPage(from: presented)
        }
        return nil
    }

    @MainActor
    private static func currentListPage(in page: PlaylistsPageViewController?) -> PlaylistEpisodeListViewController? {
        guard let page else { return nil }
        for child in page.children {
            if let list = child as? PlaylistEpisodeListViewController { return list }
            if let pager = child as? UIPageViewController,
               let current = pager.viewControllers?.first as? PlaylistEpisodeListViewController {
                return current
            }
        }
        return nil
    }

    @MainActor
    private static func firstCollectionView(in view: UIView?) -> UICollectionView? {
        guard let view else { return nil }
        if let collectionView = view as? UICollectionView { return collectionView }
        for subview in view.subviews {
            if let found = firstCollectionView(in: subview) { return found }
        }
        return nil
    }

    @MainActor
    private static func captureWindow(name: String) async {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        guard let window = scenes.flatMap(\.windows).first(where: \.isKeyWindow) else { return }
        let format = UIGraphicsImageRendererFormat()
        format.scale = window.screen.scale
        let renderer = UIGraphicsImageRenderer(bounds: window.bounds, format: format)
        let image = renderer.image { context in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        guard let data = image.pngData() else { return }
        let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("\(name).png")
        try? data.write(to: url)
        print("[t3-visual] wrote \(url.path)")
    }
}
