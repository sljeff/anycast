import Foundation
import Observation
import AnycastKit

// MARK: - Pure reducers (lib/pages/discover.dart, 05 §6.3 P1)

/// Display phase of one category page (discover.dart:60-101).
enum DiscoverPagePhase: Equatable {
    case loading
    case loaded(rssURLs: [String])
    /// Centered white "Network Error" (discover.dart:72-78): shown for an
    /// EMPTY channel list, and for a failed fetch — the K4 crash-family fix
    /// (the Dart FutureBuilder would spin forever on a thrown future).
    case networkError
}

enum DiscoverPageReducer {
    static func phase(
        isLoading: Bool,
        failed: Bool,
        channels: [SubscriptionRow]
    ) -> DiscoverPagePhase {
        if isLoading { return .loading }
        if failed || channels.isEmpty { return .networkError }
        return .loaded(rssURLs: channels.compactMap(\.rssFeedUrl))
    }
}

/// Display phase of the whole-page category fetch (discover.dart:38-46).
/// A failed OR empty category list renders the same centered error label.
enum DiscoverCategoriesPhase: Equatable {
    case loading
    case loaded(names: [String])
    case networkError
}

enum DiscoverCategoriesReducer {
    static func phase(
        isLoading: Bool,
        failed: Bool,
        categories: [APIClient.Category]
    ) -> DiscoverCategoriesPhase {
        if isLoading { return .loading }
        if failed || categories.isEmpty { return .networkError }
        return .loaded(names: categories.map(\.name))
    }
}

/// Search tab list phase (discover.dart:169-204 / 204-293): loading spinner;
/// empty results → "No results"; a failed fetch → the error label instead
/// of the Dart eternal spinner (K4 fix).
enum SearchListPhase: Equatable {
    case loading
    case noResults
    case loaded(count: Int)
    case networkError
}

enum SearchListReducer {
    static func phase(isLoading: Bool, failed: Bool, count: Int) -> SearchListPhase {
        if isLoading { return .loading }
        if failed { return .networkError }
        if count == 0 { return .noResults }
        return .loaded(count: count)
    }
}

// MARK: - Category paging (KeepAliveWrapper parity)

/// Category tab selection plus keep-alive bookkeeping (discover.dart:57):
/// a page materializes on first display and NEVER dies afterwards.
/// Selecting an index materializes it AND its two neighbors — the Flutter
/// PageView builds adjacent pages while they are still draggable, so a
/// swipe always lands on an already-live page.
struct DiscoverPagingModel: Equatable {
    private(set) var selectedIndex = 0
    private(set) var aliveIndices: Set<Int> = []

    /// Selects (clamped) and returns the indices that materialized now.
    mutating func select(_ index: Int, pageCount: Int) -> [Int] {
        guard pageCount > 0 else { return [] }
        let clamped = min(max(index, 0), pageCount - 1)
        selectedIndex = clamped
        return materialize([clamped, clamped - 1, clamped + 1], pageCount: pageCount)
    }

    /// Marks the given indices alive (bounds-checked); returns the newly
    /// materialized subset in ascending order.
    mutating func materialize(_ indices: [Int], pageCount: Int) -> [Int] {
        var created: [Int] = []
        for index in indices.sorted()
        where (0..<pageCount).contains(index) && !aliveIndices.contains(index) {
            aliveIndices.insert(index)
            created.append(index)
        }
        return created
    }
}

/// Country-change reload scope. Dart wraps EVERY alive category page in its
/// own `Obx(() => FutureBuilder(... countryCode.value))`
/// (discover.dart:59-64) — a change re-runs every alive builder at once, so
/// ALL alive pages refetch immediately, not only the selected one.
enum DiscoverCountryReload {
    static func reloadTargets(aliveIndices: Set<Int>) -> Set<Int> { aliveIndices }
}

// MARK: - SearchPage add button (03 §2.6, 2026-09-22 correction)

/// SearchPage's add-to-playlist button (discover.dart:276-286): the icon
/// reflects playlist membership, but the tap is NOT gated — this page has no
/// `if (inPlaylist) return` guard (that guard exists ONLY on Channel /
/// ChannelSearch, channel.dart:152-155 / 831-834). Every tap fires the
/// fly-in animation and then inserts/moves via addToPlaylist (contrast
/// `ChannelPlaylistGate.action(inPlaylist:)`, which returns `.blocked` for
/// members).
enum SearchPageAddButton {

