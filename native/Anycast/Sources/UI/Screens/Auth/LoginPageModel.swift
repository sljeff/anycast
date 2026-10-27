import Foundation

/// Shared account models and copy from the Dart login page
/// (lib/pages/login.dart, 03 §2.14): the signed-in account snapshot, the
/// plan period, the restore / sign-out / delete dialog copy, the legal URLs
/// and the email-login error mapping. UI-free so the tests in
/// AnycastAppTests/Auth assert against data, not UIKit.
nonisolated enum LoginPageModel {

    // MARK: - Account snapshot (login.dart:165-172, 199)

    /// Firebase provider ids as `providerData[0].providerId` reports them.
    enum ProviderIcon: Equatable, Sendable {
        case apple, google, email
    }

    struct AccountSnapshot: Equatable, Sendable {
        var uid: String?
        var email: String?
        /// "apple.com" / "google.com" / "password".
        var providerID: String?

        var signedIn: Bool { uid != nil }
    }

    /// login.dart:166-172 — apple is the default; only google.com and
    /// password switch the avatar icon.
    static func providerIcon(providerID: String?) -> ProviderIcon {
        switch providerID {
        case "google.com": return .google
        case "password": return .email
        default: return .apple
        }
    }

    // MARK: - Plan period

    enum PlanPeriod: Equatable, Sendable {
        case monthly, annual
    }

    // MARK: - Copy (verbatim from login.dart / privacy.dart)

    // User Info card (login.dart:181-298)
    static let copyEmailMenuTitle = "Copy email"
    static let signOutMenuTitle = "Sign out"
    static let signOutAlertTitle = "Sign out"
    static let signOutAlertBody = "Are you sure you want to sign out?"

    // Paywall (login.dart:412-569)
    static let purchaseErrorAlertTitle = "Error"
    static let restoreErrorAlertTitle = "Error"
    static let restoreErrorAlertBody = "No active entitlements"
    static let restoreSuccessAlertTitle = "Success"
    static let restoreSuccessAlertBody = "Restored purchases"

    // Privacy (privacy.dart:22-43)
    static let privacyPolicyURL = URL(string: "https://privacy.anycast.website")!
    static let termsOfUseURL = URL(
        string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/"
    )!

    // Remove account (login.dart:735-789)
    static let deleteAlertTitle = "Permanently Delete Your Account?"
    static let deleteAlertBody = "Warning: This action will permanently delete your account "
        + "and all associated data. Once deleted, your account cannot be recovered. "
        + "Are you sure you want to proceed?"
    static let deleteConfirmTitle = "Confirm"
    static let cancelTitle = "Cancel"

    // MARK: - Email login (login.dart:832-936, states/user.dart:219-252)

    enum EmailLogin {

        struct Feedback: Equatable, Sendable {
            let title: String
            let detail: String
        }

        /// FIRAuthErrorCodeWrongPassword (17009) — what the Dart string
        /// 'wrong-password' (states/user.dart:231-234) maps to on iOS.
        static let firebaseWrongPasswordCode = 17_009
        /// FIRAuthErrorCodeInvalidCredential (17004) — the modern Firebase
        /// backend's answer to a bad email/password pair; same user-facing
        /// outcome, so it shares the Wrong Password dialog.
        static let firebaseInvalidCredentialCode = 17_004
        static let firebaseUserNotFoundCode = 17_011

        /// states/user.dart:224-252 — Firebase auth errors map their code to
        /// title/detail (message kept verbatim otherwise); non-Firebase
        /// errors get the generic "Error" bucket.
        static func feedback(
            isFirebaseError: Bool,
            firebaseCode: Int?,
            message: String?
        ) -> Feedback {
            if isFirebaseError {
                switch firebaseCode {
                case firebaseUserNotFoundCode:
                    return Feedback(title: "User Not Found", detail: "No user found for that email.")
                case firebaseWrongPasswordCode, firebaseInvalidCredentialCode:
                    return Feedback(
                        title: "Wrong Password",
                        detail: "Wrong password provided for that user."
                    )
                default:
                    return Feedback(title: "Firebase Error", detail: message ?? "")
                }
            }
            return Feedback(title: "Error", detail: message ?? "")
        }
    }
}
