import UIKit
import Testing
import AnycastKit
@testable import Anycast

/// The Search tab's entry state: which sections show for which data, that it
/// gives way to the results and comes back when the field is emptied or
/// cancelled, and that choosing a recent query submits it.
@MainActor
struct SearchEntryStateTests {

    private struct Failure: Error {}

    private func makeStore(_ recents: [String]) -> RecentSearchStore {
        let defaults = UserDefaults(suiteName: "SearchEntryStateTests-\(UUID().uuidString)")!
        let store = RecentSearchStore(defaults: defaults)
        for query in recents.reversed() { store.record(query) }
        return store
    }

    private func makeEntry(
        recents: [String], categories: Result<[String], Failure>
    ) async -> SearchEntryViewController {
        let entry = SearchEntryViewController(store: makeStore(recents), loadCategories: { try categories.get() })
        entry.loadViewIfNeeded()
        await Self.waitUntil { entry.categories.isEmpty == (categories.successValue?.isEmpty ?? true) }
        // Let the load's snapshot apply.
        try? await Task.sleep(for: .milliseconds(50))
        return entry
    }

    @Test("Recents and categories: both sections show, recents first")
    func bothSections() async {
        let entry = await makeEntry(recents: ["a", "b"], categories: .success(["News", "Arts"]))
        #expect(entry.sections == [.recentsHeader, .recents, .categoriesHeader, .categories])
        #expect(entry.recents == ["a", "b"])
        #expect(entry.categories == ["News", "Arts"])
    }

    @Test("Recents only: no categories section")
    func recentsOnly() async {
        let entry = await makeEntry(recents: ["a"], categories: .success([]))
        #expect(entry.sections == [.recentsHeader, .recents])
    }

    @Test("Categories only: no recents section")
    func categoriesOnly() async {
        let entry = await makeEntry(recents: [], categories: .success(["News"]))
        #expect(entry.sections == [.hint, .categoriesHeader, .categories])
    }

    @Test("A failed category load hides the section silently")
    func categoriesFailure() async {
        let entry = await makeEntry(recents: ["a"], categories: .failure(Failure()))
        try? await Task.sleep(for: .milliseconds(100))
        #expect(entry.sections == [.recentsHeader, .recents])
    }

    @Test("Neither: only the one-line hint")
    func neither() async {
        let entry = await makeEntry(recents: [], categories: .success([]))
        #expect(entry.sections == [.hint])
    }

    @Test("Choosing a recent or a category reports its text")
    func selectionReportsText() async {
        let entry = await makeEntry(recents: ["history of rome"], categories: .success(["News"]))
        var chosen: [String] = []
        entry.onSelect = { chosen.append($0) }
        entry.activate(.recent("history of rome"))
        entry.activate(.category("News"))
        entry.activate(.header(.recentsHeader))
        #expect(chosen == ["history of rome", "News"])
    }

    // MARK: - On the page

    @Test("The page shows the entry state until a query runs; a tapped recent submits and moves to the top")
    func pageTogglesAndSubmitsRecent() async {
        guard let context = await Self.liveUIContext() else { return }
        let store = makeStore(["first", "second"])
        let page = SearchPageViewController(
            context: context, recentStore: store, loadCategories: { ["News"] }
        )
        page.loadViewIfNeeded()
        #expect(!page.isShowingResults)
        #expect(!page.entryPage.view.isHidden)

        let script = ScriptedSearch(channels: .success([ScriptedSearch.channel("Second")]))
        page.setSearchTransport(
            channels: { @Sendable keyword in try await script.fetchChannels(keyword) },
            episodes: { @Sendable keyword in try await script.fetchEpisodes(keyword) }
        )
        page.entryPage.activate(.recent("second"))
        #expect(page.isShowingResults)
        #expect(page.entryPage.view.isHidden)
        await Self.waitUntil { store.queries == ["second", "first"] }
        #expect(store.queries == ["second", "first"])
    }

    @Test("Submitting a query records it once a segment returns a row")
    func searchRecordsQuery() async {
        guard let context = await Self.liveUIContext() else { return }
        let store = makeStore([])
        let script = ScriptedSearch(channels: .success([ScriptedSearch.channel("Planet Money")]))
        let page = SearchPageViewController(context: context, recentStore: store, loadCategories: { [] })
        page.setSearchTransport(
            channels: { @Sendable keyword in try await script.fetchChannels(keyword) },
            episodes: { @Sendable keyword in try await script.fetchEpisodes(keyword) }
        )
        page.loadViewIfNeeded()
        page.search("  Planet Money ")
        await Self.waitUntil { store.queries == ["Planet Money"] }
        #expect(store.queries == ["Planet Money"])
    }

    @Test("Emptying the field brings the entry state back; a non-empty edit keeps the results")
    func emptiedFieldReturnsToEntry() async {
        guard let context = await Self.liveUIContext() else { return }
        let page = SearchPageViewController(context: context, recentStore: makeStore([]), loadCategories: { [] })
        page.setSearchTransport(
            channels: { @Sendable (_: String) async throws -> [SubscriptionRow] in [] },
            episodes: { @Sendable (_: String) async throws -> [APIClient.EpisodeWithChannel] in [] }
        )
        page.loadViewIfNeeded()
        page.search("news")
        #expect(page.isShowingResults)

        let bar = UISearchBar()
        page.searchBar(bar, textDidChange: "new")
        #expect(page.isShowingResults)
        page.searchBar(bar, textDidChange: "  ")
        #expect(!page.isShowingResults)
        #expect(!page.entryPage.view.isHidden)
    }

    @Test("Cancelling the field (the search tab's Close) discards the query; the recent stays")
    func cancelReturnsToEntry() async {
        guard let context = await Self.liveUIContext() else { return }
        let store = makeStore([])
        let script = ScriptedSearch(channels: .success([ScriptedSearch.channel("news")]))
        let page = SearchPageViewController(context: context, recentStore: store, loadCategories: { [] })
        page.setSearchTransport(
            channels: { @Sendable keyword in try await script.fetchChannels(keyword) },
            episodes: { @Sendable keyword in try await script.fetchEpisodes(keyword) }
        )
        page.loadViewIfNeeded()
        page.search("news")
        await Self.waitUntil { store.queries == ["news"] }
        #expect(page.isShowingResults)

        // The system clears the bar's text only after this callback.
        let bar = UISearchBar()
        bar.text = "news"
        page.searchBarCancelButtonClicked(bar)
        #expect(!page.isShowingResults)
        #expect(!page.entryPage.view.isHidden)
        #expect(store.queries == ["news"])
    }

    // MARK: - Helpers

    private static func waitUntil(_ condition: @MainActor () -> Bool) async {
        for _ in 0..<250 {
            if condition() { return }
            try? await Task.sleep(for: .milliseconds(20))
        }
    }

    private static func liveUIContext() async -> UIContext? {
        for _ in 0..<40 {
            if let context = (UIApplication.shared.delegate as? AppDelegate)?.environment.uiContext {
                return context
            }
            try? await Task.sleep(for: .milliseconds(500))
        }
        return nil
    }
}

private extension Result {
    var successValue: Success? { try? get() }
}
