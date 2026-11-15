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

    /// Interactive-dismiss bridge for the presented login sheet. The sheet's
    /// `UIPresentationController.delegate` is weak, so the coordinator
    /// retains the adapter for the sheet's lifetime and replaces it on each
    /// present.
    private var dismissalAdapter: LoginDismissalAdapter?

    /// Signed-out check for the dismissal handler. Injectable so tests can
    /// simulate a signed-in dismissal; lazily defaults to the live auth
    /// state (read at call time — `context` is attached after init).
    /// Load-bearing, not documentation — see `rollbackLoginGatedProcessing`.
    lazy var isSignedOut: @MainActor () -> Bool = { [weak self] in
        self?.context?.auth.currentUID == nil
    }

    /// Presents the login sheet for an expired session (`.reauth`: the
    /// account's last-used provider leads).
    func presentLogin() {
        guard let anchor = presentingAnchor, let context else { return }
        if let currentLogin, currentLogin.view.window != nil { return }
        if presentedChainContainsLogin(from: anchor) { return }
        guard Date().timeIntervalSince(lastAttempt) >= 1 else { return }
        lastAttempt = Date()
        let top = anchor.topMostPresented()
        let login = LoginSheetViewController.present(
            from: top, context: context, source: .reauth,
            completion: { [weak self] sheet in self?.attachDismissalAdapter(to: sheet) }
        )
        login.onCancelled = { [weak self] in self?.rollbackLoginGatedProcessing() }
        currentLogin = login
    }

    /// Attaches the interactive-dismiss signal in the present completion,
    /// when the sheet's presentation controller exists for sure (it does
    /// not reliably survive being touched before `present`).
    private func attachDismissalAdapter(to login: UIViewController?) {
        guard let login else { return }
        let adapter = LoginDismissalAdapter()
        adapter.onUserDismissed = { [weak self] in
            self?.rollbackLoginGatedProcessing()
        }
        dismissalAdapter = adapter
        login.sheetPresentationController?.delegate = adapter
    }

    /// Dismissing the login sheet WITHOUT signing in cancels the pending
    /// generates: signed-out `processing` entries are unpollable local
    /// state, so rolling them back frees the Generate button and removes
    /// the URLs from the 15 s poll set — the poller stops re-401-ing and
    /// re-presenting this sheet every round. Both cancel paths land here:
    /// the interactive swipe-down (via the dismissal adapter) and the
    /// sheet's close button (`onCancelled`). A successful sign-in dismisses
    /// the sheet programmatically and fires neither, but the `isSignedOut`
    /// check stays as the guard that keeps a signed-in dismissal from
    /// rolling back genuinely in-flight server-side processing entries.
    private func rollbackLoginGatedProcessing() {
        guard isSignedOut(), let context else { return }
        context.subtitles.cancelLoginGatedProcessing()
    }

    /// `currentLogin` only dedupes sheets this coordinator presented. The
    /// Settings "Account" row presents the login sheet directly, and a
    /// 401 can still arrive while it is up — without this chain walk the
    /// 401 stacked a second login sheet on the first.
    private func presentedChainContainsLogin(from anchor: UIViewController) -> Bool {
        var current: UIViewController? = anchor.topMostPresented()
        while let controller = current {
            if controller is LoginSheetViewController, !controller.isBeingDismissed {
                return true
            }
            current = controller.presentingViewController
        }
        return false
    }
}

/// Bridges the login sheet's interactive swipe-down dismissal into the
/// coordinator: `presentationControllerDidDismiss` fires only for the
/// user's interactive dismiss (a programmatic `dismiss(animated:)` never
/// triggers it). The sheet has no close button, so the swipe-down is the
/// cancel path — but it is NOT proof of "still signed out": after a
/// successful sign-in the sheet stays up and its later swipe-down fires
/// this same callback, so the coordinator's signed-out check is what
/// decides what a dismissal means. The sheet's `delegate` property is
/// typed `UISheetPresentationControllerDelegate` (it inherits the
/// dismissal callbacks), so that is the conformance to declare.
@MainActor
private final class LoginDismissalAdapter: NSObject, UISheetPresentationControllerDelegate {

    var onUserDismissed: (() -> Void)?

    func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
        onUserDismissed?()
    }
}
