import Foundation

/// Pure model for the account surfaces (Membership B design): the Settings
/// identity row in its three states, the Membership page's status plate,
/// usage card and "Signed in with" text, and the shared date format. UI-free
/// so the fixtures in AnycastAppTests/Account assert against data, not UIKit.
nonisolated enum AccountPageModel {

    // MARK: - Tier

    enum Tier: Equatable, Sendable {
        case signedOut, free, plus
    }

    /// Plus follows the shipped rule: any active entitlement.
    static func tier(signedIn: Bool, isSubscribed: Bool) -> Tier {
        guard signedIn else { return .signedOut }
        return isSubscribed ? .plus : .free
    }

    /// AI transcripts included per period.
    static let freeTotal = 10
    static let plusTotal = 50

    // MARK: - Plus entitlement snapshot

    /// What the `plus` RevenueCat entitlement reports; nil upstream means no
    /// such entitlement (never Plus) or RevenueCat unavailable.
    struct PlusStatus: Equatable, Sendable {
        var isActive: Bool
        var isTrial: Bool
        var willRenew: Bool
        var hasBillingIssue: Bool
        var expirationDate: Date?
        var period: LoginPageModel.PlanPeriod

        init(
            isActive: Bool,
            isTrial: Bool = false,
            willRenew: Bool = true,
            hasBillingIssue: Bool = false,
            expirationDate: Date? = nil,
            period: LoginPageModel.PlanPeriod = .monthly
        ) {
            self.isActive = isActive
            self.isTrial = isTrial
            self.willRenew = willRenew
            self.hasBillingIssue = hasBillingIssue
            self.expirationDate = expirationDate
            self.period = period
        }
    }

    // MARK: - Dates

    /// "Oct 23, 2027" — fixed locale so the copy never follows the device
    /// region; the time zone is injectable like `LoginPageModel.formatExpiry`.
    static func formatDate(_ date: Date, timeZone: TimeZone = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "MMM d, yyyy"
        return formatter.string(from: date)
    }

    private static func periodTitle(_ period: LoginPageModel.PlanPeriod) -> String {
        period == .annual ? "Yearly" : "Monthly"
    }

    // MARK: - Settings identity row

    enum AvatarKind: Equatable, Sendable {
        /// `person.fill` in `onSurfaceVariant` (signed out, or no email).
        case glyph
        /// Uppercase first letter of the email.
        case initial(String)
    }

    enum IdentityTrailing: Equatable, Sendable {
        case action(String)
        case chevron
    }

    struct IdentityContent: Equatable, Sendable {
        var avatar: AvatarKind
        var title: String
        var subtitle: String
        var trailing: IdentityTrailing
    }

    static func identity(
        tier: Tier,
        email: String?,
        remaining: Int?,
        plus: PlusStatus?,
        timeZone: TimeZone = .current
    ) -> IdentityContent {
        if tier == .signedOut {
            return IdentityContent(
                avatar: .glyph,
                title: "Sign In & Sync",
                subtitle: "Get 10 free AI transcripts",
                trailing: .action("Sign In")
            )
        }
        let trimmed = email?.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasEmail = !(trimmed ?? "").isEmpty
        let avatar: AvatarKind = hasEmail
            ? .initial(String(trimmed!.prefix(1)).uppercased()) : .glyph
        let title = hasEmail ? trimmed! : "Signed in"
        let subtitle: String
        if tier == .plus {
            subtitle = plusIdentitySubtitle(plus, timeZone: timeZone)
        } else if let remaining {
            subtitle = "Free · \(clamp(remaining, to: freeTotal)) of \(freeTotal) transcripts left"
        } else {
            subtitle = "Free"
        }
        return IdentityContent(avatar: avatar, title: title, subtitle: subtitle, trailing: .chevron)
    }

    private static func plusIdentitySubtitle(_ plus: PlusStatus?, timeZone: TimeZone) -> String {
        guard let plus, let date = plus.expirationDate else { return "Plus" }
        let formatted = formatDate(date, timeZone: timeZone)
        if plus.isTrial { return "Plus · Trial ends \(formatted)" }
        if !plus.willRenew { return "Plus · Ends \(formatted)" }
        return "Plus · Renews \(formatted)"
    }

    /// The gold row under the identity row, shown to free users only.
    static let upgradePlateTitle = "Anycast Plus"
    static let upgradePlateSubtitle = "Bilingual subtitles and more"
    static let upgradePlateAction = "Upgrade"

    // MARK: - Membership status plate

    enum PlateAction: Equatable, Sendable {
        case manage, upgrade, getItBack
    }

    struct PlateContent: Equatable, Sendable {
        var title: String
        var meta: String
        /// Rendered in the error color right after `meta` (billing issue).
        var issue: String?
        var actionTitle: String
        var action: PlateAction
        /// The meta line under the plate (billing issue only).
        var billingNote: String?
    }

    static let billingNote = "Update your payment method in the App Store to keep Plus."

    /// `isSubscribed` covers the moment before the entitlement details have
    /// loaded: a Plus user never flashes the Upgrade plate.
    static func plate(
        isSubscribed: Bool,
        plus: PlusStatus?,
        timeZone: TimeZone = .current
    ) -> PlateContent {
        let title = "Anycast Plus"
        guard let plus else {
            return isSubscribed
                ? PlateContent(title: title, meta: "Plus", issue: nil,
                               actionTitle: "Manage", action: .manage, billingNote: nil)
                : free(title)
        }
        let date = plus.expirationDate.map { formatDate($0, timeZone: timeZone) }
        guard plus.isActive else {
            return PlateContent(
                title: title,
                meta: date.map { "Plus ended \($0)" } ?? "Plus ended",
                issue: nil, actionTitle: "Get it back", action: .getItBack, billingNote: nil
            )
        }
        let period = periodTitle(plus.period)
        if plus.isTrial {
            return PlateContent(
                title: title, meta: date.map { "Free trial · Ends \($0)" } ?? "Free trial",
                issue: nil, actionTitle: "Manage", action: .manage, billingNote: nil
            )
        }
        if plus.hasBillingIssue {
            return PlateContent(
                title: title, meta: "\(period) · ", issue: "Payment issue",
                actionTitle: "Manage", action: .manage, billingNote: billingNote
            )
        }
        let verb = plus.willRenew ? "Renews" : "Ends"
        return PlateContent(
            title: title, meta: date.map { "\(period) · \(verb) \($0)" } ?? period,
            issue: nil, actionTitle: "Manage", action: .manage, billingNote: nil
        )
    }

    private static func free(_ title: String) -> PlateContent {
        PlateContent(
            title: title, meta: "Bilingual subtitles and more", issue: nil,
            actionTitle: "Upgrade", action: .upgrade, billingNote: nil
        )
    }

    // MARK: - Usage card

    struct UsageContent: Equatable, Sendable {
        var title: String
        var left: Int?
        var total: Int
        var valueText: String
        /// Bar fill, 0...1; 0 while unknown.
        var fraction: Double
        var note: String

        var accessibilityValue: String { valueText }
    }

    /// Plus gets the monthly pool; free and expired accounts the lifetime 10.
    /// The API reports no reset date, so Plus only says "Resets monthly".
    static func usage(isSubscribed: Bool, remaining: Int?) -> UsageContent {
        let total = isSubscribed ? plusTotal : freeTotal
        let note = isSubscribed ? "Resets monthly" : "\(freeTotal) in total"
        guard let remaining else {
            return UsageContent(title: "AI transcripts", left: nil, total: total,
                                valueText: "…", fraction: 0, note: note)
        }
        let left = clamp(remaining, to: total)
        return UsageContent(
            title: "AI transcripts", left: left, total: total,
            valueText: "\(left) of \(total) left",
            fraction: Double(left) / Double(total), note: note
        )
    }

    private static func clamp(_ value: Int, to total: Int) -> Int {
        min(max(value, 0), total)
    }

    // MARK: - Account group

    /// Value of the Email row.
    static func emailRowValue(_ email: String?) -> String {
        guard let email, !email.isEmpty else { return "No email" }
        return email
    }

    /// "Signed in with" value from the Firebase provider id.
    static func signedInWithText(providerID: String?) -> String {
        switch LoginPageModel.providerIcon(providerID: providerID) {
        case .apple: return "Apple"
        case .google: return "Google"
        case .email: return "Email"
        }
    }

    // MARK: - Copy

    static let pageTitle = "Account"
    static let restorePurchasesTitle = "Restore Purchases"
    static let accountGroupTitle = "Account"
    static let emailRowTitle = "Email"
    static let signedInWithRowTitle = "Signed in with"
    static let signOutTitle = "Sign Out"
    static let deleteAccountTitle = "Delete Account"
    static let privacyTitle = "Privacy"
    static let termsTitle = "Terms"
}
