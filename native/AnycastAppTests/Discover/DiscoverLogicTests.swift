import UIKit
import Testing
import AnycastKit
@testable import Anycast

/// Discover + SearchPage pure logic (05 §6.3 Discover/Search P1 checklist):
/// category paging/keep-alive, country-change reload scope, per-page and
/// per-tab list phases, the UNGUARDED SearchPage add semantics (K13/K14
/// family), and the "moves to top" repository behavior the unguarded tap
/// relies on.
@MainActor
struct DiscoverLogicTests {

    // MARK: - Category paging / keep-alive (discover.dart:47-58)

    @Test("Initial selection materializes the page and both neighbors")
    func pagingInitialMaterialization() {
        var model = DiscoverPagingModel()
        let created = model.select(0, pageCount: 5)
        #expect(model.selectedIndex == 0)
        #expect(created == [0, 1])
        #expect(model.aliveIndices == [0, 1])
    }

    @Test("Selection materializes the target plus its neighbors, clamped at the edges")
    func pagingNeighborsClamped() {
        var model = DiscoverPagingModel()
        _ = model.select(3, pageCount: 5)
        #expect(model.selectedIndex == 3)
        #expect(model.aliveIndices == [2, 3, 4])

        // At the last page there is no right neighbor.
        var small = DiscoverPagingModel()
        let created = small.select(2, pageCount: 3)
        #expect(small.selectedIndex == 2)
        #expect(created == [1, 2])
        #expect(small.aliveIndices == [1, 2])
    }

    @Test("Out-of-range selection clamps instead of crashing")
    func pagingClamping() {
        var model = DiscoverPagingModel()
        _ = model.select(99, pageCount: 3)
        #expect(model.selectedIndex == 2)
        _ = model.select(-7, pageCount: 3)
        #expect(model.selectedIndex == 0)
        // Empty page set never materializes anything.
        var empty = DiscoverPagingModel()
        #expect(empty.select(0, pageCount: 0).isEmpty)
    }

    @Test("Keep-alive: alive pages never die and re-selection is a no-op")
    func pagingKeepAlive() {
        var model = DiscoverPagingModel()
        _ = model.select(0, pageCount: 5)
        _ = model.select(2, pageCount: 5)
        #expect(model.aliveIndices == [0, 1, 2, 3])
        // Returning to an alive page materializes nothing new.
        #expect(model.select(0, pageCount: 5).isEmpty)
        #expect(model.aliveIndices == [0, 1, 2, 3])
    }

    // MARK: - Country-change reload scope (discover.dart:59-64)

    @Test("Country change reloads EVERY alive page, not only the selected one")
    func countryReloadScope() {
        let alive: Set<Int> = [0, 1, 3]
        #expect(DiscoverCountryReload.reloadTargets(aliveIndices: alive) == alive)
        // The Dart Obx wraps each alive FutureBuilder; a page that never
        // displayed (never built) is not in the set at all.
        #expect(DiscoverCountryReload.reloadTargets(aliveIndices: []).isEmpty)
    }

    @Test("Country change skips never-displayed neighbors (Obx-alive = ever built)")
    func countryReloadSkipsUnbuilt() async {
        let viewModel = DiscoverViewModel(
            api: Self.unreachableAPI(),
            countryProvider: { "US" }
        )
        // Two categories: selecting 0 materializes pages 0 and 1, but only
        // page 0 has ever DISPLAYED (loaded).
        viewModel.categories = [
            APIClient.Category(name: "A", id: "a", imageURL: "", nightImageURL: ""),
            APIClient.Category(name: "B", id: "b", imageURL: "", nightImageURL: ""),
        ]
        _ = viewModel.selectCategory(0)
        viewModel.pages[0]?.loadIfNeeded(country: "US")
        #expect(viewModel.pages[0]?.hasLoaded == true)
        #expect(viewModel.pages[1]?.hasLoaded == false)

        await Self.waitUntil { await (viewModel.pages[0]?.isLoading == false) }

        viewModel.countryDidChange()
        // Page 0 reloads immediately; the never-displayed neighbor does not
        // start a fetch.
        #expect(viewModel.pages[0]?.isLoading == true)
        #expect(viewModel.pages[1]?.hasLoaded == false)
    }

