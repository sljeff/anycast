import Foundation
import Testing
@testable import Anycast

/// T8 login page model parity (05 §6.1 S17 / 03 §2.14): logged-out copy,
/// account snapshot reduction, subscription card states, and expiry
/// formatting — asserted against data, no live auth or store calls.
@MainActor
struct LoginPageModelTests {

    // MARK: - Logged-out copy (login.dart:45-126)

    @Test("Headline is the Dart string verbatim, blank lines included")
    func signUpHeadline() {
        #expect(
            LoginPageModel.signUpHeadline
                == "Sign up now \n\n&\n\nGet 3 free audio transcriptions!"
        )
        #expect(
            LoginPageModel.signUpHeadline.contains("\n\n&\n\n")
        )
    }

    @Test("Auth button order and titles (login.dart:66-127)")
    func authButtonTitles() {
        #expect(LoginPageModel.appleButtonTitle == "Sign in with Apple")
        #expect(LoginPageModel.googleButtonTitle == "Sign in with Google")
        #expect(LoginPageModel.emailButtonTitle == "Sign in with Email")
    }

    // MARK: - Account snapshot (login.dart:165-199)

    @Test("Provider icon mapping: apple default, google.com, password")
    func providerIcons() {
        #expect(LoginPageModel.providerIcon(providerID: nil) == .apple)
        #expect(LoginPageModel.providerIcon(providerID: "apple.com") == .apple)
        #expect(LoginPageModel.providerIcon(providerID: "google.com") == .google)
        #expect(LoginPageModel.providerIcon(providerID: "password") == .email)
    }

    @Test("Email display falls back to \"No email\" (login.dart:199)")
    func emailFallback() {
        #expect(LoginPageModel.emailDisplay(for: nil) == "No email")
        let noEmail = LoginPageModel.AccountSnapshot(
            uid: "u1", email: nil, providerID: "google.com"
        )
        #expect(LoginPageModel.emailDisplay(for: noEmail) == "No email")
        let withEmail = LoginPageModel.AccountSnapshot(
            uid: "u1", email: "a@b.c", providerID: "password"
        )
        #expect(LoginPageModel.emailDisplay(for: withEmail) == "a@b.c")
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

    // MARK: - Subscription card (login.dart:309-396)

    @Test("Basic card: Basic Plan, no expiry, monthly suffix only without plus")
    func basicCard() {
        let card = LoginPageModel.subscriptionCard(
            isSubscribed: false, plusExpiration: Date(), remaining: 7, plusFlag: 0
        )
        #expect(card.tier == .basic)
        #expect(card.tierTitle == "Basic Plan")
        #expect(card.expiryLine == nil)
        #expect(card.showsExpiry == false)
        #expect(card.remainingCount == 7)
        #expect(card.remainingSuffix == " Transcriptions left")
    }

    @Test("Plus card: title, expiry line, monthly remaining suffix (plus == 1)")
    func plusCard() {
        // 2026-03-05 06:07:08 UTC → fixed zone for a deterministic string.
        let gmtPlus8 = TimeZone(secondsFromGMT: 8 * 3600)!
        let date = Date(timeIntervalSince1970: 1_772_690_828) // 2026-03-05T06:07:08Z
        let card = LoginPageModel.subscriptionCard(
            isSubscribed: true, plusExpiration: date, remaining: 42, plusFlag: 1,
            timeZone: gmtPlus8
        )
        #expect(card.tier == .plus)
        #expect(card.tierTitle == "Anycast Plus")
        #expect(card.expiryLine == "2026-03-05 14:07")
        #expect(card.showsExpiry)
        #expect(card.remainingSuffix == " Transcriptions left (this month)")
    }

    @Test("Loading state renders \"...\" (login.dart:317-319)")
    func remainingLoading() {
        let card = LoginPageModel.subscriptionCard(
            isSubscribed: false, plusExpiration: nil, remaining: nil, plusFlag: nil
        )
        #expect(card.remainingCount == nil)
    }

    @Test("Subscribed without a known expiration omits the expiry row")
    func plusWithoutExpiration() {
        let card = LoginPageModel.subscriptionCard(
            isSubscribed: true, plusExpiration: nil, remaining: 50, plusFlag: 1
        )
        #expect(card.tier == .plus)
        #expect(card.expiryLine == nil)
        #expect(card.showsExpiry == false)
    }

    @Test("Expiry formatter is zero-padded 24-hour local (login.dart:370-373)")
    func expiryFormatter() {
        let utc = TimeZone(identifier: "UTC")!
        // 2024-07-29T15:35:52Z
        let date = Date(timeIntervalSince1970: 1_722_267_352)
        #expect(LoginPageModel.formatExpiry(date, timeZone: utc) == "2024-07-29 15:35")
        // Same instant at UTC-11 crosses the day backwards.
        let minus11 = TimeZone(secondsFromGMT: -11 * 3600)!
        #expect(LoginPageModel.formatExpiry(date, timeZone: minus11) == "2024-07-29 04:35")
        // Single-digit month/day/hour zero padding: 2026-01-02T03:04:05Z.
        let early = Date(timeIntervalSince1970: 1_767_323_045)
        #expect(LoginPageModel.formatExpiry(early, timeZone: utc) == "2026-01-02 03:04")
    }

    // MARK: - Dialog copy (verbatim)

    @Test("Alert copy matches the Dart strings")
    func alertCopy() {
        #expect(LoginPageModel.signOutAlertTitle == "Sign out")
        #expect(LoginPageModel.signOutAlertBody == "Are you sure you want to sign out?")
        #expect(LoginPageModel.deleteButtonTitle == "Permanently Delete Account")
        #expect(LoginPageModel.deleteAlertTitle == "Permanently Delete Your Account?")
        #expect(
            LoginPageModel.deleteAlertBody == "Warning: This action will permanently delete "
                + "your account and all associated data. Once deleted, your account cannot "
                + "be recovered. Are you sure you want to proceed?"
        )
        #expect(LoginPageModel.deleteConfirmTitle == "Confirm")
        #expect(LoginPageModel.cancelTitle == "Cancel")
        #expect(LoginPageModel.invalidPlanAlertTitle == "Error")
        #expect(LoginPageModel.invalidPlanAlertBody == "Invalid plan")
        #expect(LoginPageModel.restoreErrorAlertTitle == "Error")
        #expect(LoginPageModel.restoreErrorAlertBody == "No active entitlements")
        #expect(LoginPageModel.restoreSuccessAlertTitle == "Success")
        #expect(LoginPageModel.restoreSuccessAlertBody == "Restored purchases")
        #expect(LoginPageModel.confirmPurchaseTitle == "Confirm purchase")
        #expect(LoginPageModel.restorePurchasesTitle == "restore purchases")
        #expect(LoginPageModel.userInfoTitle == "User Info")
        #expect(LoginPageModel.copyEmailMenuTitle == "Copy email")
        #expect(LoginPageModel.paywallTitle == "Anycast Plus Plan")
        #expect(LoginPageModel.autoRenewalTooltip.contains("Auto renewal is on."))
        #expect(LoginPageModel.autoRenewalTooltip.contains("from App Store."))
    }

    @Test("Plus benefit bullets bold the Dart fragments (login.dart:685-711)")
    func benefitBullets() {
        #expect(LoginPageModel.plusBenefits.count == 3)
        #expect(LoginPageModel.plusBenefits[0].bold == "50 TIMES")
        #expect(LoginPageModel.plusBenefits[0].suffix == " AI Transcription every month")
        #expect(LoginPageModel.plusBenefits[1].bold == "Unlimited")
        #expect(LoginPageModel.plusBenefits[1].suffix == " subtitle translation")
        #expect(
            LoginPageModel.plusBenefits[2].prefix + LoginPageModel.plusBenefits[2].bold
                + LoginPageModel.plusBenefits[2].suffix
                == "- Export subtitle to your note app"
        )
    }
}
