import Foundation

/// Open choices from the detail transcript-status proposal. `current` is
/// what the app ships; tests pass another value to pin a branch. Flip a
/// field here to change the behavior — call sites read `current`.
nonisolated struct DetailTranscriptPolicy: Equatable, Sendable {
    /// Plus accounts see a remaining count only at or below this value.
    var plusCountVisibilityMaximum: Int
    /// Ask AI is offered only once a transcript exists. When false, the
    /// overflow menu also lists Ask AI earlier; choosing it runs Generate.
    var askAIOnlyWhenReady: Bool
    /// Opening a ready transcript for an episode that is not current loads
    /// it at the saved position without starting playback. `true` starts
    /// playback the way Play does.
    var autoplayWhenOpeningTranscript: Bool
    /// "Get Plus" opens the quota paywall directly. `false` sends a generate
    /// request and waits for the refusal.
    var openPaywallWithoutProbe: Bool
    /// The status row is part of the medium detent. `false` shows it only
    /// at the large detent.
    var visibleAtMediumDetent: Bool
    /// Inbox card long-press does not gain the detail sheet's transcript
    /// entries. `true` prepends the same menu.
    var includeInboxContextMenu: Bool
    /// How long a `GET /api/user` remaining value may be reused.
    var allowanceFreshness: TimeInterval

    static let current = DetailTranscriptPolicy(
        plusCountVisibilityMaximum: 5,
        askAIOnlyWhenReady: true,
        autoplayWhenOpeningTranscript: false,
        openPaywallWithoutProbe: true,
        visibleAtMediumDetent: true,
        includeInboxContextMenu: false,
        allowanceFreshness: 60
    )
}

/// What a tap on the status row, its trailing word, or the ••• menu does.
nonisolated enum DetailTranscriptAction: Equatable, Sendable {
    case generate
    case read
    case askAI
    case getPlus
}

/// One ••• entry derived from the same state as the row.
nonisolated struct DetailTranscriptMenuItem: Equatable, Sendable {
    var title: String
    var subtitle: String?
    var action: DetailTranscriptAction
}

/// A fresh `GET /api/user` reading plus whether that account is Plus.
/// Staleness lives in the cache; the reducer treats a nil allowance as
/// "count unknown" and draws no number.
nonisolated struct TranscriptAllowance: Equatable, Sendable {
    var remaining: Int
    var isSubscribed: Bool
}

/// The status row's whole presentation: copy, accessibility, symbol, and
/// the ••• entries. Pure — the view only paints it.
nonisolated struct DetailTranscriptContent: Equatable, Sendable {

    enum Kind: Equatable, Sendable {
        case signedOut
        case available
        case plus
        case exhausted
        /// Plus, nothing left until the monthly pool refills.
        case plusExhausted
        case generating
        case ready
        case failed
        case unknown
    }

    enum Symbol: Equatable, Sendable {
        case sparkle
        case lines
        case warning
        case spinner
    }

    var kind: Kind
    var title: String
    /// Trailing count, such as "7 left". Nil draws nothing — never an ellipsis.
    var value: String?
    /// Trailing gold word. Nil on the generating row.
    var actionTitle: String?
    /// Nil when the row is not a button (generating).
    var rowAction: DetailTranscriptAction?
    /// Nil when there is no trailing word.
    var trailingAction: DetailTranscriptAction?
    var accessibilityLabel: String
    var accessibilityHint: String
    var symbol: Symbol
    /// "Get Plus" under Increase Contrast: onSurface + underline.
    var trailingUpgradesContrast: Bool
    var menu: [DetailTranscriptMenuItem]
    /// The player's transcript-page capsule says the same thing in one line
    /// (message, then `actionTitle` as its trailing word).
    var promptMessage: String = "AI transcript"

    /// VoiceOver custom actions for targets that are not the row's own
    /// double-tap (Ask AI on a ready transcript).
    var accessibilityCustomActions: [DetailTranscriptAction] {
        var seen: [DetailTranscriptAction] = []
        for item in menu where item.action != rowAction && !seen.contains(item.action) {
            seen.append(item.action)
        }
        return seen
    }
}

