import Foundation

/// The four steps of the first-launch onboarding, in order.
nonisolated enum OnboardingStep: Int, CaseIterable, Sendable {
    case welcome
    case subscriptions
    case inbox
    case transcript
}

/// A sample episode for the inbox lesson. Teaching data only: it never
/// reaches the database, the real queue or the network.
nonisolated struct OnboardingSampleEpisode: Equatable, Sendable {
    let id: String
    let title: String
    let show: String
    let minutes: Int
}

/// A sample transcript line for the transcript lesson.
nonisolated struct OnboardingSampleLine: Equatable, Sendable {
    let timestamp: String
    let original: String
    let translation: String
}

/// The onboarding's step and answer state, free of UIKit so it can be tested.
/// The container view controller owns one value and renders from it.
nonisolated struct OnboardingFlow: Equatable {

    /// What the quiet button under the primary button does on this step.
    nonisolated enum SkipOption: Equatable {
        /// No skip button on this step.
        case none
        /// "Skip" on the first step: end the onboarding.
        case all
    }

    private(set) var step: OnboardingStep = .welcome
    /// Sample episodes added in the inbox lesson, in the order added.
    private(set) var queuedEpisodeIDs: [String] = []
    /// Set when the onboarding ended, by finishing or by skipping all of it.
    private(set) var isFinished = false

    /// Progress bar value: each step fills an equal quarter of the flow.
    var progress: Float {
        Float(step.rawValue + 1) / Float(OnboardingStep.allCases.count)
    }

    /// Whether the primary button is enabled on the current step.
    var canContinue: Bool {
        true
    }

    var skipOption: SkipOption {
        switch step {
        case .welcome:
            return .all
        case .subscriptions, .inbox, .transcript:
            return .none
        }
    }

    /// Adds or removes a sample episode. Returns whether it is now queued.
    @discardableResult
    mutating func toggleQueued(_ id: String) -> Bool {
        if let index = queuedEpisodeIDs.firstIndex(of: id) {
            queuedEpisodeIDs.remove(at: index)
            return false
        }
        queuedEpisodeIDs.append(id)
        return true
    }

    /// The primary button: moves to the next step, or finishes on the last
    /// one. Returns whether anything changed.
    @discardableResult
    mutating func advance() -> Bool {
        guard !isFinished, canContinue else { return false }
        moveForward()
        return true
    }

    /// "Skip" on the first step: ends the onboarding.
    mutating func skipAll() {
        guard !isFinished, skipOption == .all else { return }
        isFinished = true
    }

    /// Destination tab index when onboarding closes (via completion or Skip):
    /// Tab 0 (Inbox) when the listener follows at least one show; Tab 2
    /// (Discover) when following none. Never Tab 1 (Playlist).
    static func exitTabIndex(subscriptionCount: Int) -> Int {
        subscriptionCount > 0 ? 0 : 2
    }

    private mutating func moveForward() {
        if let next = OnboardingStep(rawValue: step.rawValue + 1) {
            step = next
        } else {
            isFinished = true
        }
    }
}

/// Whether the onboarding was already completed or skipped, kept in
/// `UserDefaults` as a Bool under `key`. UI tests pass
/// `-onboarding.completed YES` (the argument domain) to start on the shell.
struct OnboardingGate {

    /// `UserDefaults` key of the Bool flag.
    static let key = "onboarding.completed"