    @Test("Country change reloads all ever-displayed pages, not just the current")
    func countryReloadsAllLoaded() async {
        let viewModel = DiscoverViewModel(
            api: Self.unreachableAPI(),
            countryProvider: { "US" }
        )
        viewModel.categories = (0..<3).map {
            APIClient.Category(name: "C\($0)", id: "c\($0)", imageURL: "", nightImageURL: "")
        }
        // Visit page 0, then page 2 — both displayed, selection rests on 2.
        _ = viewModel.selectCategory(0)
        viewModel.pages[0]?.loadIfNeeded(country: "US")
        await Self.waitUntil { await (viewModel.pages[0]?.isLoading == false) }
        _ = viewModel.selectCategory(2)
        viewModel.pages[2]?.loadIfNeeded(country: "US")
        await Self.waitUntil { await (viewModel.pages[2]?.isLoading == false) }
        #expect(viewModel.paging.selectedIndex == 2)

        viewModel.countryDidChange()
        // BOTH ever-displayed pages refetch (Obx rebuild), not just page 2.
        #expect(viewModel.pages[0]?.isLoading == true)
        #expect(viewModel.pages[2]?.isLoading == true)
        // Page 1 was only ever materialized as a neighbor — untouched.
        #expect(viewModel.pages[1]?.hasLoaded == false)
    }

    // MARK: - Page phases (discover.dart:60-101)

