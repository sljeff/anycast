import Foundation
import Testing
import AnycastKit
@testable import Anycast

/// The onboarding's 4-step state: step order, skip behavior, primary
/// button readiness, progress, finish tab routing, and the first-launch gate.
@MainActor
struct OnboardingFlowTests {

    @Test("Step order matches the 4-step flow")
    func stepOrder() {
        #expect(OnboardingStep.allCases == [.welcome, .subscriptions, .inbox, .transcript])
    }

    @Test("Starts on the welcome step, which can continue or skip everything")
    func startsOnWelcome() {
        let flow = OnboardingFlow()
        #expect(flow.step == .welcome)
        #expect(flow.canContinue)
        #expect(flow.skipOption == .all)
        #expect(!flow.isFinished)
    }

    @Test("Skipping on the welcome step ends the onboarding")
    func skipAllFinishes() {
        var flow = OnboardingFlow()
        flow.skipAll()
        #expect(flow.isFinished)
        #expect(flow.step == .welcome)
        #expect(flow.advance() == false)
    }

    @Test("Skip is offered only on the welcome step")
    func skipOptionsPerStep() {
        var flow = OnboardingFlow()
        #expect(flow.skipOption == .all)

        for expected in [OnboardingStep.subscriptions, .inbox, .transcript] {
            #expect(flow.advance() == true)
            #expect(flow.step == expected)
            #expect(flow.skipOption == .none)
            flow.skipAll()
            #expect(!flow.isFinished)
            #expect(flow.step == expected)
        }
    }

    @Test("Continue is enabled on every step and advancing past the last step finishes")
    func advanceAndCanContinueAcrossAllSteps() {
        var flow = OnboardingFlow()
        for expected in [OnboardingStep.welcome, .subscriptions, .inbox, .transcript] {
            #expect(flow.step == expected)
            #expect(flow.canContinue)
            #expect(!flow.isFinished)
            #expect(flow.advance() == true)
        }
        #expect(flow.isFinished)
        #expect(flow.step == .transcript)
        #expect(flow.advance() == false)
    }

    @Test("The inbox lesson toggles sample episodes in add order without gating continue")
    func inboxToggleDoesNotGateContinue() {
        var flow = OnboardingFlow()
        flow.advance()
        flow.advance()
        #expect(flow.step == .inbox)
        #expect(flow.canContinue)

        #expect(flow.toggleQueued("sample-2") == true)
        #expect(flow.canContinue)
        #expect(flow.toggleQueued("sample-1") == true)
        #expect(flow.queuedEpisodeIDs == ["sample-2", "sample-1"])
        #expect(flow.toggleQueued("sample-2") == false)
        #expect(flow.queuedEpisodeIDs == ["sample-1"])
        #expect(flow.canContinue)
    }

    @Test("Progress grows by equal quarters across all four steps")
    func progressValues() {
        var flow = OnboardingFlow()
        var recorded: [Float] = []
        for _ in OnboardingStep.allCases {
            recorded.append(flow.progress)
            flow.advance()
        }
        #expect(recorded == [0.25, 0.5, 0.75, 1.0])
        #expect(flow.isFinished)
    }

    @Test("Exit tab routes to Inbox when subscribed and Discover when empty")
    func exitTabRouting() {
        #expect(OnboardingFlow.exitTabIndex(subscriptionCount: 0) == 2)
        #expect(OnboardingFlow.exitTabIndex(subscriptionCount: 1) == 0)
        #expect(OnboardingFlow.exitTabIndex(subscriptionCount: 5) == 0)
    }

    @Test("Subscription status formats singular, plural, and hidden states")
    func subscriptionStatusCopy() {
        #expect(OnboardingCopy.subscriptionStatus(count: 0) == nil)
        #expect(OnboardingCopy.subscriptionStatus(count: 1) == "Following 1 show · New episodes are in your Inbox")
        #expect(OnboardingCopy.subscriptionStatus(count: 3) == "Following 3 shows · New episodes are in your Inbox")
    }

