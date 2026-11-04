import UIKit
import Testing
@testable import Anycast

/// The detail transcript row's pure state: every presentation the proposal
/// lists, the Plus threshold, the clamps, the ••• entries, and the
/// allowance cache. View tests check the accessibility sentence the row
/// actually exposes.
@MainActor
struct DetailTranscriptStateTests {

    private let free = TranscriptAllowance(remaining: 7, isSubscribed: false)
    private let plusPlenty = TranscriptAllowance(remaining: 32, isSubscribed: true)
    private let plusLow = TranscriptAllowance(remaining: 3, isSubscribed: true)

    // MARK: - Account states

    @Test("Signed out draws Generate and no count, even if an allowance is passed")
    func signedOut() {
        let content = DetailTranscriptState.reduce(status: nil, signedIn: false, allowance: free)
        #expect(content.kind == .signedOut)
        #expect(content.title == "AI transcript")
        #expect(content.value == nil)
        #expect(content.actionTitle == "Generate")
        #expect(content.rowAction == .generate)
        #expect(content.accessibilityLabel == "AI transcript")
        #expect(content.accessibilityHint == "Double-tap to sign in and generate")
        #expect(content.menu.map(\.title) == ["Generate transcript"])
        #expect(content.menu.first?.subtitle == nil)
        #expect(content.accessibilityCustomActions.isEmpty)
    }

