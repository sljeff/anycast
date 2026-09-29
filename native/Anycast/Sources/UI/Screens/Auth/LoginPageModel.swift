import Foundation

/// Pure model for the login sheet (lib/pages/login.dart, 03 §2.14): copy
/// strings, the logged-out/logged-in view-state reduction, plan selection,
/// and the carousel autoplay tick model. UI-free so the parity tests in
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

    /// login.dart:199 — a signed-in user without an email renders "No email".
    static func emailDisplay(for account: AccountSnapshot?) -> String {
        account?.email ?? "No email"
    }

    // MARK: - Subscription card (login.dart:309-396)

    struct SubscriptionCard: Equatable, Sendable {
        enum Tier: Equatable, Sendable { case basic, plus }

        var tier: Tier
        /// "Plan expires on yyyy-MM-dd HH:mm"; nil when not Plus or when the
        /// expiration is unknown.
        var expiryLine: String?
        /// nil = still loading / fetch failed → the card renders "..."
        /// (login.dart:314-319).
        var remainingCount: Int?
        var plusFlag: Int?

        var tierTitle: String { tier == .plus ? "Anycast Plus" : "Basic Plan" }
        var showsExpiry: Bool { expiryLine != nil }
        /// login.dart:321-323 — the suffix flips to the monthly wording only
        /// when `/api/user` reports plus == 1.
        var remainingSuffix: String {
            plusFlag == 1 ? " Transcriptions left (this month)" : " Transcriptions left"
        }
    }

    static func subscriptionCard(
        isSubscribed: Bool,
        plusExpiration: Date?,
        remaining: Int?,
        plusFlag: Int?,
        timeZone: TimeZone = .current
    ) -> SubscriptionCard {
        // The Dart builds the Basic card early-return and only the Plus
        // branch formats an expiration (login.dart:342-394).
        SubscriptionCard(
            tier: isSubscribed ? .plus : .basic,
            expiryLine: (isSubscribed ? plusExpiration : nil).map {
                formatExpiry($0, timeZone: timeZone)
            },
            remainingCount: remaining,
            plusFlag: plusFlag
        )
    }

    /// login.dart:370-373 — `Jiffy.parse(expirationDate, isUtc: true).toLocal()
    /// .format('yyyy-MM-dd HH:mm')`. The RevenueCat expirationDate is a true
    /// instant (unlike the `/api/user` `expired_at` G11 wall-clock path), so
    /// this is a plain local rendering.
    static func formatExpiry(_ date: Date, timeZone: TimeZone = .current) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        return String(
            format: "%04d-%02d-%02d %02d:%02d",
            parts.year ?? 0, parts.month ?? 0, parts.day ?? 0,
            parts.hour ?? 0, parts.minute ?? 0
        )
    }

    // MARK: - Plan cards / selection (login.dart:448-645, states/user.dart:268)

    enum PlanPeriod: Equatable, Sendable {
        case monthly, annual
    }

    struct PlanCard: Equatable, Hashable, Sendable {
        let productID: String
        let period: PlanPeriod
        /// `storeProduct.priceString`, e.g. "$2.99".
        let priceString: String

        /// login.dart:578-583 — annual packages are titled "Yearly"/"Year".
        var title: String { period == .annual ? "Yearly" : "Monthly" }
        var unit: String { period == .annual ? "Year" : "Month" }
        var priceLine: String { "\(priceString)/\(unit)" }
        /// login.dart:632-633 — two-line caption under the card.
        var autoRenewalCaption: String {
            "Auto Renewal\n\(priceString)/\(unit.lowercased())"
        }
    }

    /// The `choosenPlan` state (states/user.dart:268). iOS default is the
    /// `anycast_monthly` product id; the Android id is the isAndroid branch,
    /// not taken here (03 §9).
    struct PlanSelection: Equatable, Sendable {
        static let iOSDefaultPlanID = "anycast_monthly"

        var chosenPlanID: String

        init(chosenPlanID: String = PlanSelection.iOSDefaultPlanID) {
            self.chosenPlanID = chosenPlanID
        }

        mutating func choose(_ planID: String) { chosenPlanID = planID }

        func isSelected(_ card: PlanCard) -> Bool { card.productID == chosenPlanID }

        /// login.dart:478-501 — the package behind Confirm purchase; nil
        /// triggers the "Invalid plan" dialog.
        func selectedCard(available: [PlanCard]) -> PlanCard? {
            available.first { $0.productID == chosenPlanID }
        }
    }

    /// login.dart:660-663 — "Annually" only when the chosen id contains
    /// "annual"; any other id reads "Monthly".
    static func plusIntroTitle(chosenPlanID: String) -> String {
        chosenPlanID.contains("annual")
            ? "Anycast Plus (Annually)"
            : "Anycast Plus (Monthly)"
    }

    /// Benefit bullets (login.dart:676-712): prefix + bold fragment + suffix.
    struct BenefitBullet: Equatable, Sendable {
        let prefix: String
        let bold: String
        let suffix: String
    }

    static let plusBenefits: [BenefitBullet] = [
        BenefitBullet(prefix: "- ", bold: "50 TIMES", suffix: " AI Transcription every month"),
        BenefitBullet(prefix: "- ", bold: "Unlimited", suffix: " subtitle translation"),
        BenefitBullet(prefix: "- ", bold: "", suffix: "Export subtitle to your note app"),
    ]

    // MARK: - Carousel (login.dart:426-447)

    /// carousel_slider defaults for this page: 2 full-width slides, aspect
    /// 2:1, autoplay every 4 s wrapping around, paused while touched.
    struct CarouselAutoplay: Equatable, Sendable {
        static let slideCount = 2
        static let autoplayInterval: TimeInterval = 4

        private(set) var pageIndex = 0
        private(set) var paused = false

        mutating func tick() {
            guard !paused, Self.slideCount > 1 else { return }
            pageIndex = (pageIndex + 1) % Self.slideCount
        }

        mutating func setUserPage(_ index: Int) {
            guard Self.slideCount > 0 else { return }
            pageIndex = ((index % Self.slideCount) + Self.slideCount) % Self.slideCount
        }

        mutating func pause() { paused = true }
        mutating func resume() { paused = false }
    }

    // MARK: - Copy (verbatim from login.dart / privacy.dart)

    // Logged-out (login.dart:45-126)
    static let signUpHeadline = "Sign up now \n\n&\n\nGet 3 free audio transcriptions!"
    static let appleButtonTitle = "Sign in with Apple"
    static let googleButtonTitle = "Sign in with Google"
    static let emailButtonTitle = "Sign in with Email"

    // User Info card (login.dart:181-298)
    static let userInfoTitle = "User Info"
    static let copyEmailMenuTitle = "Copy email"
    static let signOutMenuTitle = "Sign out"
    static let signOutAlertTitle = "Sign out"
    static let signOutAlertBody = "Are you sure you want to sign out?"

    // Paywall (login.dart:412-569)
    static let paywallTitle = "Anycast Plus Plan"
    static let autoRenewalTooltip = "Auto renewal is on.\n"
        + "But you can easily cancel it at any time\nfrom App Store."
    static let confirmPurchaseTitle = "Confirm purchase"
    static let restorePurchasesTitle = "restore purchases"
    static let invalidPlanAlertTitle = "Error"
    static let invalidPlanAlertBody = "Invalid plan"
    static let purchaseErrorAlertTitle = "Error"
    static let restoreErrorAlertTitle = "Error"
    static let restoreErrorAlertBody = "No active entitlements"
    static let restoreSuccessAlertTitle = "Success"
    static let restoreSuccessAlertBody = "Restored purchases"

    // Privacy (privacy.dart:22-43)
    static let privacyPolicyTitle = "Privacy Policy"
    static let termsOfUseTitle = "Terms of Use (EULA)"
    static let privacyPolicyURL = URL(string: "https://privacy.anycast.website")!
    static let termsOfUseURL = URL(
        string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/"
    )!

    // Remove account (login.dart:735-789)
    static let deleteButtonTitle = "Permanently Delete Account"
    static let deleteAlertTitle = "Permanently Delete Your Account?"
    static let deleteAlertBody = "Warning: This action will permanently delete your account "
        + "and all associated data. Once deleted, your account cannot be recovered. "
        + "Are you sure you want to proceed?"
    static let deleteConfirmTitle = "Confirm"
    static let cancelTitle = "Cancel"

    // MARK: - Email login (login.dart:832-936, states/user.dart:219-252)

    enum EmailLogin {

        /// Registration UI exists in the Dart but is unreachable
        /// (`setLogin(false)` is commented out); the Register button answers
        /// with a dialog instead (login.dart:865-883).
        static let supportsRegistration = false

        static let emailHint = "Email"
        static let passwordHint = "Password"
        static let loginButtonTitle = "Login"
        static let registerButtonTitle = "Don't have an account? Register"
        static let registerDialogTitle = "Sorry!"
        static let registerDialogBody = "Please sign in with Apple or Google.\n\n"
            + "We don't support email registration yet."

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
