import Foundation

/// Pure model for the standalone paywall (variants A and C): which copy each
/// variant shows, the plan rows and their badge, trial-aware CTA and
/// disclosure lines, the demo card's language chips, and the quota check that
/// decides when variant C opens. Every price is derived from the
/// `Plan` values RevenueCat returned at runtime (nothing is hard-coded), and
/// the math uses `Decimal`. UI-free so AnycastAppTests/Auth/PaywallModelTests
/// assert against data, not UIKit.
nonisolated struct PaywallModel: Equatable, Sendable {

    // MARK: - Types

    /// A: the default entry (Settings, Membership). C: shown at the quota
    /// limit with the episode the user just tried as the hero.
    enum Variant: Equatable, Sendable {
        case standard
        case quota(Episode)
    }

    /// The episode variant C is about.
    struct Episode: Equatable, Sendable {
        let title: String
        let showName: String
        let durationMilliseconds: Int64?
        let artworkURL: URL?

        /// "show · 48 min"; either part is dropped when unknown.
        var metaLine: String {
            var parts: [String] = []
            let show = showName.trimmingCharacters(in: .whitespacesAndNewlines)
            if !show.isEmpty { parts.append(show) }
            if let text = PaywallModel.durationText(milliseconds: durationMilliseconds) {
                parts.append(text)
            }
            return parts.joined(separator: " · ")
        }
    }

    enum Period: Equatable, Sendable {
        case yearly, monthly
    }

    /// One purchasable product, as RevenueCat reports it.
    struct Plan: Equatable, Sendable {
        let productID: String
        let period: Period
        /// `StoreProduct.price`.
        let price: Decimal
        let currencyCode: String
        /// The locale of the product's price formatter; derived amounts
        /// (annual ÷ 12, per transcript) are formatted with it.
        let localeIdentifier: String
        /// `StoreProduct.localizedPriceString`, e.g. "$23.99".
        let priceString: String
    }

    /// The fetched offering: the plans that exist and whether the user may
    /// still start the yearly plan's free trial. Unknown or failed
    /// eligibility is `false`.
    struct Plans: Equatable, Sendable {
        var yearly: Plan?
        var monthly: Plan?
        var yearlyTrialEligible: Bool

        var isEmpty: Bool { yearly == nil && monthly == nil }

        func plan(for period: Period) -> Plan? {
            period == .yearly ? yearly : monthly
        }
    }

    enum Availability: Equatable, Sendable {
        case loading
        /// Offerings failed, RevenueCat is unconfigured, or no plan exists.
        case unavailable
        case ready(Plans)
    }

    struct PlanRow: Equatable, Sendable {
        let period: Period
        let title: String
        /// "Save 33%"; yearly only.
        let badge: String?
        let subtitle: String
        let price: String
        let isSelected: Bool
    }

    struct Feature: Equatable, Sendable {
        enum Icon: Equatable, Sendable {
            case subtitles, transcripts, ask, export
        }
        let icon: Icon
        let title: String
        let subtitle: String
    }

    struct TimelineStep: Equatable, Sendable {
        let title: String
        let subtitle: String
        /// The first step is filled; the later ones are rings.
        let isCurrent: Bool
    }

    struct Figure: Equatable, Sendable {
        let value: String
        let caption: String
    }

    // MARK: - State

    let variant: Variant
    private(set) var availability: Availability = .loading
    private(set) var selected: Period = .yearly

    init(variant: Variant) {
        self.variant = variant
    }

    /// Stores the fetched plans. Yearly stays the default; with no yearly
    /// plan, monthly is the one left to choose. An empty offering reads as
    /// unavailable.
    mutating func setPlans(_ plans: Plans) {
        guard !plans.isEmpty else {
            availability = .unavailable
            return
        }
        availability = .ready(plans)
        if plans.plan(for: selected) == nil {
            selected = plans.yearly != nil ? .yearly : .monthly
        }
    }

    mutating func setLoading() { availability = .loading }
    mutating func setUnavailable() { availability = .unavailable }

    /// Ignored when that plan does not exist.
    mutating func select(_ period: Period) {
        guard plans?.plan(for: period) != nil else { return }
        selected = period
    }

    var plans: Plans? {
        if case .ready(let plans) = availability { return plans }
        return nil
    }

    var selectedPlan: Plan? { plans?.plan(for: selected) }

    var isQuota: Bool {
        if case .quota = variant { return true }
        return false
    }

    var episode: Episode? {
        if case .quota(let episode) = variant { return episode }
        return nil
    }

    // MARK: - Copy

    static let standardHeadline = "Understand any podcast, in any language"
    static let quotaHeadline = "Keep going with this episode"
    static let featureLine = "Bilingual subtitles · 50 AI transcripts a month"
    static let quotaContextLine = "You've used all 10 free AI transcripts"
    static let quotaPrompt = "Transcribe it now and read along in"
    static let demoMeta = "Example episode · 12:04"
    static let detailsLinkTitle = "What's in Plus"
    static let restoreTitle = "Restore"
    static let continueTitle = "Continue"
    static let trialTitle = "Start 7-day free trial"
    static let termsTitle = "Terms"
    static let privacyTitle = "Privacy"
    static let termsLongTitle = "Terms of Use"
    static let privacyLongTitle = "Privacy Policy"
    static let unavailableMessage = "Prices aren't available right now"
    static let retryTitle = "Retry"
    static let featuresLabel = "What you get"
    static let timelineLabel = "How your free week works"
    static let monthlySubtitle = "Cancel anytime"
    static let transcriptsPerMonth = 50

    var headline: String { isQuota ? Self.quotaHeadline : Self.standardHeadline }

    /// The meta line above the headline; quota only.
    var contextLine: String? { isQuota ? Self.quotaContextLine : nil }

    // MARK: - Plans

    /// Trial copy appears only when the yearly plan exists and the user is
    /// eligible.
    var trialAvailable: Bool {
        guard let plans else { return false }
        return plans.yearly != nil && plans.yearlyTrialEligible
    }

    /// The trial starts only from the Yearly plan, never as a toggle.
    var selectedStartsTrial: Bool { selected == .yearly && trialAvailable }

    /// Round-down of (1 − annual ÷ (monthly × 12)) as a whole percent; nil
    /// when either price is missing or the yearly plan saves nothing.
    var savePercent: Int? {
        guard let yearly = plans?.yearly, let monthly = plans?.monthly,
              monthly.price > 0, yearly.price > 0 else { return nil }
        let ratio = yearly.price / (monthly.price * 12)
        var percent = (1 - ratio) * 100
        var rounded = Decimal()
        NSDecimalRound(&rounded, &percent, 0, .down)
        let value = (rounded as NSDecimalNumber).intValue
        return value > 0 ? value : nil
    }

    var saveBadge: String? { savePercent.map { "Save \($0)%" } }

    /// Annual ÷ 12 in the product's currency, e.g. "$1.99".
    var yearlyPerMonth: String? {
        guard let yearly = plans?.yearly else { return nil }
        return Self.format(yearly.price / 12, in: yearly)
    }

    /// Annual ÷ 12 ÷ 50: "≈4¢" for a USD value under one dollar, otherwise
    /// the product formatter's amount ("≈€0.04").
    var perTranscript: String? {
        guard let yearly = plans?.yearly else { return nil }
        let amount = yearly.price / 12 / Decimal(Self.transcriptsPerMonth)
        if yearly.currencyCode == "USD", amount < 1 {
            var cents = amount * 100
            var rounded = Decimal()
            NSDecimalRound(&rounded, &cents, 0, .plain)
            let value = max((rounded as NSDecimalNumber).intValue, 1)
            return "≈\(value)¢"
        }
        return "≈" + Self.format(amount, in: yearly)
    }

    /// Rows in display order; empty while loading or unavailable.
    var planRows: [PlanRow] {
        guard let plans else { return [] }
        var rows: [PlanRow] = []
        if let yearly = plans.yearly {
            var subtitle = yearlyPerMonth.map { "\($0)/mo" } ?? ""
            if plans.yearlyTrialEligible {
                subtitle = subtitle.isEmpty ? "7 days free" : "7 days free · \(subtitle)"
            }
            rows.append(PlanRow(
                period: .yearly, title: "Yearly", badge: saveBadge, subtitle: subtitle,
                price: "\(yearly.priceString)/yr", isSelected: selected == .yearly
            ))
        }
        if let monthly = plans.monthly {
            rows.append(PlanRow(
                period: .monthly, title: "Monthly", badge: nil, subtitle: Self.monthlySubtitle,
                price: "\(monthly.priceString)/mo", isSelected: selected == .monthly
            ))
        }
        return rows
    }

    // MARK: - CTA and disclosure

    /// The CTA is live only with a selected plan.
    var ctaEnabled: Bool { selectedPlan != nil }

    /// A always reads "Continue"; C names the trial when it applies.
    var ctaTitle: String {
        isQuota && selectedStartsTrial ? Self.trialTitle : Self.continueTitle
    }

    /// First disclosure line; nil without a selected plan.
    var disclosure: String? {
        guard let plan = selectedPlan else { return nil }
        switch plan.period {
        case .monthly:
            return "\(plan.priceString)/mo. Cancel anytime."
        case .yearly:
            return selectedStartsTrial
                ? "7 days free, then \(plan.priceString)/yr. Cancel anytime."
                : "\(plan.priceString)/yr. Cancel anytime."
        }
    }

    // MARK: - Details sheet

    /// The four "What's in Plus" rows.
    var features: [Feature] {
        let transcripts = perTranscript.map { "50 a month, \($0) each" } ?? "50 a month"
        return [
            Feature(icon: .subtitles, title: "Bilingual subtitles", subtitle: "Any episode, 11 languages"),
            Feature(icon: .transcripts, title: "AI transcripts", subtitle: transcripts),
            Feature(icon: .ask, title: "Ask the episode", subtitle: "Answers from what was said"),
            Feature(icon: .export, title: "Export to notes", subtitle: "Lines and translations"),
        ]
    }

    /// Today / Day 5 / Day 7, only for a trial-eligible user on Yearly.
    var timeline: [TimelineStep] {
        guard selectedStartsTrial, let yearly = plans?.yearly else { return [] }
        return [
            TimelineStep(title: "Today", subtitle: "All of Plus, free", isCurrent: true),
            // The app sends no trial reminder (yet), so this step promises none.
            TimelineStep(title: "Day 5", subtitle: "Cancel anytime in your App Store subscriptions", isCurrent: false),
            TimelineStep(
                title: "Day 7",
                subtitle: "\(yearly.priceString)/yr starts. Cancel before, pay nothing.",
                isCurrent: false
            ),
        ]
    }

    // MARK: - Quota figures (C)

    /// "50 more every month" and "≈4¢ each, on Yearly"; the second is
    /// dropped when no yearly price is known.
    var figures: [Figure] {
        var figures = [Figure(value: "\(Self.transcriptsPerMonth)", caption: "more every month")]
        if let perTranscript {
            figures.append(Figure(value: perTranscript, caption: "each, on Yearly"))
        }
        return figures
    }

    // MARK: - Formatting

    /// Formats with a currency formatter built from the product's locale.
    static func format(_ amount: Decimal, in plan: Plan) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.locale = Locale(identifier: plan.localeIdentifier)
        formatter.currencyCode = plan.currencyCode
        return formatter.string(from: amount as NSDecimalNumber) ?? ""
    }

    /// "48 min", "1 h 12 min"; nil for an unknown or zero duration.
    static func durationText(milliseconds: Int64?) -> String? {
        guard let milliseconds, milliseconds > 0 else { return nil }
        let minutes = max(1, Int((Double(milliseconds) / 60_000).rounded()))
        guard minutes >= 60 else { return "\(minutes) min" }
        let hours = minutes / 60
        let rest = minutes % 60
        return rest == 0 ? "\(hours) h" : "\(hours) h \(rest) min"
    }

    // MARK: - Quota decision

    /// Variant C opens only when a re-fetched account reports no transcripts
    /// left and the user is not already Plus; any other 403 keeps its toast.
    static func shouldPresentQuotaPaywall(refreshedRemaining: Int?, isSubscribed: Bool) -> Bool {
        refreshedRemaining == 0 && !isSubscribed
    }
}

