import UIKit
import Testing
@testable import Anycast

/// Regression for the long-token overflow: the bubble's 0.75×viewport width
/// cap, the edge-pinned margins, and a `.required` horizontal compression
/// resistance on the text label are jointly unsatisfiable when an AI reply
/// contains a long unbreakable URL — Auto Layout broke the cap and the
/// bubble extended past the list. The label now yields (750) and word
/// wrapping breaks the overlong token per character, so the cap must hold.
@MainActor
struct ChatBubbleWidthTests {

    @Test("listener messages sit in a player-palette bubble; replies read on the sheet")
    func bubblesUseV2Colors() {
        let human = ChatBubbleView(frame: .zero)
        human.configure(with: ChatMessage(
            id: UUID(), author: .human, createdAt: Date(), text: "Hello"
        ))
        let assistant = ChatBubbleView(frame: .zero)
        assistant.configure(with: ChatMessage(
            id: UUID(), author: .ai, createdAt: Date(), text: "Hi"
        ))

        for style in [UIUserInterfaceStyle.light, .dark] {
            let traits = UITraitCollection(userInterfaceStyle: style)
            #expect(human.bubble.backgroundColor?.resolvedColor(with: traits)
                == ChatBubbleView.humanFill.resolvedColor(with: traits))
            #expect(assistant.bubble.backgroundColor == .clear)
        }
    }

    @Test("bubble width cap holds for a long unbreakable URL")
    func longURLKeepsBubbleInsideCap() {
        let host = UIView(frame: CGRect(x: 0, y: 0, width: 402, height: 600))
        let bubble = ChatBubbleView(frame: .zero)
        bubble.configure(
            with: ChatMessage(
                id: UUID(),
                author: .ai,
                createdAt: Date(),
                text: "https://example.com/very/long/path/segments/that/keep/going/and/going/and/going?q=\(String(repeating: "x", count: 180))"
            )
        )
        bubble.translatesAutoresizingMaskIntoConstraints = false
        host.addSubview(bubble)
        // The view's own cap constant at init is the default viewportWidth
        // 320 (apply() later multiplies the 0.75 fraction); either way it
        // sits well below the text's single-line width.
        NSLayoutConstraint.activate([
            bubble.leadingAnchor.constraint(equalTo: host.leadingAnchor),
            bubble.topAnchor.constraint(equalTo: host.topAnchor, constant: 8),
        ])
        host.layoutIfNeeded()

        #expect(
            bubble.bounds.width <= 320.5,
            "bubble laid out at \(bubble.bounds.width) pt — the width cap broke"
        )
        #expect(bubble.frame.maxX <= host.bounds.maxX, "bubble extends past the list width")
    }

    @Test("a cell sized for the placeholder re-wraps at full width when reconfigured with a long reply")
    func reconfiguredLongTextIsNotNarrowStrip() {
        let long = String(repeating: "A long assistant reply that must wrap across several lines. ", count: 6)
        for author in [ChatMessage.Author.ai, .human] {
            // In a window so constraint invalidation propagates as on device.
            let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 900))
            let host = UIView(frame: window.bounds)
            window.addSubview(host)
            window.isHidden = false
            let view = ChatBubbleView(frame: .zero)
            view.translatesAutoresizingMaskIntoConstraints = false
            host.addSubview(view)
            NSLayoutConstraint.activate([
                view.leadingAnchor.constraint(equalTo: host.leadingAnchor),
                view.topAnchor.constraint(equalTo: host.topAnchor),
            ])
            view.configure(with: ChatMessage(id: UUID(), author: .ai, createdAt: Date(), text: "..."))
            host.layoutIfNeeded()

            view.configure(with: ChatMessage(id: UUID(), author: author, createdAt: Date(), text: long))
            host.layoutIfNeeded()

            // Self-sizing as the collection cell does.
            let fitted = view.systemLayoutSizeFitting(
                CGSize(width: 390, height: UIView.layoutFittingCompressedSize.height),
                withHorizontalFittingPriority: .fittingSizeLevel,
                verticalFittingPriority: .fittingSizeLevel
            )
            #expect(fitted.width > 200, "\(author): fitted \(fitted) — one-character strip")
            #expect(fitted.height < 400, "\(author): fitted \(fitted)")
        }
    }

    @Test("a failed message is dimmed and shows the resend button, which calls back")
    func failedMessageShowsResend() {
        let bubble = ChatBubbleView(frame: .zero)
        var resent = false
        bubble.onResend = { resent = true }
        bubble.configure(with: ChatMessage(
            id: UUID(), author: .human, createdAt: Date(), text: "And when it's cold?",
            deliveryState: .failed
        ))
        let host = UIView(frame: CGRect(x: 0, y: 0, width: 402, height: 300))
        bubble.translatesAutoresizingMaskIntoConstraints = false
        host.addSubview(bubble)
        NSLayoutConstraint.activate([
            bubble.trailingAnchor.constraint(equalTo: host.trailingAnchor),
            bubble.topAnchor.constraint(equalTo: host.topAnchor),
        ])
        host.layoutIfNeeded()

        let button = Self.buttons(in: bubble).first
        #expect(button?.isHidden == false)
        #expect((button?.bounds.height ?? 0) >= 44)
        #expect(bubble.bubble.alpha < 1)
        button?.sendActions(for: .touchUpInside)
        #expect(resent)

        bubble.configure(with: ChatMessage(
            id: UUID(), author: .human, createdAt: Date(), text: "ok"
        ))
        #expect(Self.buttons(in: bubble).first?.isHidden == true)
        #expect(bubble.bubble.alpha == 1)
    }

    private static func buttons(in view: UIView) -> [UIButton] {
        view.subviews.flatMap { sub in
            (sub as? UIButton).map { [$0] } ?? buttons(in: sub)
        }
    }
}