/// signed-in / Plus / remaining / subtitle status → the eight row states.
/// Status wins over the account: a transcript that is generating, ready,
/// or failed does not also talk about quota.
nonisolated enum DetailTranscriptState {

    static func reduce(
        status: String?,
        signedIn: Bool,
        allowance: TranscriptAllowance?,
        policy: DetailTranscriptPolicy = .current
    ) -> DetailTranscriptContent {
        switch status {
        case "processing":
            return generating()
        case "succeeded":
            return ready()
        case "failed":
            return failed(policy: policy)
        case .some:
            // Unknown server strings land on the failed panel, matching the
            // transcript page. nil (never requested) falls through.
            return failed(policy: policy)
        case nil:
            break
        }
        guard signedIn else { return signedOut(policy: policy) }
        guard let allowance else { return unknown(policy: policy) }
        if allowance.isSubscribed {
            return plus(allowance.remaining, policy: policy)
        }
        let left = clamp(allowance.remaining, subscribed: false)
        if left == 0 { return exhausted(policy: policy) }
        return available(left: left, policy: policy)
    }

    // MARK: - States

    private static func signedOut(policy: DetailTranscriptPolicy) -> DetailTranscriptContent {
        var content = accountRow(
            kind: .signedOut,
            value: "\(PlusOffer.freeTotal) free",
            actionTitle: "Sign In",
            action: .generate,
            accessibilityLabel: "AI transcript, \(PlusOffer.freeTotal) free with an account",
            accessibilityHint: "Double-tap to sign in and generate",
            menuSubtitle: "Sign in for \(PlusOffer.freeTotal) free",
            policy: policy
        )
        content.promptMessage = PlusOffer.freePitch
        return content
    }

    private static func available(left: Int, policy: DetailTranscriptPolicy) -> DetailTranscriptContent {
        var content = accountRow(
            kind: .available,
            value: "\(left) of \(PlusOffer.freeTotal) left",
            actionTitle: "Generate",
            action: .generate,
            accessibilityLabel: "AI transcript, \(left) of \(PlusOffer.freeTotal) free left",
            accessibilityHint: "Double-tap to generate",
            menuSubtitle: "\(left) of \(PlusOffer.freeTotal) free left",
            policy: policy
        )
        content.promptMessage = "\(left) of \(PlusOffer.freeTotal) free transcripts left"
        return content
    }

    private static func plus(_ remaining: Int, policy: DetailTranscriptPolicy) -> DetailTranscriptContent {
        let left = clamp(remaining, subscribed: true)
        if left == 0 { return plusExhausted() }
        let showsCount = left <= policy.plusCountVisibilityMaximum
        var content = accountRow(
            kind: .plus,
            value: showsCount ? "\(left) left this month" : nil,
            actionTitle: "Generate",
            action: .generate,
            accessibilityLabel: showsCount
                ? "AI transcript, \(left) left this month"
                : "AI transcript",
            accessibilityHint: "Double-tap to generate",
            menuSubtitle: showsCount ? "\(left) left this month" : nil,
            policy: policy
        )
        if showsCount { content.promptMessage = "\(left) transcripts left this month" }
        return content
    }

    /// A member out of transcripts is not sold Plus again and is not handed
    /// a Generate that the server would refuse: the row just says so.
    private static func plusExhausted() -> DetailTranscriptContent {
        DetailTranscriptContent(
            kind: .plusExhausted,
            title: "AI transcript",
            value: "None left this month",
            actionTitle: nil,
            rowAction: nil,
            trailingAction: nil,
            accessibilityLabel: "AI transcript, none left this month",
            accessibilityHint: "",
            symbol: .sparkle,
            trailingUpgradesContrast: false,
            menu: [],
            promptMessage: "No transcripts left this month"
        )
    }

    private static func exhausted(policy: DetailTranscriptPolicy) -> DetailTranscriptContent {
        var content = accountRow(
            kind: .exhausted,
            value: "None left",
            actionTitle: "Get Plus",
            action: .getPlus,
            accessibilityLabel: "AI transcript, no free transcripts left",
            accessibilityHint: "Double-tap to see Plus",
            menuSubtitle: nil,
            policy: policy
        )
        content.trailingUpgradesContrast = true
        content.promptMessage = "No free transcripts left"
        content.menu = menu(
            primary: DetailTranscriptMenuItem(title: "Get Plus", subtitle: nil, action: .getPlus),
            policy: policy
        )
        return content
    }

    private static func unknown(policy: DetailTranscriptPolicy) -> DetailTranscriptContent {
        accountRow(
            kind: .unknown,
            value: nil,
            actionTitle: "Generate",
            action: .generate,
            accessibilityLabel: "AI transcript",
            accessibilityHint: "Double-tap to generate",
            menuSubtitle: nil,
            policy: policy
        )
    }

    private static func generating() -> DetailTranscriptContent {
        DetailTranscriptContent(
            kind: .generating,
            title: "Generating transcript",
            value: nil,
            actionTitle: nil,
            rowAction: nil,
            trailingAction: nil,
            accessibilityLabel: "Generating transcript",
            accessibilityHint: "You can close this sheet",
            symbol: .spinner,
            trailingUpgradesContrast: false,
            menu: []
        )
    }

    private static func ready() -> DetailTranscriptContent {
        DetailTranscriptContent(
            kind: .ready,
            title: "Transcript ready",
            value: nil,
            actionTitle: "Ask AI",
            rowAction: .read,
            trailingAction: .askAI,
            accessibilityLabel: "Transcript ready",
            accessibilityHint: "Double-tap to read",
            symbol: .lines,
            trailingUpgradesContrast: false,
            menu: [
                DetailTranscriptMenuItem(title: "Read transcript", subtitle: nil, action: .read),
                DetailTranscriptMenuItem(title: "Ask AI", subtitle: nil, action: .askAI),
            ]
        )
    }

    private static func failed(policy: DetailTranscriptPolicy) -> DetailTranscriptContent {
        accountRow(
            kind: .failed,
            title: "Couldn't transcribe",
            value: nil,
            actionTitle: "Retry",
            action: .generate,
            accessibilityLabel: "Couldn't transcribe",
            accessibilityHint: "Double-tap to retry",
            symbol: .warning,
            menuSubtitle: nil,
            policy: policy
        )
    }

    // MARK: - Pieces

    private static func accountRow(
        kind: DetailTranscriptContent.Kind,
        title: String = "AI transcript",
        value: String?,
        actionTitle: String,
        action: DetailTranscriptAction,
        accessibilityLabel: String,
        accessibilityHint: String,
        symbol: DetailTranscriptContent.Symbol = .sparkle,
        menuSubtitle: String?,
        policy: DetailTranscriptPolicy
    ) -> DetailTranscriptContent {
        DetailTranscriptContent(
            kind: kind,
            title: title,
            value: value,
            actionTitle: actionTitle,
            rowAction: action,
            trailingAction: action,
            accessibilityLabel: accessibilityLabel,
            accessibilityHint: accessibilityHint,
            symbol: symbol,
            trailingUpgradesContrast: false,
            menu: menu(
                primary: DetailTranscriptMenuItem(
                    title: "Generate transcript", subtitle: menuSubtitle, action: action
                ),
                policy: policy
            )
        )
    }

    /// The primary entry, plus Ask AI when the policy keeps that entry
    /// available before a transcript exists. Ready builds its own menu.
    private static func menu(
        primary: DetailTranscriptMenuItem,
        policy: DetailTranscriptPolicy
    ) -> [DetailTranscriptMenuItem] {
        guard !policy.askAIOnlyWhenReady else { return [primary] }
        return [
            primary,
            DetailTranscriptMenuItem(title: "Ask AI", subtitle: nil, action: .askAI),
        ]
    }

    /// Free remaining clamps into the lifetime pool; Plus into the monthly
    /// pool. The API reports no reset date, so the row never names one.
    static func clamp(_ remaining: Int, subscribed: Bool) -> Int {
        let total = subscribed ? AccountPageModel.plusTotal : AccountPageModel.freeTotal
        return min(max(remaining, 0), total)
    }
}

