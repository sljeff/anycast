import UIKit
import Testing
@testable import Anycast

/// The Search tab's entry state: which sections show for which data, that it
/// gives way to the results, and that choosing a recent query submits it.
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
        #expect(entry.sections == [.categoriesHeader, .categories])
    }

    @Test("A failed category load hides the section silently")
    func categoriesFailure() async {
        let entry = await makeEntry(recents: ["a"], categories: .failure(Failure()))
        try? await Task.sleep(for: .milliseconds(100))
        #expect(entry.sections == [.recentsHeader, .recents])
    }

    @Test("Neither: the page is empty")
    func neither() async {
        let entry = await makeEntry(recents: [], categories: .success([]))
        #expect(entry.sections.isEmpty)
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

        page.entryPage.activate(.recent("second"))
        #expect(page.isShowingResults)
        #expect(page.entryPage.view.isHidden)
        #expect(store.queries == ["second", "first"])
    }

    @Test("Submitting a query records it")
    func searchRecordsQuery() async {
        guard let context = await Self.liveUIContext() else { return }
        let store = makeStore([])
        let page = SearchPageViewController(context: context, recentStore: store, loadCategories: { [] })
        page.loadViewIfNeeded()
        page.search("  Planet Money ")
        #expect(store.queries == ["Planet Money"])
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