    enum Icon: Equatable {
        case add
        /// Ic.round_playlist_add_check — the already-in-playlist variant.
        case added
    }

    static func icon(inPlaylist: Bool) -> Icon { inPlaylist ? .added : .add }
}

// MARK: - View models

/// One category's channel list — the per-page FutureBuilder
/// (discover.dart:57-103). Instances live for the tab's lifetime
/// (KeepAliveWrapper); a reload replaces the list in place. The fetch
/// starts on FIRST display (Flutter builds a page only when it scrolls
/// into view), which is what `hasLoaded` tracks — the Dart Obx country
/// rebuild then re-runs every page that was ever built.
@MainActor
@Observable
final class DiscoverCategoryPageModel {

    let categoryID: String
    /// True once the first fetch has been requested — the Obx-alive marker
    /// for country-change reloads.
    private(set) var hasLoaded = false
    private(set) var isLoading = true
    private(set) var failed = false
    private(set) var channels: [SubscriptionRow] = []

    private var generation = 0
    private let api: APIClient

    init(categoryID: String, api: APIClient) {
        self.categoryID = categoryID
        self.api = api
    }

    var phase: DiscoverPagePhase {
        DiscoverPageReducer.phase(isLoading: isLoading, failed: failed, channels: channels)
    }

    /// First display starts the fetch; later calls are explicit reloads
    /// (country change) and never re-trigger off display alone.
    func loadIfNeeded(country: String) {
        guard !hasLoaded else { return }
        load(country: country)
    }

    /// `listChannelsByCategoryId(id, country)`; a newer call supersedes any
    /// in-flight one (the Dart Obx rebuild discards the old future's result
    /// by rebuilding the FutureBuilder).
    func load(country: String) {
        hasLoaded = true
        generation += 1
        let generation = generation
        isLoading = true
        failed = false
        let api = self.api
        let categoryID = self.categoryID
        Task { [weak self] in
            var fetched: [SubscriptionRow]?
            do {
                fetched = try await api.listChannels(categoryID: categoryID, country: country)
            } catch {
                fetched = nil
            }
            guard let self, self.generation == generation else { return }
            if let channels = fetched {
                // data:null → [] is a valid empty answer (02 §1.2) → the
                // "Network Error" empty state (discover.dart:72-78).
                self.channels = channels
                self.failed = false
            } else {
                self.channels = []
                self.failed = true
            }
            self.isLoading = false
        }
    }
}

/// The Discover tab state (discover.dart:33-111): the category fetch, the
/// paging/keep-alive bookkeeping, and the per-category page models.
@MainActor
@Observable
final class DiscoverViewModel {

    /// Internal-set for test injection; production writes flow through
    /// `loadCategories` only.
    var categories: [APIClient.Category] = []
    private(set) var categoriesLoading = true
    private(set) var categoriesFailed = false
    private(set) var paging = DiscoverPagingModel()
    private(set) var pages: [Int: DiscoverCategoryPageModel] = [:]

    private let api: APIClient
    private let countryProvider: () -> String

    init(api: APIClient, countryProvider: @escaping () -> String) {
        self.api = api
        self.countryProvider = countryProvider
    }

    var categoriesPhase: DiscoverCategoriesPhase {
        DiscoverCategoriesReducer.phase(
            isLoading: categoriesLoading,
            failed: categoriesFailed,
            categories: categories
        )
    }

    var currentCountry: String { countryProvider() }

    /// `listCategories()` (discover.dart:38). The shell prewarms the tab at
    /// launch, so this fires from viewDidLoad — the IndexedStack parity.
    func loadCategories() {
        categoriesLoading = true
        categoriesFailed = false
        let api = self.api
        Task { [weak self] in
            var fetched: [APIClient.Category]?
            do {
                fetched = try await api.listCategories()
            } catch {
                fetched = nil
            }
            guard let self else { return }
            if let categories = fetched {
                self.categories = categories
                self.categoriesFailed = false
            } else {
                self.categories = []
                self.categoriesFailed = true
            }
            self.categoriesLoading = false
            self.buildPagesIfNeeded()
        }
    }

