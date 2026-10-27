import Foundation
import Testing
@testable import Anycast

/// T8 login page model parity (05 §6.1 S17 / 03 §2.14): the account
/// snapshot reduction and the dialog copy still shared by the account
/// surfaces — asserted against data, no live auth or store calls.
@MainActor
struct LoginPageModelTests {

    // MARK: - Account snapshot (login.dart:165-199)

    @Test("Provider icon mapping: apple default, google.com, password")
    func providerIcons() {
        #expect(LoginPageModel.providerIcon(providerID: nil) == .apple)
        #expect(LoginPageModel.providerIcon(providerID: "apple.com") == .apple)
        #expect(LoginPageModel.providerIcon(providerID: "google.com") == .google)
        #expect(LoginPageModel.providerIcon(providerID: "password") == .email)
    }

    @Test("signedIn is uid presence")
    func signedInFlag() {
        let signedIn = LoginPageModel.AccountSnapshot(
            uid: "u", email: nil, providerID: nil
        )
        let signedOut = LoginPageModel.AccountSnapshot(uid: nil, email: nil, providerID: nil)
        #expect(signedIn.signedIn)
        #expect(!signedOut.signedIn)
    }

    // MARK: - Dialog copy (verbatim)

    @Test("Alert copy matches the Dart strings")
    func alertCopy() {
        #expect(LoginPageModel.signOutAlertTitle == "Sign out")
        #expect(LoginPageModel.signOutAlertBody == "Are you sure you want to sign out?")
        #expect(LoginPageModel.deleteAlertTitle == "Permanently Delete Your Account?")
        #expect(
            LoginPageModel.deleteAlertBody == "Warning: This action will permanently delete "
                + "your account and all associated data. Once deleted, your account cannot "
                + "be recovered. Are you sure you want to proceed?"
        )
        #expect(LoginPageModel.deleteConfirmTitle == "Confirm")
        #expect(LoginPageModel.cancelTitle == "Cancel")
        #expect(LoginPageModel.purchaseErrorAlertTitle == "Error")
        #expect(LoginPageModel.restoreErrorAlertTitle == "Error")
        #expect(LoginPageModel.restoreErrorAlertBody == "No active entitlements")
        #expect(LoginPageModel.restoreSuccessAlertTitle == "Success")
        #expect(LoginPageModel.restoreSuccessAlertBody == "Restored purchases")
        #expect(LoginPageModel.copyEmailMenuTitle == "Copy email")
    }
}