    @Test("Free with remaining shows the count and a Generate menu subtitle")
    func freeWithRemaining() {
        let content = DetailTranscriptState.reduce(status: nil, signedIn: true, allowance: free)
        #expect(content.kind == .available)
        #expect(content.value == "7 left")
        #expect(content.actionTitle == "Generate")
        #expect(content.accessibilityLabel == "AI transcript, 7 free left")
        #expect(content.accessibilityHint == "Double-tap to generate")
        #expect(content.symbol == .sparkle)
        #expect(content.menu == [
            DetailTranscriptMenuItem(title: "Generate transcript", subtitle: "7 free left", action: .generate),
        ])
    }

    @Test("Free remaining clamps into 0...10; zero is None left / Get Plus")
    func freeClampAndExhausted() {
        let high = DetailTranscriptState.reduce(
            status: nil, signedIn: true,
            allowance: TranscriptAllowance(remaining: 99, isSubscribed: false)
        )
        #expect(high.value == "10 left")
        #expect(high.menu.first?.subtitle == "10 free left")

        let negative = DetailTranscriptState.reduce(
            status: nil, signedIn: true,
            allowance: TranscriptAllowance(remaining: -4, isSubscribed: false)
        )
        #expect(negative.kind == .exhausted)
        #expect(negative.value == "None left")
        #expect(negative.actionTitle == "Get Plus")
        #expect(negative.rowAction == .getPlus)
        #expect(negative.trailingUpgradesContrast)
        #expect(negative.accessibilityLabel == "AI transcript, no free transcripts left")
        #expect(negative.accessibilityHint == "Double-tap to see Plus")
        #expect(negative.menu.map(\.title) == ["Get Plus"])
    }

    @Test("Plus hides the count above the threshold and shows it at the threshold")
    func plusThreshold() {
        let hidden = DetailTranscriptState.reduce(status: nil, signedIn: true, allowance: plusPlenty)
        #expect(hidden.kind == .plus)
        #expect(hidden.value == nil)
        #expect(hidden.actionTitle == "Generate")
        #expect(hidden.accessibilityLabel == "AI transcript")
        #expect(hidden.menu.first?.subtitle == nil)

        let shown = DetailTranscriptState.reduce(status: nil, signedIn: true, allowance: plusLow)
        #expect(shown.value == "3 left this month")
        #expect(shown.accessibilityLabel == "AI transcript, 3 left this month")
        #expect(shown.menu.first?.subtitle == "3 left this month")

        let atThreshold = DetailTranscriptState.reduce(
            status: nil, signedIn: true,
            allowance: TranscriptAllowance(remaining: 5, isSubscribed: true)
        )
        #expect(atThreshold.value == "5 left this month")
        let above = DetailTranscriptState.reduce(
            status: nil, signedIn: true,
            allowance: TranscriptAllowance(remaining: 6, isSubscribed: true)
        )
        #expect(above.value == nil)

        // Zero is still Generate — Plus is not the free paywall.
        let empty = DetailTranscriptState.reduce(
            status: nil, signedIn: true,
            allowance: TranscriptAllowance(remaining: 0, isSubscribed: true)
        )
        #expect(empty.kind == .plus)
        #expect(empty.value == "0 left this month")
        #expect(empty.actionTitle == "Generate")
        #expect(empty.rowAction == .generate)
    }

    @Test("A missing allowance draws no number")
    func unknownAllowance() {
        let content = DetailTranscriptState.reduce(status: nil, signedIn: true, allowance: nil)
        #expect(content.kind == .unknown)
        #expect(content.value == nil)
        #expect(content.actionTitle == "Generate")
        #expect(content.accessibilityHint == "Double-tap to generate")
        #expect(content.menu.first?.subtitle == nil)
    }

    // MARK: - Transcript status wins

    @Test("Generating is read-only and absent from the menu")
    func generating() {
        let content = DetailTranscriptState.reduce(status: "processing", signedIn: true, allowance: free)
        #expect(content.kind == .generating)
        #expect(content.title == "Generating transcript")
        #expect(content.value == nil)
        #expect(content.actionTitle == nil)
        #expect(content.rowAction == nil)
        #expect(content.symbol == .spinner)
        #expect(content.accessibilityLabel == "Generating transcript")
        #expect(content.accessibilityHint == "You can close this sheet")
        #expect(content.menu.isEmpty)
    }

    @Test("Ready offers read on the row and Ask AI beside it")
    func ready() {
        let content = DetailTranscriptState.reduce(
            status: "succeeded", signedIn: false, allowance: nil
        )
        #expect(content.kind == .ready)
        #expect(content.title == "Transcript ready")
        #expect(content.actionTitle == "Ask AI")
        #expect(content.rowAction == .read)
        #expect(content.trailingAction == .askAI)
        #expect(content.symbol == .lines)
        #expect(content.accessibilityLabel == "Transcript ready")
        #expect(content.accessibilityHint == "Double-tap to read")
        #expect(content.menu.map(\.title) == ["Read transcript", "Ask AI"])
        #expect(content.accessibilityCustomActions == [.askAI])
    }

    @Test("Failed offers Retry; an unknown server string uses the same row")
    func failed() {
        for status in ["failed", "weird"] {
            let content = DetailTranscriptState.reduce(status: status, signedIn: true, allowance: free)
            #expect(content.kind == .failed)
            #expect(content.title == "Couldn't transcribe")
            #expect(content.actionTitle == "Retry")
            #expect(content.rowAction == .generate)
            #expect(content.symbol == .warning)
            #expect(content.accessibilityHint == "Double-tap to retry")
            #expect(content.menu.first?.title == "Generate transcript")
        }
    }

    @Test("A transcript in flight or ready hides the quota line")
    func statusBeatsQuota() {
        let generating = DetailTranscriptState.reduce(
            status: "processing", signedIn: true,
            allowance: TranscriptAllowance(remaining: 0, isSubscribed: false)
        )
        #expect(generating.kind == .generating)
        let ready = DetailTranscriptState.reduce(
            status: "succeeded", signedIn: true,
            allowance: TranscriptAllowance(remaining: 0, isSubscribed: false)
        )
        #expect(ready.kind == .ready)
    }

    @Test("Ask AI stays off the menu until a transcript exists unless the policy says otherwise")
    func askAIPolicy() {
        var early = DetailTranscriptPolicy.current
        early.askAIOnlyWhenReady = false
        let content = DetailTranscriptState.reduce(
            status: nil, signedIn: true, allowance: free, policy: early
        )
        #expect(content.menu.map(\.action) == [.generate, .askAI])
        let ready = DetailTranscriptState.reduce(status: "succeeded", signedIn: true, allowance: nil)
        #expect(ready.menu.map(\.action) == [.read, .askAI])
    }

    // MARK: - Cache

    @Test("Allowance cache is per account and expires")
    func cacheFreshness() {
        let cache = TranscriptAllowanceCache(freshness: 60)
        let start = Date(timeIntervalSince1970: 1_000)
        let allowance = TranscriptAllowance(remaining: 7, isSubscribed: false)
        cache.store(allowance, uid: "user-a", now: start)
        #expect(cache.current(uid: "user-a", now: start.addingTimeInterval(59))?.remaining == 7)
        #expect(cache.current(uid: "user-a", now: start.addingTimeInterval(60)) == nil)
        cache.store(allowance, uid: "user-a", now: start)
        #expect(cache.current(uid: "user-b", now: start) == nil)
        cache.invalidate()
        #expect(cache.current(uid: "user-a", now: start) == nil)
    }

    @Test("Read transcript does not take over an episode that is already playing")
    func openPlanLeavesOtherEpisodePlaying() {
        let plan = TranscriptOpenPlan.make(
            enclosureURL: "https://x.example/this.mp3",
            currentURL: "https://x.example/other.mp3",
            isPlaying: true
        )
        #expect(plan == .browseWhileOtherPlays)
        #expect(!plan.requiresSuccessfulPrepare)
    }

    @Test("Read transcript loads a paused episode and stays on the current one")
    func openPlanWhenIdleOrCurrent() {
        let idle = TranscriptOpenPlan.make(
            enclosureURL: "https://x.example/this.mp3",
            currentURL: "https://x.example/other.mp3",
            isPlaying: false
        )
        #expect(idle == .loadWithoutPlaying)
        #expect(idle.requiresSuccessfulPrepare)

        let current = TranscriptOpenPlan.make(
            enclosureURL: "https://x.example/this.mp3",
            currentURL: "https://x.example/this.mp3",
            isPlaying: true
        )
        #expect(current == .showCurrent)
        #expect(!current.requiresSuccessfulPrepare)

        let nothing = TranscriptOpenPlan.make(
            enclosureURL: "https://x.example/this.mp3",
            currentURL: nil,
            isPlaying: false
        )
        #expect(nothing == .loadWithoutPlaying)
    }

    @Test("A failed prepare must not open the player")
    func prepareFailureBlocksPresent() {
        #expect(TranscriptOpenPlan.loadWithoutPlaying.requiresSuccessfulPrepare)
        #expect(!TranscriptOpenPlan.browseWhileOtherPlays.requiresSuccessfulPrepare)
        #expect(!TranscriptOpenPlan.showCurrent.requiresSuccessfulPrepare)
    }

    // MARK: - Row accessibility

    @Test("The row speaks the state's sentence and wraps only at accessibility sizes")
    func rowAccessibility() {
        let row = DetailTranscriptRow(frame: CGRect(x: 0, y: 0, width: 340, height: 52))
        row.apply(
            DetailTranscriptState.reduce(status: nil, signedIn: true, allowance: free),
            animated: false
        )
        #expect(row.accessibilityLabel == "AI transcript, 7 free left")
        #expect(row.accessibilityHint == "Double-tap to generate")
        #expect(row.accessibilityTraits.contains(.button))
        #expect(!row.usesMultilineLayout)

        row.apply(
            DetailTranscriptState.reduce(status: "processing", signedIn: true, allowance: free),
            animated: false
        )
        #expect(row.accessibilityLabel == "Generating transcript")
        #expect(row.accessibilityHint == "You can close this sheet")
        #expect(row.accessibilityTraits.contains(.staticText))
        #expect(!row.accessibilityTraits.contains(.button))

        row.apply(
            DetailTranscriptState.reduce(status: "succeeded", signedIn: true, allowance: nil),
            animated: false
        )
        #expect(row.accessibilityLabel == "Transcript ready")
        let names = (row.accessibilityCustomActions ?? []).map(\.name)
        #expect(names == ["Ask AI"])

        let ax = UITraitCollection(preferredContentSizeCategory: .accessibilityMedium)
        let xxxl = UITraitCollection(preferredContentSizeCategory: .extraExtraExtraLarge)
        #expect(DetailTranscriptRow.prefersMultilineLayout(ax))
        #expect(!DetailTranscriptRow.prefersMultilineLayout(xxxl))
    }
}