/// How Read transcript / Ask AI treat the player. Another episode that is
/// actually playing stays put: no queue insert, no Inbox removal, no
/// `setByEpisode`. Nothing playing can still load this episode paused.
nonisolated enum TranscriptOpenPlan: Equatable, Sendable {
    /// This episode is already the current one. Just show its transcript.
    case showCurrent
    /// Nothing is playing. Load this episode without starting audio.
    /// `prepareEpisode` must succeed or the player stays closed.
    case loadWithoutPlaying
    /// A different episode is playing. Show this transcript beside it.
    case browseWhileOtherPlays

    static func make(enclosureURL: String, currentURL: String?, isPlaying: Bool) -> TranscriptOpenPlan {
        let current = currentURL?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let target = enclosureURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if !current.isEmpty, current == target { return .showCurrent }
        if isPlaying, !current.isEmpty { return .browseWhileOtherPlays }
        return .loadWithoutPlaying
    }

    /// Only the paused-load path depends on queue preparation. Failing that
    /// must not open the player on whatever episode is already current.
    var requiresSuccessfulPrepare: Bool { self == .loadWithoutPlaying }
}

/// The episode a transcript page can show without becoming the current item.
nonisolated struct TranscriptBrowseTarget: Equatable, Sendable {
    var enclosureURL: String
    var title: String
    var channelTitle: String?
    var imageURL: String?
}

/// Short-lived memory of `GET /api/user`'s `remaining`, shared by the
/// detail sheet and Membership. Keyed by account id so a sign-out or a
/// different login cannot display the previous account's count. Purchase,
/// restore, sign-out, and an accepted generate all invalidate it.
@MainActor
final class TranscriptAllowanceCache {

    static let shared = TranscriptAllowanceCache()

    private struct Record {
        var uid: String
        var allowance: TranscriptAllowance
        var fetchedAt: Date
    }

    private var record: Record?
    private let freshness: TimeInterval

    init(freshness: TimeInterval = DetailTranscriptPolicy.current.allowanceFreshness) {
        self.freshness = freshness
    }

    /// The value when it belongs to `uid` and is still inside the freshness window.
    func current(uid: String, now: Date = Date()) -> TranscriptAllowance? {
        guard let record, record.uid == uid, now.timeIntervalSince(record.fetchedAt) < freshness else { return nil }
        return record.allowance
    }

    @discardableResult
    func store(_ allowance: TranscriptAllowance, uid: String, now: Date = Date()) -> TranscriptAllowance {
        record = Record(uid: uid, allowance: allowance, fetchedAt: now)
        return allowance
    }

    func invalidate() {
        record = nil
    }
}
