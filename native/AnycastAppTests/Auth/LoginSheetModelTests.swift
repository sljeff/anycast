import Foundation
import Testing
@testable import Anycast

/// Login sheet model (Login A): copy per opening context, the stage
/// transitions, which provider leads on reauth, the persisted last provider,
/// and the forgot-password email check — asserted against data.
struct LoginSheetModelTests {

    // MARK: - Copy

    @Test("Copy per source: title and subtitle")
    func copyPerSource() {
        let expected: [(LoginSource, String, String)] = [
            (.settings, "Sign In & Sync", "Get 10 free AI transcripts"),
            (.paywall, "Sign in to continue", "Plus stays with your account"),
            (.transcribe, "Sign in to transcribe", "Get 10 free AI transcripts"),
            (.reauth, "Sign in again", "Session expired. Nothing is lost."),
        ]
        for (source, title, subtitle) in expected {
            let model = LoginSheetModel(source: source)
            #expect(model.title == title)
            #expect(model.subtitle == subtitle)
        }
    }

    @Test("The email stage replaces the copy and never offers account creation")
    func emailCopy() {
        for source in [LoginSource.settings, .paywall, .transcribe, .reauth] {
            var model = LoginSheetModel(source: source)
            model.showEmailForm()
            #expect(model.title == "Sign in with email")
            #expect(model.subtitle == "Use the email you signed up with")
            #expect(!model.subtitle.lowercased().contains("create"))
        }
    }

    // MARK: - Stages

    @Test("Apple stage: one primary and the Other ways link")
    func appleStage() {
        let model = LoginSheetModel(source: .settings)
        #expect(model.stage == .apple)
        #expect(model.showsOtherWaysLink)
        #expect(!model.showsAlternatives)
        #expect(!model.showsEmailForm)
    }

    @Test("More stage: the link gives way to the secondary buttons")
    func moreStage() {
        var model = LoginSheetModel(source: .settings)
        model.showMoreWays()
        #expect(model.stage == .more)
        #expect(!model.showsOtherWaysLink)
        #expect(model.showsAlternatives)
        #expect(!model.showsEmailForm)
        #expect(model.title == "Sign In & Sync")
    }

    @Test("Email stage and back via Other ways")
    func emailStage() {
        var model = LoginSheetModel(source: .transcribe)
        model.showEmailForm()
        #expect(model.stage == .email)
        #expect(model.showsEmailForm)
        #expect(!model.showsOtherWaysLink)
        #expect(!model.showsAlternatives)
        model.showMoreWays()
        #expect(model.stage == .more)
        #expect(model.title == "Sign in to transcribe")
    }

    // MARK: - Provider ordering

    @Test("Non-reauth sources lead with Apple whatever was stored")
    func nonReauthLeadsWithApple() {
        for source in [LoginSource.settings, .paywall, .transcribe] {
            let model = LoginSheetModel(source: source, lastProvider: .google)
            #expect(model.primaryProvider == .apple)
            #expect(model.alternativeProviders == [.google, .email])
        }
    }

    @Test("Reauth leads with each stored provider; the others follow in fixed order")
    func reauthOrdering() {
        let cases: [(LoginProvider, [LoginProvider])] = [
            (.apple, [.google, .email]),
            (.google, [.apple, .email]),
            (.email, [.apple, .google]),
        ]
        for (last, rest) in cases {
            let model = LoginSheetModel(source: .reauth, lastProvider: last)
            #expect(model.primaryProvider == last)
            #expect(model.alternativeProviders == rest)
        }
    }

    @Test("Reauth with nothing stored is Apple-first")
    func reauthWithoutStoredProvider() {
        let model = LoginSheetModel(source: .reauth, lastProvider: nil)
        #expect(model.primaryProvider == .apple)
        #expect(model.alternativeProviders == [.google, .email])
    }

    @Test("Button titles")
    func buttonTitles() {
        #expect(LoginProvider.apple.buttonTitle == "Continue with Apple")
        #expect(LoginProvider.google.buttonTitle == "Continue with Google")
        #expect(LoginProvider.email.buttonTitle == "Continue with Email")
    }

    // MARK: - Last sign-in provider

    private func freshStore() -> LastSignInProviderStore {
        let suite = "LoginSheetModelTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return LastSignInProviderStore(defaults: defaults)
    }

    @Test("Nothing stored loads nil; each provider round-trips as its Firebase id")
    func storeRoundTrip() {
        let store = freshStore()
        #expect(store.load() == nil)
        for provider in LoginProvider.allCases {
            store.record(provider)
            #expect(store.load() == provider)
            #expect(store.defaults.string(forKey: "anycast.lastSignInProvider") == provider.rawValue)
        }
        #expect(LoginProvider.apple.rawValue == "apple.com")
        #expect(LoginProvider.google.rawValue == "google.com")
        #expect(LoginProvider.email.rawValue == "password")
    }

    @Test("An unknown stored value loads nil")
    func storeIgnoresUnknownValue() {
        let store = freshStore()
        store.defaults.set("facebook.com", forKey: LastSignInProviderStore.key)
        #expect(store.load() == nil)
    }

    // MARK: - Forgot password

    @Test("A valid-looking email is trimmed and accepted")
    func resetEmailAccepted() {
        #expect(LoginSheetModel.resetEmail(from: "a@b.co") == "a@b.co")
        #expect(LoginSheetModel.resetEmail(from: "  me@example.com \n") == "me@example.com")
        #expect(LoginSheetModel.resetEmail(from: "first.last+tag@mail.example.org") == "first.last+tag@mail.example.org")
    }

    @Test("Empty, malformed or spaced emails are rejected")
    func resetEmailRejected() {
        let bad = ["", "   ", "plain", "a@", "@b.co", "a@b", "a@b.", "a@.co", "a@@b.co", "a b@c.co", "a@b .co"]
        for raw in bad {
            #expect(LoginSheetModel.resetEmail(from: raw) == nil, "\(raw) should be rejected")
        }
    }

    @Test("Reset messages")
    func resetMessages() {
        #expect(LoginSheetModel.resetSentMessage == "Check your inbox for a reset link")
        #expect(LoginSheetModel.resetNeedsEmailMessage == "Enter your email above first")
    }
}
