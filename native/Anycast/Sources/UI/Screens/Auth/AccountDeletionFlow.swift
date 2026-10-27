import UIKit
import AnycastKit

/// The permanent account-deletion flow (login.dart:735-789) shared by the
/// Login sheet and the Membership page: confirmation alert → full-screen
/// spinner → DELETE /api/user → sign out. Errors surface as alerts.
@MainActor
enum AccountDeletionFlow {

    /// Asks for confirmation over `presenter`; `onDeleted` runs after a
    /// successful delete has signed the user out.
    static func present(
        from presenter: UIViewController,
        context: UIContext,
        onDeleted: @escaping () -> Void
    ) {
        let alert = UIAlertController(
            title: LoginPageModel.deleteAlertTitle,
            message: LoginPageModel.deleteAlertBody,
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: LoginPageModel.cancelTitle, style: .default))
        alert.addAction(
            UIAlertAction(title: LoginPageModel.deleteConfirmTitle, style: .destructive) { [weak presenter] _ in
                guard let presenter else { return }
                // The Dart stacked a spinner over the dialog before the
                // DELETE (login.dart:749-764); presenting before this alert
                // finishes dismissing is swallowed, so run the flow from the
                // dismissal completion instead of a timed delay.
                presenter.dismiss(animated: true) {
                    performDelete(from: presenter, context: context, onDeleted: onDeleted)
                }
            }
        )
        presenter.present(alert, animated: true)
    }

    private static func performDelete(
        from presenter: UIViewController,
        context: UIContext,
        onDeleted: @escaping () -> Void
    ) {
        guard presenter.presentedViewController == nil else { return }
        let spinner = FullScreenSpinnerViewController.present(over: presenter)
        Task { @MainActor [weak presenter] in
            do {
                let result = try await context.api.deleteUser()
                spinner.dismissSpinner {
                    switch result {
                    case .deleted:
                        // DELETE 200 → sign out (login.dart:760-763); backend
                        // cascade removes Firebase + RevenueCat records.
                        Task { @MainActor in
                            await context.auth.signOut(purchases: context.purchases)
                            onDeleted()
                        }
                    case .error(let signal):
                        if let presenter { presentErrorSignal(signal, from: presenter, context: context) }
                    }
                }
            } catch {
                // Transport failure: the Dart left this as an unhandled
                // async error (no dialog).
                spinner.dismissSpinner()
            }
        }
    }

    private static func presentErrorSignal(
        _ signal: APIClient.ErrorSignal,
        from presenter: UIViewController,
        context: UIContext
    ) {
        switch signal {
        case .loginRequired:
            context.presentLogin()
        case .errorMessage(let text):
            presentAlert(title: "Error", message: text, from: presenter)
        case .errorBody(let status, let body):
            presentAlert(title: "Error \(status)", message: body, from: presenter)
        }
    }

    private static func presentAlert(title: String, message: String, from presenter: UIViewController) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        presenter.present(alert, animated: true)
    }
}