    /// Selects a category (tab tap, swipe settle, or mid-drag scrub): the
    /// selection materializes its page models plus the neighbors (so a drag
    /// lands on live pages) and starts the SELECTED page's first fetch —
    /// the Flutter PageView builds exactly the page it shows. Returns the
    /// NEW indices for the caller to install view controllers for.
    func selectCategory(_ index: Int) -> [Int] {
        let created = paging.select(index, pageCount: categories.count)
        for index in created {
            pages[index] = DiscoverCategoryPageModel(
                categoryID: categories[index].id,
                api: api
            )
        }
        if let selected = pages[paging.selectedIndex] {
            selected.loadIfNeeded(country: currentCountry)
        }
        return created
    }

    /// Country change (discover.dart:59-64): every page whose Obx is alive
    /// (ever built) refetches with the new code immediately — not just the
    /// selected one.
    func countryDidChange() {
        let country = currentCountry
        for index in DiscoverCountryReload.reloadTargets(aliveIndices: paging.aliveIndices) {
            guard let page = pages[index], page.hasLoaded else { continue }
            page.load(country: country)
        }
    }

    private func buildPagesIfNeeded() {
        guard !categories.isEmpty, pages.isEmpty else { return }
        _ = selectCategory(0)
    }
}

/// The global SearchPage state (discover.dart:113-306): the two tab
/// searches, each (re)started by its tab's first display or revisit (the
/// TabBarView children carry no KeepAliveWrapper, 03 §2.6/§3.5).
@MainActor
@Observable
final class SearchPageViewModel {

    let searchText: String

    private(set) var channels: [SubscriptionRow] = []
    private(set) var episodes: [APIClient.EpisodeWithChannel] = []
    private(set) var channelsLoading = true
    private(set) var channelsFailed = false
    private(set) var episodesLoading = true
    private(set) var episodesFailed = false

    /// Monotonic per list: a newer search of the same list supersedes any
    /// in-flight one — an older response must never clobber it (same ruling
    /// as `DiscoverCategoryPageModel.load`).
    private var channelsGeneration = 0
    private var episodesGeneration = 0

    private let api: APIClient

    init(searchText: String, api: APIClient) {
        self.searchText = searchText
        self.api = api
    }

    var channelsPhase: SearchListPhase {
        SearchListReducer.phase(
            isLoading: channelsLoading, failed: channelsFailed, count: channels.count
        )
    }

    var episodesPhase: SearchListPhase {
        SearchListReducer.phase(
            isLoading: episodesLoading, failed: episodesFailed, count: episodes.count
        )
    }

    /// searchChannels + searchEpisodes in parallel (discover.dart:170 / 205).
    func search() {
        searchChannels()
        searchEpisodes()
    }

    /// The SearchPage TabBarView children carry NO KeepAliveWrapper — each
    /// (re)visit rebuilds that tab's FutureBuilder and re-runs its future
    /// (discover.dart:167-293). The sheet opens on Channels, so the channels
    /// search is the launch fetch; the episodes search runs on first (and
    /// every later) visit of the Episodes tab.
    func activate(tab index: Int) {
        if index == 1 {
            searchEpisodes()
        } else {
            searchChannels()
        }
    }

    private func searchChannels() {
        channelsLoading = true
        channelsFailed = false
        channelsGeneration += 1
        let generation = channelsGeneration
        let api = self.api
        let keyword = searchText
        Task { [weak self] in
            var fetched: [SubscriptionRow]?
            do {
                fetched = try await api.searchChannels(keyword: keyword)
            } catch {
                fetched = nil
            }
            guard let self, self.channelsGeneration == generation else { return }
            if let channels = fetched {
                self.channels = channels
                self.channelsFailed = false
            } else {
                self.channels = []
                self.channelsFailed = true
            }
            self.channelsLoading = false
        }
    }

    private func searchEpisodes() {
        episodesLoading = true
        episodesFailed = false
        episodesGeneration += 1
        let generation = episodesGeneration
        let api = self.api
        let keyword = searchText
        Task { [weak self] in
            var fetched: [APIClient.EpisodeWithChannel]?
            do {
                fetched = try await api.searchEpisodes(keyword: keyword)
            } catch {
                fetched = nil
            }
            guard let self, self.episodesGeneration == generation else { return }
            // The Dart `episodes[index].episode!` force-unwrap (K4 family)
            // never trips: malformed rows were already compactMapped away.
            if let episodes = fetched {
                self.episodes = episodes
                self.episodesFailed = false
            } else {
                self.episodes = []
                self.episodesFailed = true
            }
            self.episodesLoading = false
        }
    }
}