    nonisolated enum Decision: Equatable {
        /// Show the onboarding.
        case present
        /// Someone who already has data of their own — an upgrade from an
        /// earlier version: do not show it, and remember that.
        case markCompleted
        /// Do not show it this launch; decide again next launch.
        case skip
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var hasCompleted: Bool {
        defaults.bool(forKey: Self.key)
    }

    func markCompleted() {
        defaults.set(true, forKey: Self.key)
    }

    /// `hasExistingData` covers every store a listener can already have
    /// rows in — subscriptions, playlist episodes, history, inbox episodes.
    /// It is nil when one of them could not be read.
    static func decision(hasCompleted: Bool, hasExistingData: Bool?) -> Decision {
        if hasCompleted { return .skip }
        guard let hasExistingData else { return .skip }
        return hasExistingData ? .markCompleted : .present
    }
}

/// Onboarding copy. The onboarding is written in English; like the rest of
/// the app's copy it lives in source (see `ImportCopy`).
nonisolated enum OnboardingCopy {

    // Buttons.
    static let start = "Get started"
    static let next = "Continue"
    static let openAnycast = "Open Anycast"
    static let skip = "Skip"

    // Step 1: Welcome.
    static let welcomeTitle = "Listen, read along, and ask."
    static let welcomeBody = "New episodes land in your Inbox, with AI transcripts you can read along and ask."

    // Step 2: Subscriptions.
    static let subscriptionsTitle = "Bring your shows"
    static let importFromApp = "Import from another app"
    static let importFromAppDetail = "Export steps or choose an OPML file"
    static let pasteFeed = "Paste an RSS link"
    static let pasteFeedDetail = "Follow one show directly"
    static let pasteFeedPlaceholder = "https://"
    static let pasteFeedConfirm = "View show"
    static let cancel = "Cancel"
    static let notAFeedAddress = "That doesn't look like an RSS link"

    static func subscriptionStatus(count: Int) -> String? {
        guard count > 0 else { return nil }
        let noun = count == 1 ? "show" : "shows"
        return "Following \(count) \(noun) · New episodes are in your Inbox"
    }

    // Step 3: Inbox.
    static let inboxTitle = "Line up what plays next"
    static let inboxHint = "Swipe right on an episode to add it to your Playlist."
    static let swipeAddToPlaylist = "Add to playlist"
    static let swipeInPlaylist = "In Playlist"
    static let playlist = "Playlist"
    static let playlistEmpty = "Nothing queued"
    static func minutes(_ count: Int) -> String { "\(count)m" }
    static func addToPlaylist(_ title: String) -> String { "Add \(title) to Playlist" }
    static func removeFromPlaylist(_ title: String) -> String { "Remove \(title) from Playlist" }

    // Step 4: Transcript.
    static let transcriptTitle = "Read along, then ask"
    static var transcriptHint: String {
        "Every episode can get an AI transcript. \(PlusOffer.freePitch) when you sign in."
    }
    static let transcriptShow = "Craft & Form"
    static let askEpisode = "What are the main takeaways?"
    static let askEpisodePoints = [
        "1. Attention is scarcer than time.",
        "2. Save hard work for peak energy.",
        "3. Task-switching has a steep hidden cost.",
    ]
    static func jumpToTimestamp(_ timestamp: String) -> String { "Jump to \(timestamp)" }
}

/// Sample content for the two interactive lessons.
nonisolated enum OnboardingSamples {

    static let episodes = [
        OnboardingSampleEpisode(id: "sample-1", title: "How AI changes daily work", show: "Morning Notes", minutes: 32),
        OnboardingSampleEpisode(id: "sample-2", title: "Good design disappears", show: "Craft & Form", minutes: 18),
        OnboardingSampleEpisode(id: "sample-3", title: "A city on the Silk Road", show: "Quiet History", minutes: 41),
    ]

    static var transcript: [OnboardingSampleLine] {
        transcript(forPreferredLanguages: Locale.preferredLanguages)
    }

    /// Picks a sample translation language matching the listener's preferred
    /// languages (`zh`, `ja`, `es`, `fr`), defaulting to Spanish so English
    /// devices do not unexpectedly show Simplified Chinese.
    static func transcript(forPreferredLanguages languages: [String]) -> [OnboardingSampleLine] {
        let code = preferredTranslationCode(from: languages)
        switch code {
        case "zh":
            return [
                OnboardingSampleLine(
                    timestamp: "00:42",
                    original: "Attention, not time, is the resource you actually control.",
                    translation: "你真正能支配的资源是注意力，而不是时间。"
                ),
                OnboardingSampleLine(
                    timestamp: "03:15",
                    original: "Put the hardest work where your energy peaks.",
                    translation: "把最难的事留给精力最好的时段。"
                ),
                OnboardingSampleLine(
                    timestamp: "07:08",
                    original: "Switching tasks costs far more than we assume.",
                    translation: "切换任务的隐性代价，比我们以为的高得多。"
                ),
            ]
        case "ja":
            return [
                OnboardingSampleLine(
                    timestamp: "00:42",
                    original: "Attention, not time, is the resource you actually control.",
                    translation: "本当にコントロールできるのは時間ではなく、注意力だ。"
                ),
                OnboardingSampleLine(
                    timestamp: "03:15",
                    original: "Put the hardest work where your energy peaks.",
                    translation: "最も難しい仕事は、集中力が最も高い時間帯に当てよう。"
                ),
                OnboardingSampleLine(
                    timestamp: "07:08",
                    original: "Switching tasks costs far more than we assume.",
                    translation: "タスクの切り替えには、私たちが思う以上のコストがかかる。"
                ),
            ]
        case "fr":
            return [
                OnboardingSampleLine(
                    timestamp: "00:42",
                    original: "Attention, not time, is the resource you actually control.",
                    translation: "L\u{2019}attention, et non le temps, est la ressource que vous contrôlez vraiment."
                ),
                OnboardingSampleLine(
                    timestamp: "03:15",
                    original: "Put the hardest work where your energy peaks.",
                    translation: "Consacrez vos pics d\u{2019}énergie aux tâches les plus difficiles."
                ),
                OnboardingSampleLine(
                    timestamp: "07:08",
                    original: "Switching tasks costs far more than we assume.",
                    translation: "Changer de tâche coûte bien plus cher qu\u{2019}on ne le croit."
                ),
            ]
        default:
            return [
                OnboardingSampleLine(
                    timestamp: "00:42",
                    original: "Attention, not time, is the resource you actually control.",
                    translation: "La atención, no el tiempo, es el recurso que realmente controlas."
                ),
                OnboardingSampleLine(
                    timestamp: "03:15",
                    original: "Put the hardest work where your energy peaks.",
                    translation: "Dedica tus momentos de mayor energía al trabajo más difícil."
                ),
                OnboardingSampleLine(
                    timestamp: "07:08",
                    original: "Switching tasks costs far more than we assume.",
                    translation: "Cambiar de tarea cuesta mucho más de lo que suponemos."
                ),
            ]
        }
    }

    private static func preferredTranslationCode(from languages: [String]) -> String {
        let supported: Set<String> = ["zh", "ja", "es", "fr"]
        for identifier in languages {
            let subtag = identifier
                .split(whereSeparator: { $0 == "-" || $0 == "_" })
                .first
                .map { String($0).lowercased() }
            if let subtag, supported.contains(subtag) {
                return subtag
            }
        }
        return "es"
    }
}
