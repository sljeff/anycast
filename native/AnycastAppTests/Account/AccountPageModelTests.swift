import Foundation
import Testing
@testable import Anycast

/// Account page model (Membership B): tier, the Settings identity row, the
/// Membership status plate, usage card, "Signed in with" text, and the date
/// format — asserted against data, independent of the live UI.
@MainActor
struct AccountPageModelTests {

    private let utc = TimeZone(identifier: "UTC")!
    /// 2027-10-23 12:00 UTC.
    private let renewal = Date(timeIntervalSince1970: 1_824_292_800)

    private func status(
        active: Bool = true,
        trial: Bool = false,
        renews: Bool = true,
        billingIssue: Bool = false,
        date: Date? = nil,
        period: LoginPageModel.PlanPeriod = .monthly
    ) -> AccountPageModel.PlusStatus {
        AccountPageModel.PlusStatus(
            isActive: active, isTrial: trial, willRenew: renews,
            hasBillingIssue: billingIssue, expirationDate: date ?? renewal, period: period
        )
    }

    // MARK: - Dates / tier

    @Test("Dates read 'MMM d, yyyy' in the injected zone, locale-independent")
    func dateFormat() {
        #expect(AccountPageModel.formatDate(renewal, timeZone: utc) == "Oct 23, 2027")
        // 12:00 UTC is already the next day in Auckland.
        let auckland = TimeZone(identifier: "Pacific/Auckland")!
        #expect(AccountPageModel.formatDate(renewal, timeZone: auckland) == "Oct 24, 2027")
        let early = Date(timeIntervalSince1970: 1_798_848_000) // 2027-01-02 00:00 UTC
        #expect(AccountPageModel.formatDate(early, timeZone: utc) == "Jan 2, 2027")
    }

    @Test("Tier: signed out wins, then any active entitlement means Plus")
    func tiers() {
        #expect(AccountPageModel.tier(signedIn: false, isSubscribed: true) == .signedOut)
        #expect(AccountPageModel.tier(signedIn: true, isSubscribed: false) == .free)
        #expect(AccountPageModel.tier(signedIn: true, isSubscribed: true) == .plus)
    }

    // MARK: - Identity row

