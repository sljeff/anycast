import Foundation
import AnycastKit

/// The one statement of what Plus is, reused by the paywall, its details
/// sheet, the Settings plate, the Membership plate and the transcript
/// prompts. Every line is backed by something the app actually does:
/// the transcript pool sizes are the ones the usage meter and the quota
/// clamps use, the translation list is `SettingsCodec.targetLanguages`, and
/// the account line is how entitlements are bound (`appUserID` = account id).
/// Nothing here promises a price, a trial length or a feature the client
/// cannot deliver; prices come from the store at runtime.
nonisolated enum PlusOffer {

    enum Icon: Equatable, Sendable {
        case transcripts, subtitles, account
    }

    struct Benefit: Equatable, Sendable {
        let icon: Icon
        let title: String
        let detail: String
    }

    static var freeTotal: Int { AccountPageModel.freeTotal }
    static var plusTotal: Int { AccountPageModel.plusTotal }
    static var languageCount: Int { SettingsCodec.targetLanguages.count }

    static let name = "Anycast Plus"
    static let headline = "Understand any podcast, in any language"

    /// "50 AI transcripts a month", the headline benefit.
    static var transcriptsLine: String { "\(plusTotal) AI transcripts a month" }

    /// One line for tight places: the plates and the paywall's feature line.
    static var shortLine: String { "\(transcriptsLine) · bilingual subtitles" }

    /// What a signed-out visitor gets for signing in.
    static var freePitch: String { "\(freeTotal) free AI transcripts" }

    /// The benefits, listener's side first. Details stay short enough for one line.
    static func benefits() -> [Benefit] {
        [
            Benefit(icon: .transcripts, title: transcriptsLine,
                    detail: "Free accounts get \(freeTotal) in total"),
            Benefit(icon: .subtitles, title: "Bilingual subtitles",
                    detail: "Read along in \(languageCount) languages"),
            Benefit(icon: .account, title: "Follows your account",
                    detail: "Sign in on any device to use Plus"),
        ]
    }

    /// Settings Plus plate subtitle for a non-member. A free account with
    /// nothing left says so; everyone else sees the offer.
    static func plateSubtitle(remaining: Int?, signedIn: Bool) -> String {
        if signedIn, let remaining, remaining <= 0 {
            return "You've used all \(freeTotal) free transcripts"
        }
        return transcriptsLine
    }
}
