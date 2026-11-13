import Testing
@testable import Anycast

/// The shared Plus statement: every number comes from the quota constants or
/// the translation list, never from a literal in copy.
struct PlusOfferTests {

    @Test("Numbers come from the app's own constants")
    func numbers() {
        #expect(PlusOffer.freeTotal == AccountPageModel.freeTotal)
        #expect(PlusOffer.plusTotal == AccountPageModel.plusTotal)
        #expect(PlusOffer.languageCount == 11)
        #expect(PlusOffer.transcriptsLine == "50 AI transcripts a month")
        #expect(PlusOffer.shortLine == "50 AI transcripts a month · bilingual subtitles")
        #expect(PlusOffer.freePitch == "10 free AI transcripts")
    }

    @Test("Three listener-side benefits, none of which promise a price or a trial")
    func benefits() {
        let benefits = PlusOffer.benefits()
        #expect(benefits.map(\.icon) == [.transcripts, .subtitles, .account])
        #expect(benefits.map(\.title) == [
            "50 AI transcripts a month", "Bilingual subtitles", "Follows your account",
        ])
        for benefit in benefits {
            #expect(!benefit.title.contains("$"))
            #expect(!benefit.detail.lowercased().contains("trial"))
        }
        #expect(PlusOffer.benefits()[0].detail == "Free accounts get 10 in total")
    }

    @Test("Plate line: the offer, or the plain fact that the free pool is gone")
    func plateSubtitle() {
        #expect(PlusOffer.plateSubtitle(remaining: nil, signedIn: false) == "50 AI transcripts a month")
        #expect(PlusOffer.plateSubtitle(remaining: 0, signedIn: false) == "50 AI transcripts a month")
        #expect(PlusOffer.plateSubtitle(remaining: 3, signedIn: true) == "50 AI transcripts a month")
        #expect(PlusOffer.plateSubtitle(remaining: 0, signedIn: true) == "You've used all 10 free transcripts")
    }

    @Test("Paywall copy that depends on store outcomes")
    func paywallStates() {
        #expect(PaywallModel.loadingMessage == "Loading prices")
        #expect(PaywallModel.unavailableMessage == "Prices aren't available right now")
        #expect(PaywallModel.retryTitle == "Retry")
        #expect(PaywallModel.welcomeToast == "Plus is on · 50 AI transcripts a month")
        var model = PaywallModel(variant: .standard)
        #expect(model.availability == .loading)
        #expect(model.planRows.isEmpty)
        #expect(!model.ctaEnabled)
        model.setUnavailable()
        #expect(model.availability == .unavailable)
        #expect(!model.ctaEnabled)
        #expect(model.disclosure == nil)
    }
}
