import UIKit
import Testing
@testable import Anycast

/// Regression for the long-token overflow: the bubble's 0.75×viewport width
/// cap, the edge-pinned margins, and a `.required` horizontal compression
/// resistance on the text label are jointly unsatisfiable when an AI reply
/// contains a long unbreakable URL — Auto Layout broke the cap and the
/// bubble extended past the list. The label now yields (750) and wraps
/// per character, so the cap must hold.
@MainActor
struct ChatBubbleWidthTests {

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
}
