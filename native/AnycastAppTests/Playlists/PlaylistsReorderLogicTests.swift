import Testing
import AnycastKit
@testable import Anycast

/// The drag-reorder decision core (states/playlist_episode.dart:93-122,
/// 05 §11 K26, 05 §6.3 P0): final-coordinate from/to → repository
/// gesture-space index, index-0 source-swap trigger, and the ordered
/// pause-then-swap playback steps.
@MainActor
struct PlaylistsReorderLogicTests {

    private let abc = ["a", "b", "c", "d"]

    // MARK: - Index translation (the Dart `to -= 1` adjustment, inverted)

    @Test("Upward move keeps its index in gesture space")
    func upwardMove() {
        let outcome = PlaylistReorderLogic.moveOutcome(from: 2, to: 0, urls: abc)!
        #expect(outcome.repositoryIndex == 0)
        #expect(outcome.finalIndex == 0)
        #expect(outcome.reorderedURLs == ["c", "a", "b", "d"])
        #expect(outcome.newHeadEnclosureURL == "c")
    }

    @Test("Downward move's gesture target sits one past the final slot")
    func downwardMove() {
        // Final to=2 from=1: Dart saw gesture to=3 and adjusted to 2.
        let outcome = PlaylistReorderLogic.moveOutcome(from: 1, to: 2, urls: abc)!
        #expect(outcome.repositoryIndex == 3)
        #expect(outcome.finalIndex == 2)
        #expect(outcome.reorderedURLs == ["a", "c", "b", "d"])
        #expect(outcome.newHeadEnclosureURL == "a")
    }

    @Test("to > from at the list tail clamps like PlaylistPositioning")
    func tailClamp() {
        let outcome = PlaylistReorderLogic.moveOutcome(from: 0, to: 3, urls: abc)!
        #expect(outcome.reorderedURLs == ["b", "c", "d", "a"])
        #expect(outcome.finalIndex == 3)
        #expect(outcome.repositoryIndex == 4)   // clamped inside movePosition
    }

    @Test("from == to is a no-op (Dart early return), including 0→0")
    func sameIndex() {
        #expect(PlaylistReorderLogic.moveOutcome(from: 0, to: 0, urls: abc) == nil)
        #expect(PlaylistReorderLogic.moveOutcome(from: 2, to: 2, urls: abc) == nil)
        #expect(PlaylistReorderLogic.moveOutcome(from: 9, to: 0, urls: abc) == nil)
    }

    // MARK: - Index-0 swap trigger (03 §3.2 / 05 §6.3 P0)

    @Test("Dragging the head away swaps the source")
    func dragHeadAway() {
        let outcome = PlaylistReorderLogic.moveOutcome(from: 0, to: 2, urls: abc)!
        #expect(outcome.swapsPlaybackSource)
        #expect(outcome.newHeadEnclosureURL == "b")
    }

    @Test("Dragging a new item to the top swaps the source")
    func dragToTop() {
        let outcome = PlaylistReorderLogic.moveOutcome(from: 2, to: 0, urls: abc)!
        #expect(outcome.swapsPlaybackSource)
        #expect(outcome.newHeadEnclosureURL == "c")
    }

    @Test("Moves not involving index 0 never swap")
    func interiorMovesDoNotSwap() {
        #expect(PlaylistReorderLogic.moveOutcome(from: 1, to: 2, urls: abc)!.swapsPlaybackSource == false)
        #expect(PlaylistReorderLogic.moveOutcome(from: 3, to: 1, urls: abc)!.swapsPlaybackSource == false)
    }

    // MARK: - Playback steps (pause → setByEpisode(new head), 08 §11.4)

