import Foundation
import Testing
import AnycastKit
@testable import Anycast

/// The 60-second overage trim decision (states/feed_episode.dart:134-147
/// removeOld + states/history.dart:54-67, driven from
/// states/player.dart:344-349): rows arrive newest-first (pubDate DESC);
/// keep the first `max`, drop the overage. Boundary: count == max removes
/// nothing.
@MainActor
struct FeedsTrimTests {

    @Test("Under the limit removes nothing")
    func underLimit() {
        let plan = InboxTrimPlanner.plan(count: 5, keeping: 100)
        #expect(!plan.removesAnything)
        #expect(plan.removedCount == 0)
    }

    @Test("Exactly at the limit removes nothing (boundary)")
    func atLimit() {
        let plan = InboxTrimPlanner.plan(count: 100, keeping: 100)
        #expect(!plan.removesAnything)
        #expect(plan.removedCount == 0)
    }

    @Test("Overage removes exactly count - max, the oldest rows")
    func overage() {
        let plan = InboxTrimPlanner.plan(count: 105, keeping: 100)
        #expect(plan.removesAnything)
        #expect(plan.removedCount == 5)
        #expect(plan.removedIndices == 100..<105)
    }

    @Test("A tightened limit trims down to it")
    func tightenedLimit() {
        let plan = InboxTrimPlanner.plan(count: 300, keeping: 50)
        #expect(plan.removedCount == 250)
        #expect(plan.removedIndices == 50..<300)
    }

    @Test("Max zero removes everything")
    func maxZero() {
        let plan = InboxTrimPlanner.plan(count: 4, keeping: 0)
        #expect(plan.removedCount == 4)
        #expect(plan.removedIndices == 0..<4)
    }

    @Test("URL extraction from the planned range; nil enclosureUrls are skipped, not crashed on")
    func urlExtraction() {
        // Newest-first list: index 0 newest … index 4 oldest; max 3 → drop 3..<5.
        let episodes = [
            FeedEpisodeRow(enclosureUrl: "a"),
            FeedEpisodeRow(enclosureUrl: "b"),
            FeedEpisodeRow(enclosureUrl: "c"),
            FeedEpisodeRow(enclosureUrl: nil),   // Dart `episode.enclosureUrl!` crash family (K4)
            FeedEpisodeRow(enclosureUrl: "e"),
        ]
        let plan = InboxTrimPlanner.plan(count: episodes.count, keeping: 3)
        #expect(plan.removedIndices == 3..<5)
        let urls = episodes[plan.removedIndices].compactMap(\.enclosureUrl)
        #expect(urls == ["e"])
    }
}
