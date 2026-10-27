import Foundation
import Testing
@testable import Anycast

/// Pure paywall logic: plan rows, the Save badge, the trial-aware CTA and
/// disclosure, per-transcript pricing in USD and other currencies, variant
/// copy, the demo card, language preselection and the quota decision.
@MainActor
struct PaywallModelTests {

    // MARK: - Fixtures

    private static func usdPlans(
        yearly: Decimal? = Decimal(string: "23.99"),
        monthly: Decimal? = Decimal(string: "2.99"),
        trial: Bool = true
    ) -> PaywallModel.Plans {
        PaywallModel.Plans(
            yearly: yearly.map {
                PaywallModel.Plan(
                    productID: "anycast_annual", period: .yearly, price: $0, currencyCode: "USD",
                    localeIdentifier: "en_US", priceString: "$\($0)"
                )
            },
            monthly: monthly.map {
                PaywallModel.Plan(
                    productID: "anycast_monthly", period: .monthly, price: $0, currencyCode: "USD",
                    localeIdentifier: "en_US", priceString: "$\($0)"
                )
            },
            yearlyTrialEligible: trial
        )
    }

    private static func euroPlans() -> PaywallModel.Plans {
        PaywallModel.Plans(
            yearly: PaywallModel.Plan(
                productID: "anycast_annual", period: .yearly, price: Decimal(string: "24.99")!,
                currencyCode: "EUR", localeIdentifier: "en_IE", priceString: "€24.99"
            ),
            monthly: PaywallModel.Plan(
                productID: "anycast_monthly", period: .monthly, price: Decimal(string: "2.99")!,
                currencyCode: "EUR", localeIdentifier: "en_IE", priceString: "€2.99"
            ),
            yearlyTrialEligible: false
        )
    }

    private static func ready(
        _ plans: PaywallModel.Plans, variant: PaywallModel.Variant = .standard
    ) -> PaywallModel {
        var model = PaywallModel(variant: variant)
        model.setPlans(plans)
        return model
    }

    private static let episode = PaywallModel.Episode(
        title: "The benchmark problem", showName: "Hard Fork",
        durationMilliseconds: 48 * 60_000, artworkURL: nil
    )

    // MARK: - Save badge

    @Test("Save percent rounds down from annual against twelve months")
    func savePercent() {
        // 1 - 23.99 / (2.99 * 12) = 33.14 %
        #expect(Self.ready(Self.usdPlans()).savePercent == 33)
        #expect(Self.ready(Self.usdPlans()).saveBadge == "Save 33%")
        // 1 - 20 / 24 = 16.67 % rounds down, not to 17.
        let plans = Self.usdPlans(yearly: 20, monthly: 2)
        #expect(Self.ready(plans).savePercent == 16)
    }

    @Test("Save badge is hidden when monthly is missing or yearly saves nothing")
    func saveBadgeHidden() {
        #expect(Self.ready(Self.usdPlans(monthly: nil)).saveBadge == nil)
        #expect(Self.ready(Self.usdPlans(yearly: 35.88, monthly: 2.99)).saveBadge == nil)
        #expect(Self.ready(Self.usdPlans(yearly: 40, monthly: 2.99)).saveBadge == nil)
        #expect(Self.ready(Self.usdPlans(yearly: nil)).saveBadge == nil)
    }

    // MARK: - Derived prices

    @Test("USD under a dollar renders cents per transcript")
    func perTranscriptUSD() {
        // 23.99 / 12 / 50 = $0.0400
        #expect(Self.ready(Self.usdPlans()).perTranscript == "≈4¢")
        // 29.99 / 12 / 50 = $0.04998 rounds to 5¢.
        #expect(Self.ready(Self.usdPlans(yearly: Decimal(string: "29.99"))).perTranscript == "≈5¢")
        // Never "≈0¢".
        #expect(Self.ready(Self.usdPlans(yearly: 1)).perTranscript == "≈1¢")
    }

    @Test("A non-USD currency uses the product's formatter")
    func perTranscriptEuro() {
        let model = Self.ready(Self.euroPlans())
        // 24.99 / 12 / 50 = 0.04165
        #expect(model.perTranscript == "≈€0.04")
        // 24.99 / 12 = 2.0825
        #expect(model.yearlyPerMonth == "€2.08")
    }

    @Test("USD at a dollar or more uses the formatter instead of cents")
    func perTranscriptLargeUSD() {
        // 1200 / 12 / 50 = $2.00
        #expect(Self.ready(Self.usdPlans(yearly: 1200)).perTranscript == "≈$2.00")
    }

    @Test("Yearly per month is annual divided by twelve")
    func yearlyPerMonth() {
        // 23.99 / 12 = 1.9991
        #expect(Self.ready(Self.usdPlans()).yearlyPerMonth == "$2.00")
        #expect(Self.ready(Self.usdPlans(yearly: nil)).yearlyPerMonth == nil)
        #expect(Self.ready(Self.usdPlans(yearly: nil)).perTranscript == nil)
    }

