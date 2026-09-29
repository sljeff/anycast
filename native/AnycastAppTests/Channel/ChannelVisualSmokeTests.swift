import UIKit
import Testing
import AnycastKit
@testable import Anycast

/// Hosted visual check for the channel fold (05 §6.1 S4 states: expanded /
/// collapsed). Presents a real ChannelViewController over the live shell,
/// captures the window at both fold extremes, and writes PNGs into the
/// app's tmp directory for offline inspection. Skips silently when the
/// startup DAG has no context yet or the seeded database has no
/// subscriptions (unseeded simulator).
@MainActor
struct ChannelVisualSmokeTests {

    @Test("Channel sheet fold: expanded and collapsed captures")
    func channelFoldScreenshots() async throws {
        guard let context = await Self.liveUIContext() else { return }
        guard let subscription = await Self.firstSubscription(context: context) else { return }
        guard let presenter = Self.rootPresenter() else { return }

        ChannelViewController.present(
            from: presenter,
            context: context,
            rssFeedURL: subscription.rssFeedUrl ?? "",
            seed: subscription
        )

        // Give the sheet presentation + initial RSS/palette work some time.
        try await Task.sleep(for: .seconds(4))

        let channelController = Self.presentedChannel(under: presenter)
        let collectionView = Self.firstCollectionView(in: channelController?.view)
        let geo = ChannelFoldGeometry(safeAreaTop: channelController?.view.safeAreaInsets.top ?? 59)

        await Self.captureWindow(name: "t2-channel-expanded")

        // Drive the fold: full collapse, clamped to what the content allows
        // (episode count is network-dependent).
        if let collectionView {
            let target = min(geo.maxShrink, collectionView.maxYOffset)
            collectionView.setContentOffset(CGPoint(x: 0, y: target), animated: true)
            try await Task.sleep(for: .milliseconds(1200))
            collectionView.delegate?.scrollViewDidScroll?(collectionView)
            try await Task.sleep(for: .milliseconds(400))
            await Self.captureWindow(name: "t2-channel-collapsed")
            // The pinned supplementary must remain visible (hosting the
            // whole single section keeps it pinned for the entire scroll) —
            // pinned, not just attached to a scrolled-away position.
            let supplementary = collectionView.visibleSupplementaryViews(
                ofKind: ChannelViewController.headerElementKind
            )
            let header = (supplementary.first as? ChannelHeaderView)?
                .convert(.init(x: 0, y: 0, width: 1, height: 1), to: nil).minY
            #expect(
                supplementary.count >= 1,
                "pinned channel header disappeared at offset \(collectionView.contentOffset.y)")
            if let header {
                #expect(header >= -1, "pinned channel header scrolled above the window (minY \(header))")
            }
            print(
                "[t2-visual] offset \(collectionView.contentOffset.y) target \(target) "
                    + "supplementary \(supplementary.count) windowMinY \(header ?? -1)"
            )
        }

        await MainActor.run { channelController?.dismiss(animated: false) }
        try await Task.sleep(for: .milliseconds(500))
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
    private static func firstSubscription(context: UIContext) async -> SubscriptionRow? {
        let subscriptions = (try? await context.database.subscriptionRepository().listAll()) ?? []
        return subscriptions.first
    }

    @MainActor
    private static func rootPresenter() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let window = scenes.flatMap(\.windows).first { $0.isKeyWindow }
        return window?.rootViewController?.topMostPresented()
    }

    @MainActor
    private static func presentedChannel(under presenter: UIViewController) -> ChannelViewController? {
        var top = presenter
        while let next = top.presentedViewController { top = next }
        // The sheet may be wrapped; find by walking the hierarchy.
        return findChannel(in: top) ?? (top as? ChannelViewController)
    }

    @MainActor
    private static func findChannel(in root: UIViewController) -> ChannelViewController? {
        if let channel = root as? ChannelViewController { return channel }
        for child in root.children {
            if let found = findChannel(in: child) { return found }
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
        print("[t2-visual] wrote \(url.path)")
    }
}

private extension UICollectionView {
    /// Maximum scrollable vertical offset (0 when content fits).
    var maxYOffset: CGFloat {
        max(0, contentSize.height + adjustedContentInset.bottom + adjustedContentInset.top - bounds.height)
    }
}
