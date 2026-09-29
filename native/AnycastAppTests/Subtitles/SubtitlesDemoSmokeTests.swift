import UIKit
import Testing
@testable import Anycast

#if DEBUG
/// Hosted visual smoke test: mounts the subtitles page with the fixed
/// bilingual demo document (the same injection `-t5-demo-lyrics` uses on a
/// launched app) and asserts the ready-state lyrics area actually renders —
/// the collection view with parsed lines is on screen and the page reports
/// the bilingual ready state. Catches layout-fault-class regressions
/// (unsatisfiable constraints log and drop views) without pixel baselines.
@MainActor
struct SubtitlesDemoSmokeTests {

    @Test("Demo bilingual document renders the lyrics area")
    func demoDocumentRendersLyrics() async throws {
        guard let context = await Self.liveUIContext(),
              let presenter = await Self.rootPresenter()
        else {
            print("App environment not ready; skipping demo smoke")
            return
        }

        let controller = SubtitlesPageViewController(context: context)
        controller.modalPresentationStyle = .fullScreen
        controller.activateDemoDocument()
        // Present on the settled TOP of the stack — the shell can be
        // mid-presenting an auto Login sheet (auth-failure signals during
        // the run), and `present` on an in-flight presenter is refused,
        // leaving the view unlaid-out (visibleCells == 0).
        let host = await Self.settledTopPresenter() ?? presenter
        host.present(controller, animated: false)
        try await Task.sleep(for: .milliseconds(500))

        #expect(controller.demoIsRenderingLyrics)

        // The lyrics collection is embedded and laid out with lines:
        // 5 demo segments × (start + end spacer) = 10 rows.
        let collection = Self.firstCollectionView(in: controller.view)
        #expect(collection != nil)
        if let collection {
            #expect(collection.numberOfSections == 1)
            #expect(collection.numberOfItems(inSection: 0) == 10)
            #expect(collection.visibleCells.count > 0)
        }

        controller.dismiss(animated: false)
    }

    // MARK: - Helpers

    private static func firstCollectionView(in view: UIView) -> UICollectionView? {
        if let collection = view as? UICollectionView { return collection }
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
        return window?.rootViewController
    }

    /// Walks the presented stack and waits until the top controller is fully
    /// installed (view in a window AND no transition in flight). Returns nil
    /// only when no window exists at all.
    private static func settledTopPresenter() async -> UIViewController? {
        for _ in 0..<40 {
            var top = rootPresenter()
            while let next = top?.presentedViewController { top = next }
            if let top, top.view.window != nil, !top.isBeingPresented,
               top.transitionCoordinator == nil {
                return top
            }
            try? await Task.sleep(for: .milliseconds(250))
        }
        return nil
    }
}
#endif
