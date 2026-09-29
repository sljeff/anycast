import Foundation
import Testing
@testable import Anycast

/// T8 EmailLogin copy + feedback mapping (05 §6.1 S18 / 03 §2.14): the
/// register-not-supported contract and the Firebase error → dialog mapping
/// (states/user.dart:219-252) — pure data, no auth calls.
@MainActor
struct EmailLoginCopyTests {

    @Test("Registration stays disabled; the button answers with a dialog")
    func registrationDisabled() {
        // login.dart:867 — setLogin(false) is commented out; the register
        // widget is unreachable and the Register button never switches modes.
        #expect(LoginPageModel.EmailLogin.supportsRegistration == false)
        #expect(LoginPageModel.EmailLogin.registerDialogTitle == "Sorry!")
        #expect(
            LoginPageModel.EmailLogin.registerDialogBody
                == "Please sign in with Apple or Google.\n\n"
                    + "We don't support email registration yet."
        )
    }

    @Test("Field hints and button titles (login.dart:841-883)")
    func fieldCopy() {
        #expect(LoginPageModel.EmailLogin.emailHint == "Email")
        #expect(LoginPageModel.EmailLogin.passwordHint == "Password")
        #expect(LoginPageModel.EmailLogin.loginButtonTitle == "Login")
        #expect(
            LoginPageModel.EmailLogin.registerButtonTitle
                == "Don't have an account? Register"
        )
    }

    @Test("user-not-found maps to the dedicated dialog (states/user.dart:227-230)")
    func userNotFound() {
        let feedback = LoginPageModel.EmailLogin.feedback(
            isFirebaseError: true,
            firebaseCode: LoginPageModel.EmailLogin.firebaseUserNotFoundCode,
            message: "anything"
        )
        #expect(feedback.title == "User Not Found")
        #expect(feedback.detail == "No user found for that email.")
    }

    @Test("wrong-password maps to the dedicated dialog (states/user.dart:231-234)")
    func wrongPassword() {
        let feedback = LoginPageModel.EmailLogin.feedback(
            isFirebaseError: true,
            firebaseCode: LoginPageModel.EmailLogin.firebaseWrongPasswordCode,
            message: "anything"
        )
        #expect(feedback.title == "Wrong Password")
        #expect(feedback.detail == "Wrong password provided for that user.")
    }

    @Test("Other Firebase errors keep the message under \"Firebase Error\"")
    func genericFirebaseError() {
        let feedback = LoginPageModel.EmailLogin.feedback(
            isFirebaseError: true,
            firebaseCode: 17_020, // network request failed
            message: "The network request was failed."
        )
        #expect(feedback.title == "Firebase Error")
        #expect(feedback.detail == "The network request was failed.")

        let noMessage = LoginPageModel.EmailLogin.feedback(
            isFirebaseError: true, firebaseCode: 17_000, message: nil
        )
        #expect(noMessage.title == "Firebase Error")
        #expect(noMessage.detail == "")
    }

    @Test("Non-Firebase errors use the generic bucket (states/user.dart:242-251)")
    func nonFirebaseError() {
        // E.g. AuthError.firebaseNotConfigured on a bare simulator run.
        let feedback = LoginPageModel.EmailLogin.feedback(
            isFirebaseError: false, firebaseCode: nil, message: "Firebase is not configured"
        )
        #expect(feedback.title == "Error")
        #expect(feedback.detail == "Firebase is not configured")
    }

    @Test("Firebase error code constants match FIRAuthErrorCode raw values")
    func codeConstants() {
        #expect(LoginPageModel.EmailLogin.firebaseWrongPasswordCode == 17_009)
        #expect(LoginPageModel.EmailLogin.firebaseInvalidCredentialCode == 17_004)
        #expect(LoginPageModel.EmailLogin.firebaseUserNotFoundCode == 17_011)
    }

    @Test("invalid-credential (17004) — the modern wrong-password answer — shares the Wrong Password dialog")
    func invalidCredentialMapsToWrongPassword() {
        let feedback = LoginPageModel.EmailLogin.feedback(
            isFirebaseError: true,
            firebaseCode: LoginPageModel.EmailLogin.firebaseInvalidCredentialCode,
            message: "The supplied auth credential is incorrect."
        )
        #expect(feedback.title == "Wrong Password")
        #expect(feedback.detail == "Wrong password provided for that user.")
    }
}