    @Test("Signed out: person glyph, Sign In action, no chevron")
    func identitySignedOut() {
        let content = AccountPageModel.identity(tier: .signedOut, email: "a@b.co", remaining: 3, plus: nil)
        #expect(content == AccountPageModel.IdentityContent(
            avatar: .glyph, title: "Sign In & Sync",
            subtitle: "Get 10 free AI transcripts", trailing: .action("Sign In")
        ))
    }

    @Test("Free: initial avatar, email title, quota subtitle, chevron")
    func identityFree() {
        let content = AccountPageModel.identity(tier: .free, email: "jeff@example.com", remaining: 7, plus: nil)
        #expect(content == AccountPageModel.IdentityContent(
            avatar: .initial("J"), title: "jeff@example.com",
            subtitle: "Free · 7 of 10 transcripts left", trailing: .chevron
        ))
    }

    @Test("Free: unknown remaining reads just 'Free'; remaining is clamped")
    func identityFreeUnknownAndClamped() {
        #expect(AccountPageModel.identity(tier: .free, email: "a@b.co", remaining: nil, plus: nil).subtitle == "Free")
        #expect(AccountPageModel.identity(tier: .free, email: "a@b.co", remaining: 99, plus: nil).subtitle
            == "Free · 10 of 10 transcripts left")
        #expect(AccountPageModel.identity(tier: .free, email: "a@b.co", remaining: -2, plus: nil).subtitle
            == "Free · 0 of 10 transcripts left")
    }

    @Test("Signed in without an email: glyph avatar and 'Signed in' title")
    func identityMissingEmail() {
        for email in [nil, "", "  "] as [String?] {
            let content = AccountPageModel.identity(tier: .free, email: email, remaining: nil, plus: nil)
            #expect(content.avatar == .glyph)
            #expect(content.title == "Signed in")
        }
    }

    @Test("Plus subtitle: renews, trial, ending, and unknown date")
    func identityPlus() {
        func subtitle(_ plus: AccountPageModel.PlusStatus?) -> String {
            AccountPageModel.identity(
                tier: .plus, email: "a@b.co", remaining: 10, plus: plus, timeZone: utc
            ).subtitle
        }
        #expect(subtitle(status()) == "Plus · Renews Oct 23, 2027")
        #expect(subtitle(status(trial: true)) == "Plus · Trial ends Oct 23, 2027")
        #expect(subtitle(status(renews: false)) == "Plus · Ends Oct 23, 2027")
        #expect(subtitle(nil) == "Plus")
        #expect(subtitle(AccountPageModel.PlusStatus(isActive: true, expirationDate: nil)) == "Plus")
        let content = AccountPageModel.identity(tier: .plus, email: "z@b.co", remaining: nil, plus: status())
        #expect(content.avatar == .initial("Z"))
        #expect(content.trailing == .chevron)
    }

    @Test("Upgrade plate copy")
    func upgradePlateCopy() {
        #expect(AccountPageModel.upgradePlateTitle == "Anycast Plus")
        #expect(AccountPageModel.upgradePlateSubtitle == "Bilingual subtitles and more")
        #expect(AccountPageModel.upgradePlateAction == "Upgrade")
    }

    // MARK: - Status plate

    private func plate(isSubscribed: Bool = true, _ plus: AccountPageModel.PlusStatus?) -> AccountPageModel.PlateContent {
        AccountPageModel.plate(isSubscribed: isSubscribed, plus: plus, timeZone: utc)
    }

    @Test("Trial plate")
    func plateTrial() {
        let content = plate(status(trial: true))
        #expect(content.meta == "Free trial · Ends Oct 23, 2027")
        #expect(content.actionTitle == "Manage")
        #expect(content.action == .manage)
        #expect(content.issue == nil)
        #expect(content.billingNote == nil)
    }

    @Test("Active plate: renewing and cancelled, yearly and monthly")
    func plateActive() {
        #expect(plate(status(period: .annual)).meta == "Yearly · Renews Oct 23, 2027")
        #expect(plate(status(period: .monthly)).meta == "Monthly · Renews Oct 23, 2027")
        #expect(plate(status(renews: false, period: .annual)).meta == "Yearly · Ends Oct 23, 2027")
        #expect(plate(status(renews: false)).action == .manage)
    }

    @Test("Billing issue plate carries the issue suffix and the note")
    func plateBillingIssue() {
        let content = plate(status(billingIssue: true, period: .annual))
        #expect(content.meta == "Yearly · ")
        #expect(content.issue == "Payment issue")
        #expect(content.actionTitle == "Manage")
        #expect(content.billingNote == "Update your payment method in the App Store to keep Plus.")
    }

    @Test("Expired plate offers to get Plus back")
    func plateExpired() {
        let content = plate(isSubscribed: false, status(active: false))
        #expect(content.meta == "Plus ended Oct 23, 2027")
        #expect(content.actionTitle == "Get it back")
        #expect(content.action == .getItBack)
    }

    @Test("Free plate upgrades; an unloaded Plus user never sees it")
    func plateFreeAndUnloaded() {
        let free = plate(isSubscribed: false, nil)
        #expect(free.meta == "Bilingual subtitles and more")
        #expect(free.actionTitle == "Upgrade")
        #expect(free.action == .upgrade)

        let unloaded = plate(isSubscribed: true, nil)
        #expect(unloaded.action == .manage)
    }

    // MARK: - Usage

    @Test("Usage: Plus pool of 50 resets monthly")
    func usagePlus() {
        let usage = AccountPageModel.usage(isSubscribed: true, remaining: 32)
        #expect(usage.total == 50)
        #expect(usage.left == 32)
        #expect(usage.valueText == "32 of 50 left")
        #expect(usage.fraction == 32.0 / 50.0)
        #expect(usage.note == "Resets monthly")
        #expect(usage.accessibilityValue == "32 of 50 left")
        #expect(usage.title == "AI transcripts")
    }

    @Test("Usage: free pool of 10 is a lifetime total")
    func usageFree() {
        let usage = AccountPageModel.usage(isSubscribed: false, remaining: 4)
        #expect(usage.total == 10)
        #expect(usage.valueText == "4 of 10 left")
        #expect(usage.fraction == 0.4)
        #expect(usage.note == "10 in total")
    }

    @Test("Usage: remaining is clamped into 0...total")
    func usageClamped() {
        #expect(AccountPageModel.usage(isSubscribed: false, remaining: 40).valueText == "10 of 10 left")
        #expect(AccountPageModel.usage(isSubscribed: false, remaining: 40).fraction == 1)
        #expect(AccountPageModel.usage(isSubscribed: true, remaining: -5).valueText == "0 of 50 left")
        #expect(AccountPageModel.usage(isSubscribed: true, remaining: -5).fraction == 0)
    }

    @Test("Usage: unknown remaining shows an ellipsis and an empty bar")
    func usageUnknown() {
        let usage = AccountPageModel.usage(isSubscribed: true, remaining: nil)
        #expect(usage.left == nil)
        #expect(usage.valueText == "…")
        #expect(usage.fraction == 0)
        #expect(usage.total == 50)
    }

    // MARK: - Account group

    @Test("Signed in with: provider ids map to Apple / Google / Email")
    func signedInWith() {
        #expect(AccountPageModel.signedInWithText(providerID: "apple.com") == "Apple")
        #expect(AccountPageModel.signedInWithText(providerID: "google.com") == "Google")
        #expect(AccountPageModel.signedInWithText(providerID: "password") == "Email")
        #expect(AccountPageModel.signedInWithText(providerID: nil) == "Apple")
    }

    @Test("Email row value falls back to 'No email'")
    func emailValue() {
        #expect(AccountPageModel.emailRowValue("a@b.co") == "a@b.co")
        #expect(AccountPageModel.emailRowValue(nil) == "No email")
        #expect(AccountPageModel.emailRowValue("") == "No email")
    }
}
