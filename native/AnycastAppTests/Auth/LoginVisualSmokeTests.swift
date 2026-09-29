import UIKit
import Testing
@testable import Anycast

/// Hosted visual check for the login sheet (05 §6.1 S17): presents the real
/// LoginViewController over the live shell and captures the window into the
/// app's tmp directory for offline inspection. The captured auth state is
/// whatever the host is in (a signed-in simulator yields the logged-in
/// list; a fresh one the logged-out column). Skips silently when the
/// startup DAG has no context yet.
@MainActor
struct LoginVisualSmokeTests {

    @Test("Login sheet capture in the host's auth state")
    func loginSheetScreenshot() async throws {
        guard let context = await Self.liveUIContext() else { return }
        guard let presenter = Self.rootPresenter() else { return }

        AppSheets.presentExpand(LoginViewController(context: context), from: presenter)
        try await Task.sleep(for: .seconds(2))
        await Self.captureWindow(name: "t8-login-sheet")

        // Sheet must not hard-fail without Firebase/RevenueCat configured —
        // the view hierarchy still holds the three auth buttons.
        let login = Self.findLogin(under: presenter)
        #expect(login != nil)
        // The auth affordances exist only in the logged-out column (the
        // captured auth state mirrors the host); when one renders, all
        // three must. Titles live in the buttons' embedded labels, not
        // UIButton's own title machinery.
        let authTitles = [
            LoginPageModel.appleButtonTitle,
            LoginPageModel.googleButtonTitle,
            LoginPageModel.emailButtonTitle,
        ]
        let foundTitles = authTitles.filter { Self.findLabel(text: $0, in: login?.view) }
        if !foundTitles.isEmpty {
            let missing = authTitles.filter { !foundTitles.contains($0) }
            #expect(
                missing.isEmpty,
                "auth buttons partially rendered, missing: \(missing.joined(separator: ", "))")
        }

        await MainActor.run { login?.dismiss(animated: false) }
        try await Task.sleep(for: .milliseconds(500))
    }

    @MainActor
    private static func findLabel(text: String, in view: UIView?) -> Bool {
        guard let view else { return false }
        if let label = view as? UILabel, label.text == text { return true }
        return view.subviews.contains { findLabel(text: text, in: $0) }
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
    private static func rootPresenter() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let window = scenes.flatMap(\.windows).first { $0.isKeyWindow }
        return window?.rootViewController?.topMostPresented()
    }

    @MainActor
    private static func findLogin(under presenter: UIViewController) -> LoginViewController? {
        var top = presenter
        while let next = top.presentedViewController { top = next }
        return findLogin(in: top) ?? (top as? LoginViewController)
    }

    @MainActor
    private static func findLogin(in root: UIViewController) -> LoginViewController? {
        if let login = root as? LoginViewController { return login }
        for child in root.children {
            if let found = findLogin(in: child) { return found }
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
        print("[t8-visual] wrote \(url.path)")
    }
}
