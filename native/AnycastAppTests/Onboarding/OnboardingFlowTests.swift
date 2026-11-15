import Foundation
import Testing
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

    @Test("Skipping the interests step drops a half-made choice")
    func skippingInterestsClearsThem() {
        var flow = OnboardingFlow()
        flow.advance()
        flow.toggleInterest("News")
        flow.skipStep()
        #expect(flow.step == .subscriptions)
        #expect(flow.interests.isEmpty)
    }

    @Test("The queue lesson continues once two sample episodes are added")
    func queueLessonNeedsTwo() {
        var flow = OnboardingFlow()
        flow.advance()
        flow.skipStep()
        flow.advance()
        flow.advance()
        #expect(flow.step == .queueLesson)
        #expect(!flow.canContinue)

        #expect(flow.toggleQueued("sample-2") == true)
        #expect(!flow.canContinue)
        #expect(flow.toggleQueued("sample-1") == true)
        #expect(flow.canContinue)
        #expect(flow.queuedEpisodeIDs == ["sample-2", "sample-1"])
        #expect(flow.toggleQueued("sample-2") == false)
        #expect(!flow.canContinue)
        #expect(flow.queuedEpisodeIDs == ["sample-1"])
    }

    @Test("The transcript lesson continues once the sample question is asked")
    func transcriptLessonNeedsTheQuestion() {
        var flow = OnboardingFlow()
        flow.advance()
        for _ in 0..<4 { flow.skipStep() }
        #expect(flow.step == .transcriptLesson)
        #expect(!flow.canContinue)
        flow.markEpisodeAsked()
        #expect(flow.canContinue)
        #expect(flow.advance() == true)
        #expect(flow.step == .done)
    }

    @Test("Every middle step can be skipped; the last step has no skip and finishes")
    func skipThroughToTheEnd() {
        var flow = OnboardingFlow()
        flow.advance()
        var visited: [OnboardingStep] = []
        while flow.skipOption == .step {
            visited.append(flow.step)
            flow.skipStep()
        }
        #expect(visited == [.interests, .subscriptions, .impression, .queueLesson, .transcriptLesson])
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
        flow.advance()
        while flow.skipOption == .step {
            #expect(flow.progress > previous)
            previous = flow.progress
            flow.skipStep()
        }
        #expect(flow.progress == 1)
    }

    @Test("The impression names the first two interests, or none")
    func impressionCopy() {
        #expect(OnboardingCopy.impression(interests: ["Tech", "Business", "Design"]).contains("You lean toward Tech and Business shows"))
        #expect(OnboardingCopy.impression(interests: ["Comedy"]).contains("You lean toward Comedy shows"))
        #expect(!OnboardingCopy.impression(interests: []).contains("You lean toward"))
    }

    // MARK: - Gate

    @Test("The gate reads false until marked, then stays true")
    func gatePersists() {
        let defaults = UserDefaults(suiteName: "OnboardingFlowTests-\(UUID().uuidString)")!
        let gate = OnboardingGate(defaults: defaults)
        #expect(!gate.hasCompleted)
        gate.markCompleted()
        #expect(gate.hasCompleted)
        #expect(OnboardingGate(defaults: defaults).hasCompleted)
    }

    @Test("Only a first launch with no subscriptions presents the onboarding")
    func gateDecision() {
        #expect(OnboardingGate.decision(hasCompleted: false, subscriptionCount: 0) == .present)
        // Someone upgrading with shows already followed is marked done.
        #expect(OnboardingGate.decision(hasCompleted: false, subscriptionCount: 3) == .markCompleted)
        // An unreadable database decides nothing this launch.
        #expect(OnboardingGate.decision(hasCompleted: false, subscriptionCount: nil) == .skip)
        #expect(OnboardingGate.decision(hasCompleted: true, subscriptionCount: 0) == .skip)
    }
}