    @Test("Category page phase: loading wins; empty list and failure are Network Error")
    func pagePhaseReducer() {
        let row = SubscriptionRow(rssFeedUrl: "https://example.com/a.rss")
        // Loading dominates.
        #expect(DiscoverPageReducer.phase(isLoading: true, failed: false, channels: [row]) == .loading)
        #expect(DiscoverPageReducer.phase(isLoading: true, failed: true, channels: []) == .loading)
        // Loaded.
        #expect(
            DiscoverPageReducer.phase(isLoading: false, failed: false, channels: [row])
                == .loaded(rssURLs: ["https://example.com/a.rss"])
        )
        // Empty channels → the discover.dart:72-78 label.
        #expect(DiscoverPageReducer.phase(isLoading: false, failed: false, channels: []) == .networkError)
        // Fetch failure → same label (K4 fix instead of an eternal spinner).
        #expect(DiscoverPageReducer.phase(isLoading: false, failed: true, channels: []) == .networkError)
        #expect(DiscoverPageReducer.phase(isLoading: false, failed: true, channels: [row]) == .networkError)
    }

    @Test("Whole-page categories phase: loading; empty and failure are Network Error")
    func categoriesPhaseReducer() {
        let category = APIClient.Category(name: "Arts", id: "1", imageURL: "", nightImageURL: "")
        #expect(DiscoverCategoriesReducer.phase(isLoading: true, failed: false, categories: []) == .loading)
        #expect(
            DiscoverCategoriesReducer.phase(isLoading: false, failed: false, categories: [category])
                == .loaded(names: ["Arts"])
        )
        #expect(DiscoverCategoriesReducer.phase(isLoading: false, failed: false, categories: []) == .networkError)
        #expect(DiscoverCategoriesReducer.phase(isLoading: false, failed: true, categories: []) == .networkError)
    }

    // MARK: - Search list phases (discover.dart:169-293)

    @Test("Search list phase: loading / No results / loaded / Network Error")
    func searchListReducer() {
        #expect(SearchListReducer.phase(isLoading: true, failed: false, count: 0) == .loading)
        #expect(SearchListReducer.phase(isLoading: true, failed: true, count: 3) == .loading)
        #expect(SearchListReducer.phase(isLoading: false, failed: false, count: 0) == .noResults)
        #expect(SearchListReducer.phase(isLoading: false, failed: false, count: 12) == .loaded(count: 12))
        #expect(SearchListReducer.phase(isLoading: false, failed: true, count: 12) == .networkError)
        #expect(SearchListReducer.phase(isLoading: false, failed: true, count: 0) == .networkError)
    }

    @Test("SearchPageViewModel: both tabs surface the failure state (K4 fix)")
    func searchFailureStates() async {
        let viewModel = SearchPageViewModel(searchText: "query", api: Self.unreachableAPI())
        #expect(viewModel.searchText == "query")
        viewModel.search()
        #expect(viewModel.channelsPhase == .loading)
        #expect(viewModel.episodesPhase == .loading)

        await Self.waitUntil {
            viewModel.channelsPhase != .loading && viewModel.episodesPhase != .loading
        }
        #expect(viewModel.channelsPhase == .networkError)
        #expect(viewModel.episodesPhase == .networkError)
        #expect(viewModel.channels.isEmpty)
        #expect(viewModel.episodes.isEmpty)
    }

    // MARK: - Unguarded add semantics (03 §2.6 2026-09-22 correction)

    @Test("SearchPage add button: icon reflects membership, action is never gated")
    func searchAddButtonSemantics() {
        // Icon variant (Ic.round_playlist_add_check when in a playlist).
        #expect(SearchPageAddButton.icon(inPlaylist: false) == .add)
        #expect(SearchPageAddButton.icon(inPlaylist: true) == .added)
        // The tap is ungated by design — there is no action predicate on
        // this page (contrast the Channel pages, whose gate blocks members:
        // channel.dart:152-155 / 831-834).
        #expect(ChannelPlaylistGate.action(inPlaylist: true) == .blocked)
        #expect(ChannelPlaylistGate.action(inPlaylist: false) == .flyInAndInsert)
    }

    @Test("Unguarded add MOVES an existing episode toward the playlist top (K14)")
    func unguardedAddMovesToTop() async throws {
        let database = try await AppDatabase.openAt(
            URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent("discover-add-\(UUID().uuidString).sqlite3")
        )
        let repository = database.playlistRepository()
        let target = ChannelPlaylistLogic.defaultPlaylistID

        // A playlist with head and tail rows.
        let head = ChannelPlaylistLogic.playlistRow(
            from: FeedEpisodeRow(title: "head", enclosureUrl: "head.mp3"), playlistId: target
        )
        let tail = ChannelPlaylistLogic.playlistRow(
            from: FeedEpisodeRow(title: "tail", enclosureUrl: "tail.mp3"), playlistId: target
        )
        try await repository.insertOrUpdateByIndex(head, playlistId: target, index: 0)
        try await repository.insertOrUpdateByIndex(tail, playlistId: target, index: 1)
        var order = try await repository.listEpisodes(playlistId: target)
        #expect(order.map(\.enclosureUrl) == ["head.mp3", "tail.mp3"])

        // The SearchPage add path: NOT the current playlist → insertion
        // index 0; the row already exists → insertOrUpdateByIndex MOVES it.
        let index = ChannelPlaylistLogic.addToPlaylistIndex(
            currentPlaylistId: nil,
            targetPlaylistId: target,
            currentEnclosureURL: nil,
            episodeEnclosureURL: "tail.mp3"
        )
        #expect(index == 0)
        try await repository.insertOrUpdateByIndex(tail, playlistId: target, index: index!)
        order = try await repository.listEpisodes(playlistId: target)
        #expect(order.map(\.enclosureUrl) == ["tail.mp3", "head.mp3"])

        // While playlist 1 IS the current playlist, the add lands UNDER the
        // playing head (slot 1) — the moved row ends up second.
        let indexUnderHead = ChannelPlaylistLogic.addToPlaylistIndex(
            currentPlaylistId: target,
            targetPlaylistId: target,
            currentEnclosureURL: "head.mp3",
            episodeEnclosureURL: "tail.mp3"
        )
        #expect(indexUnderHead == 1)
    }

    // MARK: - Helpers

    /// An API client whose host can never resolve — deterministic failure
    /// without touching the network contract servers.
    private static func unreachableAPI() -> APIClient {
        APIClient(
            host: URL(string: "https://anycast.invalid")!,
            client: HTTPClient(),
            tokenProvider: { nil }
        )
    }

    /// Polls the MainActor condition until true (10 s deadline) — the view
    /// models settle their Tasks asynchronously.
    private static func waitUntil(_ condition: @MainActor () async -> Bool) async {
        for _ in 0..<500 {
            if await condition() { return }
            try? await Task.sleep(for: .milliseconds(20))
        }
    }
}
