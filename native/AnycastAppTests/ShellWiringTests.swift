import UIKit
import Testing
@testable import Anycast

/// Shell wiring regressions from the 2026-09-28 review round: both bugs
/// rendered correctly while being dead — the mini player's play/pause
/// control carried no action, and the inner tab strip's indicator never
/// received a frame (its width came from legacy titleLabel, which stays
/// empty for configuration-based buttons).
@MainActor
struct ShellWiringTests {

    // MARK: - Inner tab strip indicator (PodcastsTabStrip)

    /// Builds the strip and lays it out attached to the live key window —
    /// an off-window `layoutIfNeeded` does not resolve the stack subtree,
    /// so the buttons (and the indicator sized against them) stay at zero.
    private func makeLaidOutStrip() -> (strip: PodcastsTabStrip, host: UIView)? {
        let strip = PodcastsTabStrip(items: [
            .init(title: "Inbox", icon: AppIcons.inbox),
            .init(title: "Subscriptions", icon: AppIcons.subscriptions),
        ])
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        guard let window = scenes.flatMap(\.windows).first(where: \.isKeyWindow) else { return nil }
        let host = UIView(frame: CGRect(x: 0, y: -56, width: 320, height: 56))
        strip.translatesAutoresizingMaskIntoConstraints = false
        host.addSubview(strip)
        NSLayoutConstraint.activate([
            strip.leadingAnchor.constraint(equalTo: host.leadingAnchor),
            strip.trailingAnchor.constraint(equalTo: host.trailingAnchor),
            strip.topAnchor.constraint(equalTo: host.topAnchor),
            strip.bottomAnchor.constraint(equalTo: host.bottomAnchor),
        ])
        window.addSubview(host)
        host.setNeedsLayout()
        host.layoutIfNeeded()
        return (strip, host)
    }

    /// The strip's only direct subview carrying the selection tint is the
    /// indicator (buttons live inside the stack and tint via foreground).
    private func indicator(in strip: PodcastsTabStrip) -> UIView? {
        strip.subviews.first { $0.backgroundColor == Theme.tabSelectedGreen }
    }

    private func buttons(in strip: PodcastsTabStrip) -> [UIButton] {
        let stack = strip.subviews.compactMap { $0 as? UIStackView }.first
        return (stack?.arrangedSubviews as? [UIButton]) ?? []
    }

    @Test("Inner tab strip lays out a visible indicator under the selected tab")
    func stripIndicatorVisible() {
        guard let (strip, host) = makeLaidOutStrip() else { return }
        defer { host.removeFromSuperview() }
        guard let indicator = indicator(in: strip) else {
            Issue.record("no indicator view with the selection tint found")
            return
        }
        let buttons = buttons(in: strip)
        guard buttons.count == 2 else {
            Issue.record("expected two strip buttons, found \(buttons.count)")
            return
        }
        #expect(indicator.frame.height == 3)
        #expect(indicator.frame.width > 0)
        #expect(abs(indicator.frame.midX - buttons[0].center.x) < 1)

        strip.select(1, animated: false)
        #expect(indicator.frame.width > 0)
        #expect(abs(indicator.frame.midX - buttons[1].center.x) < 1)
    }

    // MARK: - Mini player play/pause wiring (PlayerBarView)

    @Test("Mini player play/pause control carries a touch-up action")
    func miniPlayerPlayPauseWired() async {
        guard let context = await Self.liveUIContext() else { return }
        let bar = context.makePlayerBar()
        bar.frame = CGRect(x: 0, y: 0, width: 390, height: 58)
        bar.layoutIfNeeded()
        guard let control = Self.firstDescendant(of: bar, of: PlayPauseIconControl.self) else {
            Issue.record("no PlayPauseIconControl inside the mini player bar")
            return
        }
        let wired = control.allTargets.contains { target in
            !(control.actions(forTarget: target, forControlEvent: .touchUpInside) ?? []).isEmpty
        }
        #expect(wired)
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
    private static func firstDescendant<T: UIView>(of view: UIView, of type: T.Type) -> T? {
        if let match = view as? T { return match }
        for subview in view.subviews {
            if let found = firstDescendant(of: subview, of: type) { return found }
        }
        return nil
    }
}
