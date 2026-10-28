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

    final class RecordingTransport: ChatTransport {
        private(set) var inputs: [String] = []
        func chat(
            enclosureURL: String, input: String, history: [[String: String]]
        ) async -> ChatTransportOutcome {
            inputs.append(input)
            return .reply("ok")
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
        #expect(controller.inputBar.isDescendant(of: controller.view))

        await Self.captureWindow(name: "t6-chat")

        controller.dismiss(animated: false)
        try await Task.sleep(for: .milliseconds(300))
        // The thread belongs to the episode: dismissal keeps it.
        #expect(conversation.messages.count == 4)
    }

    @Test("Draft question pre-fills the composer without sending; example 3 sends the current line")
    func draftAndExampleQuestions() async throws {
        guard let context = await Self.liveUIContext(),
              let presenter = Self.rootPresenter()
        else {
            print("App environment not ready; skipping chat draft smoke")
            return
        }

        let transport = RecordingTransport()
        let conversation = ChatConversation(transport: transport)
        let controller = ChatViewController(
            context: context,
            episodeTitle: "Demo",
            enclosureURL: "demo://enclosure-draft",
            conversation: conversation,
            draftQuestion: "About this line: \"hello\" ",
            currentLineProvider: { "the starter is the boss" }
        )
        controller.modalPresentationStyle = .fullScreen
        presenter.present(controller, animated: false)
        controller.loadViewIfNeeded()

        #expect(controller.inputBar.text == "About this line: \"hello\" ")
        #expect(conversation.messages.isEmpty, "a draft is not auto-sent")

        controller.sendExampleQuestion(ChatExamplePrompts.explainNow)
        for _ in 0..<1_000 where transport.inputs.isEmpty { await Task.yield() }
        #expect(transport.inputs == ["Explain this part: \"the starter is the boss\""])

        controller.dismiss(animated: false)
        try await Task.sleep(for: .milliseconds(300))
    }

    @Test("Composer: glass pill is 48 pt tall; send button is hidden when empty and shown with text")
    func composerSendButtonVisibility() async throws {
        let bar = ChatInputBar()
        bar.frame = CGRect(x: 0, y: 0, width: 402, height: 200)
        let host = UIWindow(frame: bar.frame)
        host.addSubview(bar)
        host.isHidden = false
        defer { host.isHidden = true }
        bar.setNeedsLayout()
        bar.layoutIfNeeded()

        let send = try #require(Self.button(labeled: "Send message", in: bar))
        #expect(send.alpha == 0 && !send.isEnabled, "no text: no send button")
        // The bar sizes to its content: 8 pt top margin + the pill.
        func pillHeight() -> CGFloat {
            bar.systemLayoutSizeFitting(
                CGSize(width: 402, height: UIView.layoutFittingCompressedSize.height),
                withHorizontalFittingPriority: .required, verticalFittingPriority: .fittingSizeLevel
            ).height - 8
        }
        #expect(abs(pillHeight() - 48) < 0.5, "one body line gives a 48 pt pill")

        bar.setText("hello")
        try await Task.sleep(for: .milliseconds(400))
        #expect(send.alpha == 1 && send.isEnabled)
        bar.setSending(true)
        try await Task.sleep(for: .milliseconds(400))
        #expect(send.alpha == 0 && !send.isEnabled, "hidden while a request is in flight")
        bar.setSending(false)
        bar.setText("   ")
        try await Task.sleep(for: .milliseconds(400))
        #expect(send.alpha == 0, "whitespace only is not sendable")

        bar.setText(String(repeating: "long line of text ", count: 40))
        bar.layoutIfNeeded()
        #expect(pillHeight() > 48 && pillHeight() < 120, "grows, capped at 3 lines")
    }

    @Test("Page sheet: the composer rides above the docked keyboard and rests on the sheet when it goes down")
    func pageSheetComposerClearsKeyboard() async throws {
        guard let context = await Self.liveUIContext(),
              let presenter = Self.rootPresenter()
        else {
            print("App environment not ready; skipping chat keyboard smoke")
            return
        }

        let controller = ChatViewController(
            context: context,
            episodeTitle: "Demo ep",
            enclosureURL: "demo://enclosure-keyboard",
            conversation: ChatConversation(transport: InstantReplyTransport())
        )
        // The production presentation (SubtitlesPageViewController.openChat),
        // not full screen: the keyboard layout guide behaves differently in
        // a page sheet.
        AppSheets.presentExpand(controller, from: presenter)
        try await Task.sleep(for: .milliseconds(800))

        var keyboardFrame = CGRect.null
        let observer = NotificationCenter.default.addObserver(
            forName: UIResponder.keyboardWillChangeFrameNotification, object: nil, queue: .main
        ) { note in
            if let frame = note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect {
                MainActor.assumeIsolated { keyboardFrame = frame }
            }
        }
        defer { NotificationCenter.default.removeObserver(observer) }

        controller.inputBar.focus()
        try await Task.sleep(for: .milliseconds(1_200))
        let screen = try #require(controller.view.window?.screen.bounds)
        let composerUp = controller.inputBar.convert(controller.inputBar.bounds, to: nil)
        print("[chat-keyboard] keyboard=\(keyboardFrame) composer=\(composerUp) screen=\(screen)")
        // A hardware keyboard on the host leaves no software keyboard to
        // clear; the geometry check applies when one actually came up.
        if !keyboardFrame.isNull, keyboardFrame.minY < screen.maxY - 100 {
            #expect(composerUp.maxY <= keyboardFrame.minY, "the docked keyboard covers the composer")
        }

        controller.view.endEditing(true)
        try await Task.sleep(for: .milliseconds(1_000))
        let composerDown = controller.inputBar.convert(controller.inputBar.bounds, to: controller.view)
        print("[chat-keyboard] down composer=\(composerDown) view=\(controller.view.bounds)")
        let restingInset = max(28, controller.view.safeAreaInsets.bottom)
        #expect(abs(controller.view.bounds.maxY - restingInset - composerDown.maxY) < 1,
                "with the keyboard down the composer rests on the sheet")

        controller.dismiss(animated: false)
        try await Task.sleep(for: .milliseconds(300))
    }

    @Test("Header New chat button follows the thread; subtitle carries the question count; send lowers the keyboard")
    func headerNewChatAndKeyboard() async throws {
        guard let context = await Self.liveUIContext(),
              let presenter = Self.rootPresenter()
        else {
            print("App environment not ready; skipping chat header smoke")
            return
        }

        let conversation = ChatConversation(transport: InstantReplyTransport())
        let controller = ChatViewController(
            context: context,
            episodeTitle: "Demo ep",
            enclosureURL: "demo://enclosure-header",
            conversation: conversation
        )
        controller.modalPresentationStyle = .fullScreen
        presenter.present(controller, animated: false)
        controller.loadViewIfNeeded()
        try await Task.sleep(for: .milliseconds(500))

        let newChat = try #require(Self.button(labeled: "New chat", in: controller.view))
        #expect(newChat.isHidden, "no New chat on an empty thread")
        #expect(Self.label(withText: "Demo ep", in: controller.view) != nil)

        controller.inputBar.focus()
        let textView = try #require(Self.firstDescendant(of: controller.inputBar, ofType: UITextView.self))
        controller.inputBar.setText("What is this?")
        // Keyboard availability varies on CI hosts; the assertion only
        // applies when the field actually took focus.
        let focused = textView.isFirstResponder
        let send = try #require(Self.button(labeled: "Send message", in: controller.inputBar))
        send.sendActions(for: .touchUpInside)
        #expect(!textView.isFirstResponder, "send lowers the keyboard (was focused: \(focused))")

        for _ in 0..<1_000 where conversation.messages.count < 2 { await Task.yield() }
        try await Task.sleep(for: .milliseconds(500))
        #expect(!newChat.isHidden, "New chat shows once the thread has messages")
        #expect(Self.label(withText: "1 question · Demo ep", in: controller.view) != nil)

        controller.inputBar.focus()
        newChat.sendActions(for: .touchUpInside)
        #expect(!textView.isFirstResponder, "New chat lowers the keyboard")
        #expect(conversation.messages.isEmpty)
        try await Task.sleep(for: .milliseconds(500))
        #expect(newChat.isHidden)

        controller.dismiss(animated: false)
        try await Task.sleep(for: .milliseconds(300))
    }

    // MARK: - Helpers

    private static func firstDescendant<T: UIView>(of view: UIView, ofType type: T.Type) -> T? {
        if let match = view as? T { return match }
        for subview in view.subviews {
            if let found = firstDescendant(of: subview, ofType: type) { return found }
        }
        return nil
    }

    private static func button(labeled label: String, in view: UIView) -> UIButton? {
        if let button = view as? UIButton, button.accessibilityLabel == label { return button }
        for subview in view.subviews {
            if let found = button(labeled: label, in: subview) { return found }
        }
        return nil
    }

    private static func label(withText text: String, in view: UIView) -> UILabel? {
        if let label = view as? UILabel, label.text == text { return label }
        for subview in view.subviews {
            if let found = Self.label(withText: text, in: subview) { return found }
        }
        return nil
    }

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
