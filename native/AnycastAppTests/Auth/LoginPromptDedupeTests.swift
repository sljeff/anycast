import UIKit
import Testing
@testable import Anycast

/// Regression: the Settings "Account" row presents LoginViewController
/// directly — never through LoginPromptCoordinator — and that sheet's own
/// signed-out /api/user returns loginRequired, which routes back to
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
        AppSheets.presentExpand(LoginViewController(context: context), from: presenter)
        // Let the sheet's own reloadSubscriptionData 401 land (synthetic
        // when signed out — no network involved) plus the sheet transition.
        try await Task.sleep(for: .milliseconds(800))

        // The exact call the sheet's .loginRequired handlers make
        // (LoginViewController reloadSubscriptionData / presentErrorSignal).
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

    // MARK: - Helpers

    /// Login sheets in the presented chain above `presenter` — a stacked
    /// second sheet would surface as a chain sibling, count 2.
    @MainActor
    private static func loginCount(under presenter: UIViewController) -> Int {
        var count = 0
        var current: UIViewController? = presenter
        while let controller = current {
            if controller is LoginViewController { count += 1 }
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
