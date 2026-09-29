import UIKit
import Testing
import AnycastKit
@testable import Anycast

/// Hosted visual check for the settings sheet (05 §6.1 S16): presents the
/// real SettingsViewController over the live shell and captures the window
/// for offline inspection (translation on and off). Skips silently when the
/// startup DAG has no context yet (unseeded simulator).
@MainActor
struct SettingsVisualSmokeTests {

    @Test("Settings sheet captures: translation off and on")
    func settingsScreenshots() async throws {
        guard let context = await Self.liveUIContext() else { return }
        guard let presenter = Self.rootPresenter() else { return }

        // This writes the LIVE app container's database — restore the
        // original language afterwards, or a leftover "zh" flips transcript
        // translation on for every later run on this simulator. The restore
        // must complete before the test ends: a fire-and-forget Task races
        // the next test's reads (and dies with the process on the last one).
        // (defer cannot await, so both exits restore explicitly.)
        let originalLanguage = context.settingsBox.current.targetLanguage

        func runCaptures() async throws {
            // Translation off: '' hides the Target Language row.
            await context.settingsCoordinator.updateTargetLanguage("")
            let controller = SettingsViewController(context: context)
            AppSheets.presentExpand(controller, from: presenter)
            try await Task.sleep(for: .seconds(2))
            await Self.captureWindow(name: "t7-settings-translation-off")

            // Translation on: the row appears (writes go through the
            // coordinator, exactly like a user toggling the switch).
            await context.settingsCoordinator.updateTargetLanguage("zh")
            try await Task.sleep(for: .milliseconds(800))
            await Self.captureWindow(name: "t7-settings-translation-on")

            await MainActor.run { controller.dismiss(animated: false) }
            try await Task.sleep(for: .milliseconds(500))
        }

        do {
            try await runCaptures()
        } catch {
            await context.settingsCoordinator.updateTargetLanguage(originalLanguage)
            throw error
        }
        await context.settingsCoordinator.updateTargetLanguage(originalLanguage)
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
        print("[t7-visual] wrote \(url.path)")
    }
}
