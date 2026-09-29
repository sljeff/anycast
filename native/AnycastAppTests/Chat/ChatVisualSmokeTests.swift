import UIKit
import Testing
import AnycastKit
@testable import Anycast

/// Hosted visual smoke test (pattern: ChannelVisualSmokeTests /
/// SubtitlesDemoSmokeTests): mounts ChatViewController with an injected
/// conversation driven by an instant scripted transport, asserts the
/// ChatLayout list renders the bubbles, and writes a PNG for offline
/// inspection. Skips silently when the startup DAG has no context yet.
@MainActor
struct ChatVisualSmokeTests {

    final class InstantReplyTransport: ChatTransport {
        private(set) var requests = 0
        func chat(
            enclosureURL: String, input: String, history: [[String: String]]
        ) async -> ChatTransportOutcome {
            requests += 1
            return .reply("Demo answer \(requests) to your question about the episode.")
        }
    }

    @Test("Chat sheet renders bubbles from an injected conversation")
    func chatSheetRendersBubbles() async throws {
        guard let context = await Self.liveUIContext(),
              let presenter = Self.rootPresenter()
        else {
            print("App environment not ready; skipping chat smoke")
            return
        }

        let transport = InstantReplyTransport()
        let conversation = ChatConversation(transport: transport)
        let controller = ChatViewController(
            context: context,
            episodeTitle: "Demo episode — transcript chat",
            enclosureURL: "demo://enclosure",
            conversation: conversation
        )
        controller.modalPresentationStyle = .fullScreen
        presenter.present(controller, animated: false)
        controller.loadViewIfNeeded()

        await conversation.send("What is this episode about?", enclosureURL: "demo://enclosure")
        await conversation.send("And who is the host?", enclosureURL: "demo://enclosure")
        try await Task.sleep(for: .milliseconds(800))

        let collection = Self.firstCollectionView(in: controller.view)
        #expect(collection != nil, "ChatLayout collection view missing")
        if let collection {
            // 2 user messages + 2 AI replies = 4 bubbles. visibleCells is
            // viewport-dependent (other live-shell suites can transiently
            // resize the shared window mid-run) — assert it only as > 0.
            #expect(collection.numberOfSections == 1)
            #expect(collection.numberOfItems(inSection: 0) == 4)
            #expect(collection.visibleCells.count > 0)
        }
        #expect(controller.view.subviews.contains(where: { $0 is ChatInputBar }))

        await Self.captureWindow(name: "t6-chat")

        controller.dismiss(animated: false)
        try await Task.sleep(for: .milliseconds(300))
        // PopScope parity: dismissal cleared the conversation.
        #expect(conversation.messages.isEmpty)
    }

    // MARK: - Helpers

    private static func firstCollectionView(in view: UIView?) -> UICollectionView? {
        guard let view else { return nil }
        if let collectionView = view as? UICollectionView { return collectionView }
        for subview in view.subviews {
            if let found = firstCollectionView(in: subview) { return found }
        }
        return nil
    }

    private static func liveUIContext() async -> UIContext? {
        for _ in 0..<40 {
            if let context = (UIApplication.shared.delegate as? AppDelegate)?.environment.uiContext {
                return context
            }
            try? await Task.sleep(for: .milliseconds(500))
        }
        return nil
    }

    private static func rootPresenter() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let window = scenes.flatMap(\.windows).first { $0.isKeyWindow }
        // Top-most presenter: presenting from the bare root is refused while
        // another live-shell suite still has a sheet mid-presentation.
        return window?.rootViewController?.topMostPresented()
    }

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
        print("[t6-visual] wrote \(url.path)")
    }
}
