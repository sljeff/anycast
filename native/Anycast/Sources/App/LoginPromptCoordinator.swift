import UIKit

/// Presents the login sheet wherever a 401/403-code=2 surfaces
/// (docs/migration/03 §10.1 — the Flutter line opened LoginPage from
/// `ErrorHandler` at any moment; the native port routes every trigger
/// through `AuthController.onAuthRequired` → here, plus direct calls from
/// screens that receive `.loginRequired` signals).
@MainActor
final class LoginPromptCoordinator {

    /// The shell root; set by RootViewController at install time. Sheets
    /// stack from the top-most presenter above this anchor (03 §1.2).
    weak var presentingAnchor: UIViewController?

    /// Cycle-safe access to the context (screens are built from it).
    weak var context: UIContext?

    /// Dedupe: a presented login sheet that is still on screen swallows
    /// further 401s (the Dart code could stack multiple sheets).
    private weak var currentLogin: UIViewController?

    /// Rate limit on PRESENT ATTEMPTS: the `currentLogin` dedupe only covers
    /// a sheet that actually reached the window. A refused `present` (another
    /// transition in flight) leaves `currentLogin` windowless, and every
    /// further 401 — N `processing` URLs in one subtitle-poll round, or the
    /// refused sheet's own /api/user — spawns another sheet attempt in a
    /// tight main-actor loop (observed: hundreds/sec, main thread pegged).
    /// One attempt per second still self-heals once the pipeline frees.
    private var lastAttempt = Date.distantPast

    /// Presents `LoginViewController` as a full-height expand sheet
    /// (03 §1.3 #7: expand true / threshold 0.9 → A2/A3 system sheet).
    func presentLogin() {
        guard let anchor = presentingAnchor, let context else { return }
        if let currentLogin, currentLogin.view.window != nil { return }
        if presentedChainContainsLogin(from: anchor) { return }
        guard Date().timeIntervalSince(lastAttempt) >= 1 else { return }
        lastAttempt = Date()
        let top = anchor.topMostPresented()
        let login = LoginViewController(context: context)
        currentLogin = login
        AppSheets.presentExpand(login, from: top)
    }

    /// `currentLogin` only dedupes sheets this coordinator presented. The
    /// Settings "Account" row presents LoginViewController directly, and
    /// that sheet's own signed-out /api/user returns loginRequired —
    /// without this chain walk the 401 stacked a second login sheet on
    /// the first (the sheet's `.loginRequired` handler routes back here).
    private func presentedChainContainsLogin(from anchor: UIViewController) -> Bool {
        var current: UIViewController? = anchor.topMostPresented()
        while let controller = current {
            if controller is LoginViewController, !controller.isBeingDismissed {
                return true
            }
            current = controller.presentingViewController
        }
        return false
    }
}