// MARK: - Demo card

nonisolated extension PaywallModel {

    /// One language chip with the demo translation of the highlighted line.
    struct Language: Equatable, Sendable {
        let code: String
        let label: String
        let translation: String
        /// The context lines around the highlighted one.
        let before: [Line]
        let after: [Line]
    }

    struct Line: Equatable, Sendable {
        let original: String
        let translation: String
    }

    static let highlightedLine = "But was it actually getting smarter?"

    /// The four chips, in display order.
    static let languages: [Language] = [
        Language(
            code: "zh", label: "中文", translation: "但它真的变得更聪明了吗？",
            before: [
                Line(original: "We kept adding data to the benchmark.", translation: "我们不断往基准测试里加数据。"),
                Line(original: "So the model kept getting better at the benchmark.", translation: "所以模型在基准测试上越来越好。"),
            ],
            after: [
                Line(original: "That is the question nobody wanted to ask.", translation: "这正是没人愿意问的问题。"),
                Line(original: "Scores went up, but the reasoning didn’t.", translation: "分数上去了，推理能力却没有。"),
            ]
        ),
        Language(
            code: "ja", label: "日本語", translation: "でも、本当に賢くなっていたのだろうか？",
            before: [
                Line(original: "We kept adding data to the benchmark.", translation: "私たちはベンチマークにデータを足し続けた。"),
                Line(original: "So the model kept getting better at the benchmark.", translation: "そのため、モデルはベンチマークでどんどん良くなった。"),
            ],
            after: [
                Line(original: "That is the question nobody wanted to ask.", translation: "それは誰も聞きたがらなかった問いだ。"),
                Line(original: "Scores went up, but the reasoning didn’t.", translation: "スコアは上がったが、推論力は変わらなかった。"),
            ]
        ),
        Language(
            code: "es", label: "Español", translation: "Pero ¿de verdad se estaba volviendo más inteligente?",
            before: [
                Line(original: "We kept adding data to the benchmark.", translation: "Seguimos añadiendo datos al benchmark."),
                Line(original: "So the model kept getting better at the benchmark.", translation: "Así que el modelo seguía mejorando en el benchmark."),
            ],
            after: [
                Line(original: "That is the question nobody wanted to ask.", translation: "Esa es la pregunta que nadie quiso hacer."),
                Line(original: "Scores went up, but the reasoning didn’t.", translation: "Las puntuaciones subieron, pero el razonamiento no."),
            ]
        ),
        Language(
            code: "fr", label: "Français", translation: "Mais devenait-il vraiment plus intelligent ?",
            before: [
                Line(original: "We kept adding data to the benchmark.", translation: "Nous n’arrêtions pas d’ajouter des données au benchmark."),
                Line(original: "So the model kept getting better at the benchmark.", translation: "Alors le modèle ne cessait de s’améliorer sur le benchmark."),
            ],
            after: [
                Line(original: "That is the question nobody wanted to ask.", translation: "C’est la question que personne ne voulait poser."),
                Line(original: "Scores went up, but the reasoning didn’t.", translation: "Les scores ont grimpé, mais pas le raisonnement."),
            ]
        ),
    ]

    /// Index of the chip to preselect for variant C: the Settings target
    /// language when set and offered, else the device language mapped to a
    /// chip, else the first chip. Codes compare on their language subtag
    /// ("zh-Hans-CN" and "zh_TW" both map to "zh").
    static func preselectedLanguageIndex(settingsTarget: String?, deviceLanguage: String?) -> Int {
        for candidate in [settingsTarget, deviceLanguage] {
            guard let code = languageSubtag(candidate),
                  let index = languages.firstIndex(where: { $0.code == code }) else { continue }
            return index
        }
        return 0
    }

    private static func languageSubtag(_ identifier: String?) -> String? {
        guard let identifier else { return nil }
        let first = identifier.split(whereSeparator: { $0 == "-" || $0 == "_" }).first
        return first.map { String($0).lowercased() }
    }

    /// The demo card's selection. Variant A cycles the chips every 3 s until
    /// the user taps one; C never cycles.
    struct Demo: Equatable, Sendable {
        static let cycleInterval: TimeInterval = 3

        let cycles: Bool
        private(set) var index: Int
        private(set) var isPinned = false

        init(cycles: Bool, index: Int = 0) {
            self.cycles = cycles
            self.index = index
        }

        var language: Language { PaywallModel.languages[index] }

        /// Advances to the next chip; no-op for C or once a chip was tapped.
        mutating func tick() {
            guard cycles, !isPinned else { return }
            index = (index + 1) % PaywallModel.languages.count
        }

        /// A tap pins the choice for good.
        mutating func pick(_ newIndex: Int) {
            guard PaywallModel.languages.indices.contains(newIndex) else { return }
            index = newIndex
            isPinned = true
        }
    }
}
