import Foundation

/// What opened the login sheet; picks the title and subtitle copy.
nonisolated enum LoginSource: Equatable, Sendable {
    /// The signed-out Settings identity row.
    case settings
    /// A purchase attempt while signed out (batch 3).
    case paywall
    /// "Generate" on a transcript while signed out.
    case transcribe
    /// A 401 on an account that was signed in (session expired).
    case reauth
}

/// The three ways to sign in. The raw value is the Firebase provider id, which
/// is also what `LastSignInProviderStore` persists.
nonisolated enum LoginProvider: String, CaseIterable, Equatable, Sendable {
    case apple = "apple.com"
    case google = "google.com"
    case email = "password"

    var buttonTitle: String {
        switch self {
        case .apple: "Continue with Apple"
        case .google: "Continue with Google"
        case .email: "Continue with Email"
        }
    }
}

/// Remembers the provider of the last successful sign-in so a session-expired
/// sheet can lead with it. Namespaced key; the defaults store is injectable
/// for tests.
/// `UserDefaults` is documented thread-safe, hence the unchecked conformance.
nonisolated struct LastSignInProviderStore: @unchecked Sendable {

    static let key = "anycast.lastSignInProvider"
    static let standard = LastSignInProviderStore(defaults: .standard)

    let defaults: UserDefaults

    func record(_ provider: LoginProvider) {
        defaults.set(provider.rawValue, forKey: Self.key)
    }

    /// nil when nothing was recorded or the stored value is unknown.
    func load() -> LoginProvider? {
        defaults.string(forKey: Self.key).flatMap(LoginProvider.init(rawValue:))
    }
}

/// Pure model for the login sheet (Login A): the copy per opening context,
/// the three stages of the one sheet, which provider leads, and the
/// forgot-password email check. UI-free so the fixtures in
/// AnycastAppTests/Auth assert against data, not UIKit.
nonisolated struct LoginSheetModel: Equatable, Sendable {

    /// `apple`: one primary button and the "Other ways" link. `more`: the
    /// remaining providers appear in place. `email`: the sign-in form.
    enum Stage: Equatable, Sendable {
        case apple, more, email
    }

    let source: LoginSource
    /// The account's last-used provider; only the reauth source reads it.
    let lastProvider: LoginProvider?
    private(set) var stage: Stage = .apple

    init(source: LoginSource, lastProvider: LoginProvider? = nil) {
        self.source = source
        self.lastProvider = lastProvider
    }

    // MARK: - Copy

    static let emailTitle = "Sign in with email"
    /// Email registration stays unsupported, so the subtitle never offers it.
    static let emailSubtitle = "Use the email you signed up with"
    static let otherWaysTitle = "Other ways to sign in"
    static let emailOtherWaysTitle = "Other ways"
    static let emailHint = "Email"
    static let passwordHint = "Password"
    static let signInTitle = "Sign In"
    static let forgotTitle = "Forgot?"
    static let resetSentMessage = "Check your inbox for a reset link"
    static let resetNeedsEmailMessage = "Enter your email above first"

    static func title(for source: LoginSource) -> String {
        switch source {
        case .settings: "Sign In & Sync"
        case .paywall: "Sign in to continue"
        case .transcribe: "Sign in to transcribe"
        case .reauth: "Sign in again"
        }
    }

    static func subtitle(for source: LoginSource) -> String {
        switch source {
        case .settings, .transcribe: "Get 10 free AI transcripts"
        case .paywall: "Plus stays with your account"
        case .reauth: "Session expired. Nothing is lost."
        }
    }

    var title: String { stage == .email ? Self.emailTitle : Self.title(for: source) }
    var subtitle: String { stage == .email ? Self.emailSubtitle : Self.subtitle(for: source) }

    // MARK: - Providers

    /// Reauth leads with the account's last-used provider; every other
    /// source, and reauth with nothing stored, leads with Apple.
    var primaryProvider: LoginProvider {
        source == .reauth ? (lastProvider ?? .apple) : .apple
    }

    /// The other two providers, in Apple, Google, Email order.
    var alternativeProviders: [LoginProvider] {
        LoginProvider.allCases.filter { $0 != primaryProvider }
    }

    // MARK: - Stages

    /// The "Other ways to sign in" link under the primary button.
    var showsOtherWaysLink: Bool { stage == .apple }
    /// The two secondary provider buttons.
    var showsAlternatives: Bool { stage == .more }
    var showsEmailForm: Bool { stage == .email }

    mutating func showMoreWays() { stage = .more }
    mutating func showEmailForm() { stage = .email }

    // MARK: - Forgot password

    /// The trimmed address when it looks like one (`a@b.c`: one `@`, text on
    /// both sides, a dot inside the domain, no whitespace); nil otherwise.
    static func resetEmail(from raw: String) -> String? {
        let email = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = email.split(separator: "@", omittingEmptySubsequences: false)
        guard parts.count == 2, !parts[0].isEmpty, !parts[1].isEmpty,
              !email.contains(where: \.isWhitespace) else { return nil }
        let domain = parts[1]
        guard let dot = domain.lastIndex(of: "."),
              dot != domain.startIndex,
              domain.index(after: dot) != domain.endIndex else { return nil }
        return email
    }
}
