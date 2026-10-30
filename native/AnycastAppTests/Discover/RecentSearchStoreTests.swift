import Foundation
import Testing
@testable import Anycast

/// The Search tab's recent queries: order, cap, case-insensitive de-duplication,
/// trimming, deletion and tolerance of a malformed stored value.
struct RecentSearchStoreTests {

    private func makeStore() -> (store: RecentSearchStore, defaults: UserDefaults) {
        let defaults = UserDefaults(suiteName: "RecentSearchStoreTests-\(UUID().uuidString)")!
        return (RecentSearchStore(defaults: defaults), defaults)
    }

    @Test("Starts empty and lists the most recent query first")
    func orderIsMostRecentFirst() {
        let (store, _) = makeStore()
        #expect(store.queries.isEmpty)
        store.record("one")
        store.record("two")
        store.record("three")
        #expect(store.queries == ["three", "two", "one"])
    }

    @Test("Keeps at most eight, dropping the oldest")
    func capsAtEight() {
        let (store, _) = makeStore()
        for index in 1...10 { store.record("q\(index)") }
        #expect(store.queries == ["q10", "q9", "q8", "q7", "q6", "q5", "q4", "q3"])
        #expect(store.queries.count == RecentSearchStore.limit)
    }

    @Test("A repeat moves to the front, ignoring case, and keeps the new spelling")
    func dedupesIgnoringCase() {
        let (store, _) = makeStore()
        store.record("Radiolab")
        store.record("serial")
        store.record("radiolab")
        #expect(store.queries == ["radiolab", "serial"])
    }

    @Test("Queries are trimmed and empty ones are ignored")
    func trimsAndIgnoresEmpty() {
        let (store, _) = makeStore()
        store.record("  The Daily \n")
        store.record("   ")
        store.record("")
        #expect(store.queries == ["The Daily"])
        store.record("the daily")
        #expect(store.queries == ["the daily"])
    }

    @Test("Removes one entry (ignoring case) or clears all")
    func removeAndClear() {
        let (store, _) = makeStore()
        store.record("a")
        store.record("B")
        store.record("c")
        store.remove("b")
        #expect(store.queries == ["c", "a"])
        store.remove("missing")
        #expect(store.queries == ["c", "a"])
        store.clear()
        #expect(store.queries.isEmpty)
    }

    @Test("A missing or malformed stored value reads as empty")
    func garbageDecodesToEmpty() {
        let (store, defaults) = makeStore()
        defaults.set("not an array", forKey: RecentSearchStore.key)
        #expect(store.queries.isEmpty)
        defaults.set([1, 2, 3], forKey: RecentSearchStore.key)
        #expect(store.queries.isEmpty)
        defaults.set(["mixed", 7] as [Any], forKey: RecentSearchStore.key)
        #expect(store.queries.isEmpty)
        // Recording over garbage starts a clean list.
        store.record("fresh")
        #expect(store.queries == ["fresh"])
    }

    @Test("Persists under the documented key as a string array")
    func persistsUnderKey() {
        let (store, defaults) = makeStore()
        store.record("one")
        #expect(RecentSearchStore.key == "search.recentQueries")
        #expect(defaults.array(forKey: RecentSearchStore.key) as? [String] == ["one"])
    }
}