    // MARK: - Plan rows

    @Test("Trial-eligible yearly row: badge, free-week subtitle, full price")
    func rowsEligible() {
        let rows = Self.ready(Self.usdPlans()).planRows
        #expect(rows.count == 2)
        #expect(rows[0] == PaywallModel.PlanRow(
            period: .yearly, title: "Yearly", badge: "Save 33%",
            subtitle: "7 days free · $2.00/mo", price: "$23.99/yr", isSelected: true
        ))
        #expect(rows[1] == PaywallModel.PlanRow(
            period: .monthly, title: "Monthly", badge: nil,
            subtitle: "Cancel anytime", price: "$2.99/mo", isSelected: false
        ))
    }

    @Test("Ineligible yearly row shows only the monthly equivalent")
    func rowsIneligible() {
        let rows = Self.ready(Self.usdPlans(trial: false)).planRows
        #expect(rows[0].subtitle == "$2.00/mo")
    }

    @Test("Yearly is preselected; selecting monthly flips the rows")
    func selection() {
        var model = Self.ready(Self.usdPlans())
        #expect(model.selected == .yearly)
        model.select(.monthly)
        #expect(model.planRows.map(\.isSelected) == [false, true])
    }

    @Test("A missing plan cannot be selected and the other becomes the default")
    func missingPlan() {
        var model = Self.ready(Self.usdPlans(monthly: nil))
        model.select(.monthly)
        #expect(model.selected == .yearly)

        let monthlyOnly = Self.ready(Self.usdPlans(yearly: nil))
        #expect(monthlyOnly.selected == .monthly)
        #expect(monthlyOnly.planRows.count == 1)
        // A trial needs the yearly plan.
        #expect(monthlyOnly.trialAvailable == false)
    }

    // MARK: - CTA and disclosure

    @Test("A names no trial; C names it only for an eligible yearly selection")
    func ctaTitles() {
        var standard = Self.ready(Self.usdPlans())
        #expect(standard.ctaTitle == "Continue")
        standard.select(.monthly)
        #expect(standard.ctaTitle == "Continue")

        var quota = Self.ready(Self.usdPlans(), variant: .quota(Self.episode))
        #expect(quota.ctaTitle == "Start 7-day free trial")
        quota.select(.monthly)
        #expect(quota.ctaTitle == "Continue")
        #expect(Self.ready(Self.usdPlans(trial: false), variant: .quota(Self.episode)).ctaTitle == "Continue")
    }

    @Test("Disclosure follows the selected plan and trial eligibility")
    func disclosure() {
        var model = Self.ready(Self.usdPlans())
        #expect(model.disclosure == "7 days free, then $23.99/yr. Cancel anytime.")
        model.select(.monthly)
        #expect(model.disclosure == "$2.99/mo. Cancel anytime.")

        let noTrial = Self.ready(Self.usdPlans(trial: false))
        #expect(noTrial.disclosure == "$23.99/yr. Cancel anytime.")
    }

    @Test("Unknown eligibility reads as not eligible: no trial anywhere")
    func ineligibleHidesTrial() {
        let model = Self.ready(Self.usdPlans(trial: false))
        #expect(model.trialAvailable == false)
        #expect(model.selectedStartsTrial == false)
        #expect(model.timeline.isEmpty)
    }

    @Test("Loading and unavailable have no rows, no disclosure, a disabled CTA")
    func notReady() {
        var model = PaywallModel(variant: .standard)
        #expect(model.availability == .loading)
        #expect(model.planRows.isEmpty)
        #expect(model.disclosure == nil)
        #expect(!model.ctaEnabled)
        model.setUnavailable()
        #expect(model.availability == .unavailable)
        #expect(model.selectedPlan == nil)
        #expect(!model.ctaEnabled)
        #expect(model.figures.count == 1)
        // An offering without plans is also unavailable.
        model.setPlans(PaywallModel.Plans(yearly: nil, monthly: nil, yearlyTrialEligible: true))
        #expect(model.availability == .unavailable)
    }

    // MARK: - Details sheet

    @Test("Timeline appears for an eligible yearly selection only")
    func timeline() {
        var model = Self.ready(Self.usdPlans())
        #expect(model.timeline.map(\.title) == ["Today", "Day 5", "Day 7"])
        #expect(model.timeline.map(\.isCurrent) == [true, false, false])
        #expect(model.timeline[2].subtitle == "$23.99/yr starts. Cancel before, pay nothing.")
        model.select(.monthly)
        #expect(model.timeline.isEmpty)
    }

    @Test("Four feature rows; transcripts quote the per-transcript price")
    func features() {
        let features = Self.ready(Self.usdPlans()).features
        #expect(features.map(\.title) == [
            "Bilingual subtitles", "AI transcripts", "Ask the episode", "Export to notes",
        ])
        #expect(features[1].subtitle == "50 a month, ≈4¢ each")
        #expect(PaywallModel(variant: .standard).features[1].subtitle == "50 a month")
    }

    // MARK: - Variant copy

    @Test("A and C copy")
    func variantCopy() {
        let standard = PaywallModel(variant: .standard)
        #expect(standard.headline == "Understand any podcast, in any language")
        #expect(standard.contextLine == nil)
        #expect(PaywallModel.featureLine == "Bilingual subtitles · 50 AI transcripts a month")

        let quota = PaywallModel(variant: .quota(Self.episode))
        #expect(quota.headline == "Keep going with this episode")
        #expect(quota.contextLine == "You've used all 10 free AI transcripts")
        #expect(quota.isQuota)
        #expect(quota.episode == Self.episode)
    }

    @Test("Quota figures are 50 and the per-transcript price")
    func figures() {
        let figures = Self.ready(Self.usdPlans(), variant: .quota(Self.episode)).figures
        #expect(figures == [
            PaywallModel.Figure(value: "50", caption: "more every month"),
            PaywallModel.Figure(value: "≈4¢", caption: "each, on Yearly"),
        ])
    }

    @Test("Episode meta line: show and rounded duration, either dropped when unknown")
    func episodeMeta() {
        #expect(Self.episode.metaLine == "Hard Fork · 48 min")
        let long = PaywallModel.Episode(
            title: "t", showName: "S", durationMilliseconds: 72 * 60_000, artworkURL: nil
        )
        #expect(long.metaLine == "S · 1 h 12 min")
        let hour = PaywallModel.Episode(
            title: "t", showName: "S", durationMilliseconds: 60 * 60_000, artworkURL: nil
        )
        #expect(hour.metaLine == "S · 1 h")
        let unknown = PaywallModel.Episode(title: "t", showName: "S", durationMilliseconds: nil, artworkURL: nil)
        #expect(unknown.metaLine == "S")
        let noShow = PaywallModel.Episode(title: "t", showName: " ", durationMilliseconds: 30_000, artworkURL: nil)
        #expect(noShow.metaLine == "1 min")
    }

    // MARK: - Demo card

    @Test("Four chips in board order")
    func chips() {
        #expect(PaywallModel.languages.map(\.label) == ["中文", "日本語", "Español", "Français"])
        #expect(PaywallModel.languages.allSatisfy { $0.before.count == 2 && $0.after.count == 2 })
    }

    @Test("Variant A cycles through the chips and wraps")
    func demoCycles() {
        var demo = PaywallModel.Demo(cycles: true)
        #expect(demo.index == 0)
        demo.tick(); demo.tick(); demo.tick()
        #expect(demo.index == 3)
        demo.tick()
        #expect(demo.index == 0)
        #expect(PaywallModel.Demo.cycleInterval == 3)
    }

    @Test("A tapped chip stops cycling for good")
    func demoPins() {
        var demo = PaywallModel.Demo(cycles: true)
        demo.pick(2)
        #expect(demo.isPinned)
        demo.tick()
        #expect(demo.index == 2)
        demo.pick(99)
        #expect(demo.index == 2)
    }

    @Test("Variant C never cycles")
    func demoStaticForQuota() {
        var demo = PaywallModel.Demo(cycles: false, index: 1)
        demo.tick()
        #expect(demo.index == 1)
    }

    // MARK: - Language preselection

    @Test("Settings target language wins, then the device language, then the first chip")
    func preselection() {
        func index(_ target: String?, _ device: String?) -> Int {
            PaywallModel.preselectedLanguageIndex(settingsTarget: target, deviceLanguage: device)
        }
        #expect(index("es", "ja-JP") == 2)
        #expect(index("", "ja-JP") == 1)
        #expect(index(nil, "zh-Hans-CN") == 0)
        #expect(index("", "fr_FR") == 3)
        // A target the chips do not offer falls through to the device language.
        #expect(index("de", "fr-FR") == 3)
        #expect(index("de", "en-US") == 0)
        #expect(index(nil, nil) == 0)
    }

    // MARK: - Quota decision

    @Test("Quota paywall opens only at zero remaining for a non-subscriber")
    func quotaDecision() {
        #expect(PaywallModel.shouldPresentQuotaPaywall(refreshedRemaining: 0, isSubscribed: false))
        #expect(!PaywallModel.shouldPresentQuotaPaywall(refreshedRemaining: 0, isSubscribed: true))
        #expect(!PaywallModel.shouldPresentQuotaPaywall(refreshedRemaining: 3, isSubscribed: false))
        // The re-fetch failed or signed out: keep the toast.
        #expect(!PaywallModel.shouldPresentQuotaPaywall(refreshedRemaining: nil, isSubscribed: false))
    }
}
