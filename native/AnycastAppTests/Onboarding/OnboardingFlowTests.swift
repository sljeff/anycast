import Foundation
import Testing
import AnycastKit
@testable import Anycast

/// The onboarding's step state: what the primary button needs on each step,
/// what the skip button does, and the first-launch gate.
@MainActor
struct OnboardingFlowTests {

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
    }

    @Test("Skip-all only works on the welcome step")
    func skipAllOnlyOnWelcome() {
        var flow = OnboardingFlow()
        flow.advance()
        flow.skipAll()
        #expect(!flow.isFinished)
        #expect(flow.step == .interests)
    }

    @Test("Interests needs at least one choice, kept in the order chosen")
    func interestsRequireAChoice() {
        var flow = OnboardingFlow()
        flow.advance()
        #expect(flow.step == .interests)
        #expect(!flow.canContinue)
        #expect(flow.advance() == false)
        #expect(flow.step == .interests)

        #expect(flow.toggleInterest("Design") == true)
        #expect(flow.toggleInterest("Tech") == true)
        #expect(flow.interests == ["Design", "Tech"])
        #expect(flow.toggleInterest("Design") == false)
        #expect(flow.interests == ["Tech"])
        #expect(flow.canContinue)
        #expect(flow.advance() == true)
        #expect(flow.step == .subscriptions)
    }

    @Test("Skip is offered on the interests step only while nothing is chosen")
    func interestsSkipFlipsOnceChosen() {
        var flow = OnboardingFlow()
        flow.advance()
        #expect(flow.skipOption == .step)

        flow.toggleInterest("News")
        #expect(flow.skipOption == .none)
        // With no skip offered, skipping does nothing and keeps the choice.
        flow.skipStep()
        #expect(flow.step == .interests)
        #expect(flow.interests == ["News"])

        flow.toggleInterest("News")
        #expect(flow.skipOption == .step)
        flow.skipStep()
        #expect(flow.step == .subscriptions)
        #expect(flow.interests.isEmpty)
    }

    @Test("The queue lesson continues once two sample episodes are added")
    func queueLessonNeedsTwo() {
        var flow = flow(at: .queueLesson)
        #expect(!flow.canContinue)
        #expect(flow.skipOption == .step)

        #expect(flow.toggleQueued("sample-2") == true)
        #expect(!flow.canContinue)
        #expect(flow.skipOption == .step)
        #expect(flow.toggleQueued("sample-1") == true)
        #expect(flow.canContinue)
        #expect(flow.skipOption == .none)
        #expect(flow.queuedEpisodeIDs == ["sample-2", "sample-1"])
        #expect(flow.toggleQueued("sample-2") == false)
        #expect(!flow.canContinue)
        #expect(flow.skipOption == .step)
        #expect(flow.queuedEpisodeIDs == ["sample-1"])
    }

    @Test("The transcript lesson continues once the sample question is asked")
    func transcriptLessonNeedsTheQuestion() {
        var flow = flow(at: .transcriptLesson)
        #expect(!flow.canContinue)
        #expect(flow.skipOption == .step)
        flow.markEpisodeAsked()
        #expect(flow.canContinue)
        #expect(flow.skipOption == .none)
        #expect(flow.advance() == true)
        #expect(flow.step == .done)
    }

    @Test("Steps without a requirement offer no skip")
    func noSkipWithoutRequirement() {
        for step in [OnboardingStep.subscriptions, .impression, .done] {
            var flow = flow(at: step)
            #expect(flow.skipOption == .none)
            flow.skipStep()
            #expect(flow.step == step)
        }
    }

    @Test("An unmet step can be skipped; the last step has no skip and finishes")
    func skipThroughToTheEnd() {
        var flow = OnboardingFlow()
        flow.advance()
        var skipped: [OnboardingStep] = []
        while true {
            if flow.skipOption == .step {
                skipped.append(flow.step)
                flow.skipStep()
            } else if flow.step != .done {
                flow.advance()
            } else {
                break
            }
        }
        // Nothing was answered, so each requirement step is skipped.
        #expect(skipped == [.interests, .queueLesson, .transcriptLesson])
        #expect(flow.step == .done)
        #expect(flow.skipOption == .none)

        // Skip does nothing on the last step; the primary button finishes.
        flow.skipStep()
        #expect(flow.step == .done)
        #expect(!flow.isFinished)
        #expect(flow.advance() == true)
        #expect(flow.isFinished)
        #expect(flow.advance() == false)
    }

    @Test("Progress grows with each step and ends full")
    func progress() {
        var flow = OnboardingFlow()
        var previous = flow.progress
        #expect(previous > 0)
        while flow.step != .done {
            if flow.skipOption == .step { flow.skipStep() } else { flow.advance() }
            #expect(flow.progress > previous)
            previous = flow.progress
        }
        #expect(flow.progress == 1)
    }

    @Test("The impression names the first two interests, or none")
    func impressionCopy() {
        #expect(OnboardingCopy.impression(interests: ["Tech", "Business", "Design"]).contains("You lean toward Tech and Business shows"))
        #expect(OnboardingCopy.impression(interests: ["Comedy"]).contains("You lean toward Comedy shows"))
        #expect(!OnboardingCopy.impression(interests: []).contains("You lean toward"))
    }

    /// A flow moved to `target` with every requirement met on the way.
    private func flow(at target: OnboardingStep) -> OnboardingFlow {
        var flow = OnboardingFlow()
        while flow.step != target {
            switch flow.step {
            case .interests:
                flow.toggleInterest("Tech")
            case .queueLesson:
                flow.toggleQueued("sample-1")
                flow.toggleQueued("sample-2")
            case .transcriptLesson:
                flow.markEpisodeAsked()
            default:
                break
            }
            flow.advance()
        }
        return flow
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