    @Test("Sample episodes and transcript copy follow product specs")
    func sampleContentAndCopy() {
        #expect(OnboardingSamples.episodes.count == 3)
        #expect(OnboardingCopy.transcriptHint.contains(PlusOffer.freePitch))

        let chinese = OnboardingSamples.transcript(forPreferredLanguages: ["zh-Hans-US"])
        let japanese = OnboardingSamples.transcript(forPreferredLanguages: ["ja-JP"])
        let fallback = OnboardingSamples.transcript(forPreferredLanguages: ["en-US"])
        #expect(chinese.count == 3)
        #expect(japanese.count == 3)
        #expect(fallback.count == 3)
        #expect(chinese[0].translation != fallback[0].translation)
        #expect(japanese[0].translation != chinese[0].translation)
    }

    // MARK: - Gate

    @Test("The gate reads false until marked, then stays true")
    func gatePersists() {
        let suiteName = "OnboardingFlowTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let gate = OnboardingGate(defaults: defaults)
        #expect(!gate.hasCompleted)
        gate.markCompleted()
        #expect(gate.hasCompleted)
        #expect(OnboardingGate(defaults: defaults).hasCompleted)
    }

    @Test("Only a first launch with no data of any kind presents the onboarding")
    func gateDecision() {
        #expect(OnboardingGate.decision(hasCompleted: false, hasExistingData: false) == .present)
        // Someone upgrading with ANY existing data — subscriptions,
        // playlist episodes, history or inbox episodes — is marked done.
        #expect(OnboardingGate.decision(hasCompleted: false, hasExistingData: true) == .markCompleted)
        // An unreadable store decides nothing this launch.
        #expect(OnboardingGate.decision(hasCompleted: false, hasExistingData: nil) == .skip)
        #expect(OnboardingGate.decision(hasCompleted: true, hasExistingData: false) == .skip)
    }

    // MARK: - Existing-data probe (the gate's input)

    private static func makeDatabase(_ name: String) async throws -> (AppDatabase, URL) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("OnboardingFlowTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("\(name).db")
        let database = try await AppDatabase.openAt(url, localeIdentifier: "en_US")
        return (database, directory)
    }

    @Test("The probe sees each store alone as existing data; a fresh install has none")
    func existingDataProbe() async throws {
        let (database, directory) = try await Self.makeDatabase("probe")
        defer { try? FileManager.default.removeItem(at: directory) }

        // Fresh install: nothing anywhere.
        let fresh = try await OnboardingLauncher.listenerHasExistingData(database)
        #expect(!fresh)

        // History alone (a listener who played but never followed).
        try await database.historyRepository().insert(
            HistoryEpisodeRow(title: "Played once", enclosureUrl: "https://example.com/a.mp3")
        )
        #expect(try await OnboardingLauncher.listenerHasExistingData(database))

        // A fresh database with only an inbox row.
        let (inboxOnly, inboxDirectory) = try await Self.makeDatabase("inbox")
        defer { try? FileManager.default.removeItem(at: inboxDirectory) }
        try await inboxOnly.feedRepository().insertMany([
            FeedEpisodeRow(title: "New episode", enclosureUrl: "https://example.com/b.mp3")
        ])
        #expect(try await OnboardingLauncher.listenerHasExistingData(inboxOnly))

        // A fresh database with only a playlist row.
        let (playlistOnly, playlistDirectory) = try await Self.makeDatabase("playlist")
        defer { try? FileManager.default.removeItem(at: playlistDirectory) }
        try await playlistOnly.playlistRepository().insertOrUpdateByIndex(
            PlaylistEpisodeRow(title: "Queued", enclosureUrl: "https://example.com/c.mp3"),
            playlistId: 1,
            index: 0
        )
        #expect(try await OnboardingLauncher.listenerHasExistingData(playlistOnly))

        // A fresh database with only a subscription.
        let (subscriptionsOnly, subscriptionsDirectory) = try await Self.makeDatabase("subscriptions")
        defer { try? FileManager.default.removeItem(at: subscriptionsDirectory) }
        try await subscriptionsOnly.subscriptionRepository().addMany([
            SubscriptionRow(rssFeedUrl: "https://example.com/feed.xml", title: "A show")
        ])
        #expect(try await OnboardingLauncher.listenerHasExistingData(subscriptionsOnly))
    }
}
