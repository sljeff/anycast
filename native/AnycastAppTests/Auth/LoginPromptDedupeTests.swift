import UIKit
import Testing
@testable import Anycast

/// Regression: the Settings "Account" row presents the login sheet directly
/// — never through LoginPromptCoordinator — and a background 401 routes to
/// `context.presentLogin()`. The coordinator must recognize a login sheet
/// already in the presentation chain and swallow the request instead of
/// stacking a second sheet on the first (the reported double login window).
@MainActor
@Suite(.serialized)
struct LoginPromptDedupeTests {

    /// The Settings path + the sheet's own 401 must yield exactly one sheet.
    @Test("401 while a directly-presented login sheet is up must not stack a second")
    func directPresentationSwallowsSubsequent401() async throws {
        guard let context = await Self.liveUIContext() else { return }
        guard let presenter = await Self.rootPresenter() else { return }
        try await Self.waitForNoLogin(under: presenter)

        // Settings' presentAccount(): direct sheet, coordinator uninvolved.
        LoginSheetViewController.present(from: presenter, context: context, source: .settings)
        // Let the sheet transition finish.
        try await Task.sleep(for: .milliseconds(800))

        // The call a background 401 makes.
        context.presentLogin()
        try await Task.sleep(for: .milliseconds(600))

        #expect(
            Self.loginCount(under: presenter) == 1,
            "a second login sheet was stacked over the directly-presented one"
        )

