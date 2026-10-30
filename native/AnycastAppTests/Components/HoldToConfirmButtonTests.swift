import UIKit
import Testing
@testable import Anycast

/// HoldToConfirmButton: completes after the hold, cancels on early release,
/// and hands off to `onConfirmRequested` under assistive technology.
@MainActor
struct HoldToConfirmButtonTests {

    private static let duration: TimeInterval = 0.05

    /// Hosted in a window so the property animators actually run.
    private func makeButton() -> (HoldToConfirmButton, UIWindow) {
        let button = HoldToConfirmButton(
            title: "Hold to Clear", holdingTitle: "Keep Holding", image: nil, holdDuration: Self.duration
        )
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 200))
        window.addSubview(button)
        NSLayoutConstraint.activate([
            button.leadingAnchor.constraint(equalTo: window.leadingAnchor, constant: 16),
            button.trailingAnchor.constraint(equalTo: window.trailingAnchor, constant: -16),
            button.topAnchor.constraint(equalTo: window.topAnchor, constant: 16),
        ])
        window.isHidden = false
        window.layoutIfNeeded()
        return (button, window)
    }

    private func wait(_ seconds: TimeInterval) async {
        try? await Task.sleep(for: .seconds(seconds))
    }

    @Test("a completed hold confirms exactly once")
    func completes() async {
        let (button, window) = makeButton()
        var confirmed = 0
        button.onConfirm = { confirmed += 1 }
        button.sendActions(for: .touchDown)
        await wait(Self.duration + 0.3)
        button.sendActions(for: .touchUpInside)
        await wait(0.1)
        #expect(confirmed == 1)
        withExtendedLifetime(window) {}
    }

    @Test("releasing early cancels the hold")
    func cancelsEarly() async {
        let (button, window) = makeButton()
        var confirmed = 0
        button.onConfirm = { confirmed += 1 }
        button.sendActions(for: .touchDown)
        #expect(button.configuration?.title == "Keep Holding")
        button.sendActions(for: .touchUpInside)
        #expect(button.configuration?.title == "Hold to Clear")
        await wait(Self.duration + 0.3)
        #expect(confirmed == 0)
        withExtendedLifetime(window) {}
    }

    @Test("assistive technology requests confirmation instead of holding")
    func assistive() async {
        HoldToConfirmButton.assistiveTechnologyOverride = true
        defer { HoldToConfirmButton.assistiveTechnologyOverride = nil }
        let (button, window) = makeButton()
        var confirmed = 0
        var requested = 0
        button.onConfirm = { confirmed += 1 }
        button.onConfirmRequested = { requested += 1 }
        button.sendActions(for: .touchDown)
        button.sendActions(for: .touchUpInside)
        await wait(Self.duration + 0.3)
        #expect(requested == 1)
        #expect(confirmed == 0)
        #expect(button.accessibilityActivate())
        #expect(requested == 2)
        withExtendedLifetime(window) {}
    }

    @Test("reset() returns to the idle look after completion")
    func resetRestoresIdle() async {
        let (button, window) = makeButton()
        button.sendActions(for: .touchDown)
        #expect(button.configuration?.title == "Keep Holding")
        await wait(Self.duration + 0.3)
        button.reset()
        #expect(button.configuration?.title == "Hold to Clear")
        withExtendedLifetime(window) {}
    }
}
