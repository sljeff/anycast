import Foundation

/// The seven steps of the first-launch onboarding, in order.
nonisolated enum OnboardingStep: Int, CaseIterable, Sendable {
    case welcome
    case interests
    case subscriptions
    case impression
    case queueLesson
    case transcriptLesson
    case done
}

/// A sample episode for the queue lesson. Teaching data only: it never
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
        /// No skip button (the last step).
        case none
        /// "Skip this step": go to the next step.
        case step
        /// "Skip, enter directly" on the first step: end the onboarding.
        case all
    }

    /// The queue lesson's primary button enables once this many are added.
    static let requiredQueueCount = 2

    private(set) var step: OnboardingStep = .welcome
    /// Chosen interests, in the order they were chosen.
    private(set) var interests: [String] = []
    /// Sample episodes added in the queue lesson, in the order added.
    private(set) var queuedEpisodeIDs: [String] = []
    /// Whether the sample question was asked in the transcript lesson.
    private(set) var hasAskedEpisode = false
    /// Set when the onboarding ended, by finishing or by skipping all of it.
    private(set) var isFinished = false

    /// Progress bar value: the first step already shows a sliver.
    var progress: Float {
        Float(step.rawValue + 1) / Float(OnboardingStep.allCases.count)
    }

    /// Whether the primary button is enabled on the current step.
    var canContinue: Bool {
        switch step {
        case .interests:
            return !interests.isEmpty
        case .queueLesson:
            return queuedEpisodeIDs.count >= Self.requiredQueueCount
        case .transcriptLesson:
            return hasAskedEpisode
        case .welcome, .subscriptions, .impression, .done:
            return true
        }
    }

    var skipOption: SkipOption {
        switch step {
        case .welcome: return .all
        case .done: return .none
        default: return .step
        }
    }

    /// Selects or deselects an interest. Returns whether it is now selected.
    @discardableResult
    mutating func toggleInterest(_ name: String) -> Bool {
        if let index = interests.firstIndex(of: name) {
            interests.remove(at: index)
            return false
        }
        interests.append(name)
        return true
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

    mutating func markEpisodeAsked() {
        hasAskedEpisode = true
    }

    /// The primary button: moves to the next step, or finishes on the last
    /// one. Does nothing while the step's requirement is unmet. Returns
    /// whether anything changed.
    @discardableResult
    mutating func advance() -> Bool {
        guard !isFinished, canContinue else { return false }
        moveForward()
        return true
    }

    /// "Skip this step": moves on without the step's requirement. Skipping
    /// the interests step drops a half-made choice, so later steps do not
    /// describe interests the listener declined to confirm.
    mutating func skipStep() {
        guard !isFinished, skipOption == .step else { return }
        if step == .interests { interests.removeAll() }
        moveForward()
    }

    /// "Skip, enter directly" on the first step: ends the onboarding.
    mutating func skipAll() {
        guard skipOption == .all else { return }
        isFinished = true
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

    static let brandMark = "\u{2731}"

    // Buttons.
    static let start = "Get started"
    static let next = "Continue"
    static let enter = "Enter Anycast"
    static let skipStep = "Skip this step"
    static let skipAll = "Skip and go straight in"
    static func interestsDone(count: Int) -> String { "That's it (\(count))" }

    // Step 1.
    static let welcomeTitle = "Hi, I'm Anycast."
    static let welcomeBody = "I keep what you want to hear lined up, then turn episodes into text and answer your questions about them. Got a minute to get to know each other?"

    // Step 2.
    static let interestsQuestion = "Let's start with you. What do you usually listen to?"
    static let interestsHint = "Pick as many as you like."
    static let interests = ["Tech", "Business", "Design", "History", "Languages", "Comedy", "News", "Psychology"]

    // Step 3.
    static let subscriptionsQuestion = "Using another podcast app? You can bring your subscriptions with you."
    static let importFromApp = "Import from another app"
    static let importFromAppDetail = "Choose an exported OPML file"
    static let pasteFeed = "Paste an RSS link"
    static let pasteFeedDetail = "Follow one show directly"
    static let startFromPicks = "Start fresh"
    static let startFromPicksDetail = "You can still import later in Settings"
    static let pasteFeedPlaceholder = "https://"
    static let pasteFeedConfirm = "View show"
    static let cancel = "Cancel"
    static let notAFeedAddress = "That doesn't look like an RSS link"
    static let feedSheetDone = "Done"

    // Step 4.
    static func impression(interests: [String]) -> String {
        let leading = interests.prefix(2).joined(separator: " and ")
        let taste = leading.isEmpty
            ? "You haven't told me what you like yet, but you probably"
            : "You lean toward \(leading) shows, you"
        return "Here's my first impression from your interests. \(taste) like episodes that teach you something, and you likely listen on the commute or while getting things done."
    }
    static let helpTitle = "How I'll help"
    static let helpLines = [
        "New episodes from your shows land in the Inbox, ready to play",
        "Long episodes get a text summary first, so you can decide",
        "Bilingual subtitles cover hard accents and jargon",
    ]
    static let impressionFeedback = "If anything sounds off, tell me."
    static let impressionRight = "Sounds right"
    static let impressionWrong = "Something's off"
    static let impressionRightReply = "Great, I'll go with that."
    static let impressionWrongReply = "No problem. I'll get to know you better as you listen."

    // Step 5.
    static let queueTitle = "Your queue decides what plays next"
    static let queueHint = "Add two episodes to Up Next. When one ends, the next starts on its own."
    static let sampleCaption = "Sample episodes"
    static let upNext = "Up Next"
    static let upNextEmpty = "Nothing here yet"
    static func minutes(_ count: Int) -> String { "\(count) min" }
    static func addToUpNext(_ title: String) -> String { "Add \(title) to Up Next" }
    static func removeFromUpNext(_ title: String) -> String { "Remove \(title) from Up Next" }

    // Step 6.
    static let transcriptTitle = "Read along, then ask"
    static let transcriptHint = "Every episode can get an AI transcript with bilingual subtitles. Tap a line to jump there, or ask the episode a question."
    static let sampleTranscriptCaption = "Sample transcript"
    static let askEpisode = "Ask this episode: what are the three main points?"
    static let askEpisodeAnswer = "This episode makes three points:\n1. Attention is scarcer than time\n2. Save the hardest work for your best energy\n3. Switching tasks costs a lot\n(Sample answer)"

    // Step 7.
    // The lessons queue sample episodes only, so this never speaks of a
    // queue the user will not find on the Playlist tab.
    static let done = "You're all set. Those were practice episodes, so your Playlist starts empty. Add real ones the same way and they'll line up there."
}

/// Sample content for the two lessons.
nonisolated enum OnboardingSamples {

    static let episodes = [
        OnboardingSampleEpisode(id: "sample-1", title: "How AI assistants are changing everyday work", show: "Morning Tech", minutes: 32),
        OnboardingSampleEpisode(id: "sample-2", title: "What a small shop knows about business", show: "Small Business Notes", minutes: 24),
        OnboardingSampleEpisode(id: "sample-3", title: "Why good design goes unnoticed", show: "Design Talk", minutes: 18),
        OnboardingSampleEpisode(id: "sample-4", title: "A city on the Silk Road", show: "Echoes of History", minutes: 41),
    ]

    static let transcript = [
        OnboardingSampleLine(
            timestamp: "00:42",
            original: "Attention, not time, is the resource you actually control.",
            translation: "注意力不是时间，而是你真正能支配的资源。"
        ),
        OnboardingSampleLine(
            timestamp: "03:15",
            original: "Put the hardest work where your energy peaks.",
            translation: "把最难的事放在一天里精力最好的那一段。"
        ),
        OnboardingSampleLine(
            timestamp: "07:08",
            original: "Switching tasks costs far more than we assume.",
            translation: "切换任务的代价，比我们以为的高得多。"
        ),
        OnboardingSampleLine(
            timestamp: "11:30",
            original: "Rest is not a reward; it is part of the work.",
            translation: "休息不是奖励，它本身就是工作的一部分。"
        ),
    ]
}