        await MainActor.run { presenter.dismiss(animated: false) }
        try await Task.sleep(for: .milliseconds(400))
        try await Self.waitForNoLogin(under: presenter)
    }

    /// The chain walk must not over-dedupe: with nothing presented, the
    /// coordinator still presents exactly one sheet.
    @Test("coordinator still presents when no login sheet is on screen")
    func presentsWhenAbsent() async throws {
        guard let context = await Self.liveUIContext() else { return }
        guard let presenter = await Self.rootPresenter() else { return }
        try await Self.waitForNoLogin(under: presenter)

        context.presentLogin()
        try await Task.sleep(for: .milliseconds(800))

        #expect(Self.loginCount(under: presenter) == 1)

        await MainActor.run { presenter.dismiss(animated: false) }
        try await Task.sleep(for: .milliseconds(400))
        try await Self.waitForNoLogin(under: presenter)
    }

    /// The login-cancel rollback: signed-out Generate leaves the
    /// optimistic "processing" stuck (synthetic 401, no network) and the
    /// coordinator's login sheet on screen. Dismissal via the interactive
    /// path — driven here as the exact UIKit callback, which a
    /// programmatic dismiss never delivers — must roll the entry back to
    /// the Generate state.
    @Test("interactive dismissal of the login sheet rolls back login-gated processing")
    func interactiveDismissalRollsBackProcessing() async throws {
        guard let context = await Self.liveUIContext() else { return }
        guard let presenter = await Self.rootPresenter() else { return }
        // The whole scenario is signed-out only; skip on a signed-in host.
        guard context.auth.currentUID == nil else { return }
        try await Self.waitForNoLogin(under: presenter)

        // Signed-out Generate: the request 401s before any network, the
        // login sheet presents through the coordinator, and the entry
        // sticks as "processing" (the bug's stuck state).
        let url = "https://x.example/login-cancel-\(UUID().uuidString).mp3"
        await context.subtitles.add(url: url)
        #expect(context.subtitles.statuses[url] == "processing",
                "the optimistic entry stays while the login sheet is pending")

        // Wait for the sheet AND its dismissal delegate (the coordinator
        // attaches the adapter in the present completion, after the
        // sheet transition finishes).
        guard let sheet = await Self.waitForLoginSheetDelegate(under: presenter) else { return }

        // The exact callback UIKit delivers for the interactive
        // swipe-down dismissal.
        sheet.delegate?.presentationControllerDidDismiss?(sheet)

        #expect(context.subtitles.statuses[url] == nil,
                "dismissing the login sheet without signing in cancels the pending generate")

        // Cleanup: the callback alone does not remove the sheet (UIKit
        // has already dismissed it interactively in the real flow).
        await MainActor.run { presenter.dismiss(animated: false) }
        try await Task.sleep(for: .milliseconds(400))
        try await Self.waitForNoLogin(under: presenter)
    }

    /// The signed-in dismissal must NOT roll back: the coordinator's
    /// signed-out check is what makes a dismissal callback a no-op once an
    /// account is signed in — verified here by overriding the
    /// coordinator's `isSignedOut` seam to report signed-in.
    @Test("interactive dismissal while signed in does not roll back processing")
    func interactiveDismissalWhileSignedInKeepsProcessing() async throws {
        guard let context = await Self.liveUIContext() else { return }
        guard let presenter = await Self.rootPresenter() else { return }
        // The host must genuinely be signed out so the sheet presents via
        // the signed-out 401 path; the seam override then simulates the
        // signed-in dismissal on top.
        guard context.auth.currentUID == nil else { return }
        try await Self.waitForNoLogin(under: presenter)

        let url = "https://x.example/signed-in-dismiss-\(UUID().uuidString).mp3"
        await context.subtitles.add(url: url)
        #expect(context.subtitles.statuses[url] == "processing")

        guard let sheet = await Self.waitForLoginSheetDelegate(under: presenter) else { return }

        // Simulate the signed-in state for the dismissal: the sheet stays
        // up after signing in and is later swiped down — the callback
        // fires while currentUID != nil.
        let original = context.loginPrompt.isSignedOut
        context.loginPrompt.isSignedOut = { false }
        defer { context.loginPrompt.isSignedOut = original }

        sheet.delegate?.presentationControllerDidDismiss?(sheet)

        #expect(context.subtitles.statuses[url] == "processing",
                "a post-sign-in swipe-down must not cancel genuine in-flight work")

        // Cleanup: drop the seeded entry directly (its rollback path is
        // deliberately closed here), then remove the sheet. A leftover
        // processing entry would keep the host's 15 s poller presenting
        // login sheets during later suites.
        context.subtitles.cancelLoginGatedProcessing()
        await MainActor.run { presenter.dismiss(animated: false) }
        try await Task.sleep(for: .milliseconds(400))
        try await Self.waitForNoLogin(under: presenter)
    }

    // MARK: - Helpers

    /// Login sheets in the presented chain above `presenter` — a stacked
    /// second sheet would surface as a chain sibling, count 2.
    @MainActor
    private static func loginCount(under presenter: UIViewController) -> Int {
        var count = 0
        var current: UIViewController? = presenter
        while let controller = current {
            if controller is LoginSheetViewController { count += 1 }
            current = controller.presentedViewController
        }
        return count
    }

    /// Clears login sheets another suite may have left mid-flight (the app
    /// tests share one host and Swift Testing parallelizes across suites).
    @MainActor
    private static func waitForNoLogin(under presenter: UIViewController) async throws {
        for _ in 0..<10 {
            if loginCount(under: presenter) == 0 { return }
            try await Task.sleep(for: .milliseconds(500))
        }
    }

    /// Waits for a coordinator-presented login sheet whose dismissal
    /// delegate is attached (a directly-presented login sheet never gets
    /// one, so this pins the adapter to the coordinator's own path).
    /// Nil (with a recorded issue) if it never appears.
    @MainActor
    private static func waitForLoginSheetDelegate(under presenter: UIViewController) async -> UISheetPresentationController? {
        for _ in 0..<20 {
            var current: UIViewController? = presenter
            while let controller = current {
                if let login = controller as? LoginSheetViewController,
                   !login.isBeingDismissed,
                   let sheet = login.sheetPresentationController,
                   sheet.delegate != nil {
                    return sheet
                }
                current = controller.presentedViewController
            }
            try? await Task.sleep(for: .milliseconds(500))
        }
        Issue.record("coordinator login sheet (or its dismissal delegate) never appeared")
        return nil
    }

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
}
