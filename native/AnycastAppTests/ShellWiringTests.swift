import UIKit
import Testing
@testable import Anycast

/// Shell wiring regressions from the 2026-09-28 review round: the bug
/// rendered correctly while being dead — the mini player's play/pause
/// control carried no action. (The inner-tab-strip indicator half retired
/// with the V2 IA flip — PodcastsTabContainer/PodcastsTabStrip deleted,
/// 09 §10 V2.)
@MainActor
struct ShellWiringTests {

    // MARK: - Mini player play/pause wiring (PlayerBarView)
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