    @Test("Source swap is an ordered pause-then-set on the POST-reorder head")
    func playbackStepOrder() {
        let away = PlaylistReorderLogic.moveOutcome(from: 0, to: 2, urls: abc)!
        #expect(PlaylistReorderLogic.playbackSteps(
            swapsPlaybackSource: away.swapsPlaybackSource,
            newHeadEnclosureURL: away.newHeadEnclosureURL
        ) == [.pausePlayback, .setSource("b")])

        let toTop = PlaylistReorderLogic.moveOutcome(from: 2, to: 0, urls: abc)!
        #expect(PlaylistReorderLogic.playbackSteps(
            swapsPlaybackSource: toTop.swapsPlaybackSource,
            newHeadEnclosureURL: toTop.newHeadEnclosureURL
        ) == [.pausePlayback, .setSource("c")])

        // No index-0 involvement → no steps; empty head guards too.
        let interior = PlaylistReorderLogic.moveOutcome(from: 1, to: 2, urls: abc)!
        #expect(PlaylistReorderLogic.playbackSteps(
            swapsPlaybackSource: interior.swapsPlaybackSource,
            newHeadEnclosureURL: interior.newHeadEnclosureURL
        ) == [])
        #expect(PlaylistReorderLogic.playbackSteps(swapsPlaybackSource: true, newHeadEnclosureURL: nil) == [])
    }

    // MARK: - From/to recovery from the diffable snapshot

    @Test("fromTo derives final coordinates from before/after lists")
    func fromToDerivation() {
        let before = ["a", "b", "c", "d"]
        let after = ["b", "c", "a", "d"]   // a: 0 → 2
        let pair = PlaylistReorderLogic.fromTo(movedURL: "a", before: before, after: after)
        #expect(pair?.from == 0)
        #expect(pair?.to == 2)
        #expect(PlaylistReorderLogic.fromTo(movedURL: "a", before: before, after: before) == nil)
    }

    @Test("movedIndex finds the single changed item")
    func movedIndexFinder() {
        #expect(PlaylistEpisodeListViewController.movedIndex(
            before: ["a", "b", "c"], after: ["c", "a", "b"]
        )?.to == 0)
        #expect(PlaylistEpisodeListViewController.movedIndex(
            before: ["a", "b", "c"], after: ["a", "b", "c"]
        ) == nil)
        #expect(PlaylistEpisodeListViewController.movedIndex(
            before: ["a", "b"], after: ["a"]
        ) == nil)
    }

    @Test("reorderedRows mirrors the URL math")
    func rowReordering() {
        let rows = abc.map { PlaylistEpisodeRow(enclosureUrl: $0, playlistId: 1) }
        let moved = PlaylistReorderLogic.reorderedRows(rows, from: 0, to: 2)!
        #expect(moved.map(\.enclosureUrl) == ["b", "c", "a", "d"])
        #expect(PlaylistReorderLogic.reorderedRows(rows, from: 1, to: 1) == nil)
    }

    // MARK: - Repository convention pin (K26)

    @Test("repositoryIndex + PlaylistPositioning land the item at finalIndex")
    func repositoryConvention() {
        // movePosition takes POST-move neighbors (K26), so on an evenly
        // spaced 0…n-1 list the assigned position is the midpoint of the
        // final slot's new neighbors (or ±3·gap at the edges) — NOT slot k's
        // old value k. What must hold: ordering by the assigned position
        // places the moved item at exactly finalIndex in reorderedURLs.
        let cases: [(from: Int, to: Int, expected: Double)] = [
            (0, 2, 2.5),                                    // between 2 and 3
            (2, 0, 0 - PlaylistPositioning.minPositionGap * 3),
            (1, 2, 2.5),                                    // between 2 and 3
            (3, 1, 0.5),                                    // between 0 and 1
            (0, 3, 3 + PlaylistPositioning.minPositionGap * 3),
            (2, 3, 3 + PlaylistPositioning.minPositionGap * 3),
        ]
        for testCase in cases {
            guard let outcome = PlaylistReorderLogic.moveOutcome(
                from: testCase.from, to: testCase.to, urls: abc
            ) else {
                Issue.record("move \(testCase) unexpectedly nil")
                continue
            }
            let positions: [Double?] = abc.indices.map(Double.init)
            let result = PlaylistPositioning.movePosition(
                from: testCase.from, to: outcome.repositoryIndex, orderedPositions: positions
            )
            #expect(!result.needsReorder)
            #expect(result.position == testCase.expected)
            // K26 outcome: keep every other row's position, give the moved
            // row the computed one — position order == reorderedURLs order.
            var postMove = positions
            postMove.remove(at: testCase.from)
            postMove.insert(result.position, at: outcome.finalIndex)
            let orderedByPosition = zip(outcome.reorderedURLs, postMove)
                .sorted { $0.1! < $1.1! }
                .map(\.0)
            #expect(orderedByPosition == outcome.reorderedURLs)
        }
    }
}
