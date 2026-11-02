import UIKit
import Testing
import AnycastKit
@testable import Anycast

/// Copy, the single next step, when a query is saved to Recent, and the
/// rule that a segment already loaded in this search is not fetched again.
@MainActor
struct SearchResultStateTests {

    private struct Failure: Error {}

    // MARK: - Echo

    @Test("Short queries are quoted whole, including case and surrounding spaces")
    func echoKeepsShortQueries() {
        let echo = SearchResultState.echoedQuery("  DeCoDeR \n")
        #expect(echo.visible == "DeCoDeR")
        #expect(echo.spoken == "DeCoDeR")
        #expect(SearchResultState.searchingAnnouncement(query: "  decoder ") == "Searching for decoder")
    }

    @Test("A query of 60 characters is not shortened; 61 drops the middle")
    func echoTruncatesPastSixty() {
        let sixty = String(repeating: "a", count: 60)
        #expect(SearchResultState.echoedQuery(sixty).visible == sixty)

        var characters = Array(repeating: Character("a"), count: 61)
        characters[40] = "Z"
        characters[45] = "Q"
        let sixtyOne = String(characters)
        let echo = SearchResultState.echoedQuery(sixtyOne)
        #expect(echo.spoken == sixtyOne)
        #expect(echo.visible == String(sixtyOne.prefix(40)) + "…" + String(sixtyOne.suffix(15)))
        #expect(!echo.visible.contains("Z"))
        #expect(!echo.visible.contains("Q"))
        #expect(echo.visible.count == 40 + 1 + 15)
    }

    @Test("Chinese characters and emoji each count as one character")
    func echoCountsExtendedGraphemes() {
        let chinese = String(repeating: "字", count: 61)
        let echo = SearchResultState.echoedQuery(chinese)
        #expect(echo.visible == String(repeating: "字", count: 40) + "…" + String(repeating: "字", count: 15))

        let emoji = String(repeating: "😀", count: 61)
        let emojiEcho = SearchResultState.echoedQuery(emoji)
        #expect(emojiEcho.spoken.count == 61)
        #expect(emojiEcho.visible.hasPrefix(String(repeating: "😀", count: 40) + "…"))
        #expect(emojiEcho.visible.hasSuffix(String(repeating: "😀", count: 15)))
    }

    // MARK: - Sentences

    @Test("Each result state has one sentence and at most one action")
    func stateMatrix() {
        let query = "xyzqqqnotaword123"
        let unknown: [SearchListPhase] = [.loading, .loaded(count: 4), .networkError]

        for other in unknown {
            let channels = presentation(.channels, .noResults, other, query)
            #expect(channels?.title == "No channels for “\(query)”")
            #expect(channels?.spokenTitle == "No channels for “\(query)”")
            #expect(channels?.title.hasPrefix("No channels for “") == true)
            #expect(channels?.action == .showOtherSegment)
            #expect(channels?.actionTitle == "Show episodes")
            #expect(channels?.actionAccessibilityLabel == "Show episodes for \(query)")
            #expect(channels?.showsButton == true)

            let episodes = presentation(.episodes, .noResults, other, query)
            #expect(episodes?.title == "No episodes for “\(query)”")
            #expect(episodes?.spokenTitle == "No episodes for “\(query)”")
            #expect(episodes?.action == .showOtherSegment)
            #expect(episodes?.actionTitle == "Show channels")
            #expect(episodes?.actionAccessibilityLabel == "Show channels for \(query)")
        }

        let both = presentation(.episodes, .noResults, .noResults, query)
        #expect(both?.title == "Nothing found for “\(query)”. Try another word.")
        #expect(both?.spokenTitle == "Nothing found for “\(query)”. Try another word.")
        #expect(both?.title.hasSuffix(". Try another word.") == true)
        #expect(both?.title.contains("\u{200B}") == false)
        #expect(both?.action == .focusSearchField)
        #expect(both?.showsButton == false)
        #expect(presentation(.channels, .noResults, .noResults, query) == both)

        let failed = presentation(.channels, .networkError, .noResults, "decoder")
        #expect(failed?.title == "Couldn’t load results for “decoder”")
        #expect(failed?.title.contains("\u{2019}") == true)
        #expect(failed?.action == .retry)
        #expect(failed?.actionTitle == "Retry")
        #expect(failed?.actionAccessibilityLabel == "Retry search for decoder")
        // A failure on the other segment still offers the one switch.
        #expect(presentation(.episodes, .networkError, .loaded(count: 2), "decoder")?.action == .retry)

        #expect(presentation(.channels, .loading, .noResults, query) == nil)
        #expect(presentation(.episodes, .loaded(count: 3), .noResults, query) == nil)
    }

    @Test("A long query is shortened on screen and read in full")
    func longQueryIsSpokenWhole() {
        let query = String(repeating: "b", count: 80)
        let state = presentation(.channels, .noResults, .loading, query)
        let echo = SearchResultState.echoedQuery(query)
        #expect(state?.title == "No channels for “\(echo.visible)”")
        #expect(state?.title.hasSuffix("”") == true)
        #expect(state?.spokenTitle == "No channels for “\(echo.spoken)”")
        #expect(state?.spokenTitle.contains("\u{200B}") == false)
        #expect(state?.spokenTitle.contains(query) == true)
        #expect(state?.actionAccessibilityLabel == "Show episodes for \(query)")
    }

    @Test("A token breaks by character only when it cannot fit on one line")
    func characterBreaksOnlyWhenTooWide() {
        let sentence = "No channels for “xyzqqqnotaword123”"
        let measure: (String) -> CGFloat = { CGFloat($0.count) * 10 }
        let narrow = SearchResultState.titleFittingLine(sentence, lineWidth: 100, measure: measure)
        #expect(narrow.hasPrefix("No channels for "))
        #expect(!narrow.contains("N\u{200B}"))
        #expect(!narrow.contains("channels".map(String.init).joined(separator: "\u{200B}")))
        #expect(narrow.contains("\u{200B}"))
        let wide = SearchResultState.titleFittingLine(sentence, lineWidth: 400, measure: measure)
        #expect(wide == sentence)
        #expect(!wide.contains("\u{200B}"))
    }

    @Test("A 76-character query keeps its tail inside the sentence")
    func longEchoKeepsTheTail() {
        let tail = "anythingatall9"
        #expect(tail.count == 15)
        let query = String(repeating: "n", count: 40) + String(repeating: "m", count: 21) + tail
        #expect(query.count == 76)
        let echo = SearchResultState.echoedQuery(query)
        #expect(echo.visible.hasSuffix(tail))
        let state = presentation(.channels, .noResults, .loading, query)
        #expect(state?.title.hasSuffix("\(tail)”") == true)
        #expect(state?.title.contains("\u{200B}") == false)
    }

    @Test("The sentences never offer a second path")
    func noSecondPath() {
        let phases: [SearchListPhase] = [.loading, .noResults, .loaded(count: 1), .networkError]
        let segments: [SearchResultSegment] = [.channels, .episodes]
        for segment in segments {
            for phase in phases {
                for other in phases {
                    let state = presentation(segment, phase, other, "vergecats")
                    let buttonCount = state?.showsButton == true ? 1 : 0
                    #expect(buttonCount <= 1)
                    let text = [state?.title, state?.spokenTitle, state?.actionTitle]
                        .compactMap { $0 }
                        .joined(separator: " ")
                    #expect(!text.contains("Browse Discover"))
                    #expect(!text.localizedCaseInsensitiveContains("did you mean"))
                    #expect(!text.contains("Check your connection"))
                }
            }
        }
    }

    // MARK: - Recent

    @Test("Recent records the first hit only")
    func recentRule() {
        #expect(!SearchRecentRule.shouldRecord(
            alreadyRecorded: false, channelsPhase: .loading, episodesPhase: .loading
        ))
        #expect(!SearchRecentRule.shouldRecord(
            alreadyRecorded: false, channelsPhase: .noResults, episodesPhase: .loading
        ))
        #expect(!SearchRecentRule.shouldRecord(
            alreadyRecorded: false, channelsPhase: .noResults, episodesPhase: .noResults
        ))
        #expect(!SearchRecentRule.shouldRecord(
            alreadyRecorded: false, channelsPhase: .networkError, episodesPhase: .networkError
        ))
        #expect(SearchRecentRule.shouldRecord(
            alreadyRecorded: false, channelsPhase: .loaded(count: 1), episodesPhase: .loading
        ))
        #expect(SearchRecentRule.shouldRecord(
            alreadyRecorded: false, channelsPhase: .noResults, episodesPhase: .loaded(count: 2)
        ))
        #expect(!SearchRecentRule.shouldRecord(
            alreadyRecorded: true, channelsPhase: .loaded(count: 4), episodesPhase: .loaded(count: 4)
        ))
        #expect(!SearchRecentRule.hasHit(.loaded(count: 0)))
        #expect(SearchRecentRule.hasHit(.loaded(count: 1)))
    }

    // MARK: - View model

    @Test("A loaded segment is not fetched again; a failed one is")
    func revisitSkipsLoadedSegment() async {
        let script = ScriptedSearch(
            channels: .success([ScriptedSearch.channel("Decoder")]),
            episodes: .success([ScriptedSearch.episode("One")])
        )
        let model = script.makeModel("decoder")
        model.activate(tab: 0)
        await Self.waitUntil { model.channelsLoaded }
        #expect(model.channelsPhase == .loaded(count: 1))
        #expect(script.channelCallCount == 1)
        #expect(script.episodeCallCount == 0)

        model.activate(tab: 1)
        await Self.waitUntil { model.episodesLoaded }
        #expect(script.episodeCallCount == 1)

        model.activate(tab: 0)
        model.activate(tab: 1)
        try? await Task.sleep(for: .milliseconds(80))
        #expect(script.channelCallCount == 1)
        #expect(script.episodeCallCount == 1)
        #expect(model.channelsPhase == .loaded(count: 1))
    }

    @Test("A settled zero-result segment is kept; a failed segment loads again")
    func emptyStaysAndFailureRefetches() async {
        let script = ScriptedSearch(
            channels: .success([]),
            episodes: .failure(Failure())
        )
        let model = script.makeModel("xyzqqqnotaword123")
        model.activate(tab: 0)
        await Self.waitUntil { model.channelsPhase == .noResults }
        #expect(model.channelsLoaded)
        model.activate(tab: 1)
        await Self.waitUntil { model.episodesPhase == .networkError }
        #expect(!model.episodesLoaded)

        model.activate(tab: 0)
        model.activate(tab: 1)
        await Self.waitUntil { script.episodeCallCount >= 2 && model.episodesPhase == .networkError }
        #expect(script.channelCallCount == 1)
        #expect(script.episodeCallCount == 2)
        #expect(model.channelsPhase == .noResults)
    }

    @Test("Retry fetches only the current segment and can recover")
    func retryFetchesOneSegment() async {
        let script = ScriptedSearch(
            channels: .failure(Failure()),
            episodes: .success([ScriptedSearch.episode("Kept")])
        )
        let model = script.makeModel("decoder")
        model.activate(tab: 0)
        await Self.waitUntil { model.channelsPhase == .networkError }
        model.activate(tab: 1)
        await Self.waitUntil { model.episodesLoaded }
        let episodeCalls = script.episodeCallCount
        let kept = model.episodes

        script.setChannels(.success([ScriptedSearch.channel("Decoder")]))
        model.retry(tab: 0)
        #expect(model.channelsPhase == .loading)
        await Self.waitUntil { model.channelsPhase == .loaded(count: 1) }
        #expect(script.channelCallCount == 2)
        #expect(script.episodeCallCount == episodeCalls)
        #expect(model.episodes == kept)
    }

    // MARK: - On the page

    @Test("Zero results and failures are not saved; the first hit is saved once")
    func pageRecordsOnlyHits() async {
        guard let context = await Self.liveUIContext() else { return }
        let store = Self.makeStore(["kept", "decoder"])
        let script = ScriptedSearch(channels: .success([]), episodes: .success([]))
        let page = SearchPageViewController(context: context, recentStore: store, loadCategories: { [] })
        page.setSearchTransport(
            channels: { @Sendable keyword in try await script.fetchChannels(keyword) },
            episodes: { @Sendable keyword in try await script.fetchEpisodes(keyword) }
        )
        page.loadViewIfNeeded()

        page.search("  xyzqqqnotaword123 ")
        await Self.waitUntil { page.segmentPhases.channels == .noResults }
        #expect(store.queries == ["kept", "decoder"])

        page.selectSegmentForTests(1)
        await Self.waitUntil { page.segmentPhases.episodes == .noResults }
        #expect(store.queries == ["kept", "decoder"])
        #expect(script.channelCallCount == 1)
        #expect(script.episodeCallCount == 1)

        script.setChannels(.failure(Failure()))
        page.search("decoder")
        await Self.waitUntil { page.segmentPhases.channels == .networkError }
        #expect(store.queries == ["kept", "decoder"])

        script.setChannels(.success([ScriptedSearch.channel()]))
        await Self.waitUntil { Self.resultAction(in: page) != nil }
        Self.tapResultAction(in: page)
        await Self.waitUntil { store.queries.first == "decoder" }
        #expect(store.queries == ["decoder", "kept"])

        script.setEpisodes(.success([ScriptedSearch.episode()]))
        page.selectSegmentForTests(1)
        await Self.waitUntil { page.segmentPhases.episodes == .loaded(count: 1) }
        #expect(store.queries == ["decoder", "kept"])
    }

    @Test("A hit longer than 60 characters is saved whole")
    func longHitIsSavedWhole() async {
        guard let context = await Self.liveUIContext() else { return }
        let store = Self.makeStore([])
        let query = String(repeating: "字", count: 80)
        let script = ScriptedSearch(channels: .success([ScriptedSearch.channel()]))
        let page = SearchPageViewController(context: context, recentStore: store, loadCategories: { [] })
        page.setSearchTransport(
            channels: { @Sendable keyword in try await script.fetchChannels(keyword) },
            episodes: { @Sendable (_: String) async throws -> [APIClient.EpisodeWithChannel] in [] }
        )
        page.loadViewIfNeeded()
        page.search(query)
        await Self.waitUntil { store.queries == [query] }
        #expect(store.queries == [query])
    }

    @Test("Both empty focuses the field once per search")
    func bothEmptyFocusesOnce() async {
        guard let context = await Self.liveUIContext() else { return }
        let script = ScriptedSearch(channels: .success([]), episodes: .success([]))
        let page = SearchPageViewController(context: context, recentStore: Self.makeStore([]), loadCategories: { [] })
        page.setSearchTransport(
            channels: { @Sendable keyword in try await script.fetchChannels(keyword) },
            episodes: { @Sendable keyword in try await script.fetchEpisodes(keyword) }
        )
        let host = Self.wrap(page)
        let previous = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first { $0.isKeyWindow }
        let window = Self.makeWindow()
        window.rootViewController = host
        window.makeKeyAndVisible()
        page.loadViewIfNeeded()

        page.search("xyzqqqnotaword123")
        await Self.waitUntil { page.segmentPhases.channels == .noResults }
        #expect(page.bothEmptyFocusCount == 0)

        page.selectSegmentForTests(1)
        await Self.waitUntil { page.bothEmptyFocusCount == 1 && page.segmentPhases.episodes == .noResults }
        let field = page.searchFieldForTests
        if field.window != nil {
            try? await Task.sleep(for: .milliseconds(150))
            #expect(field.isFirstResponder)
            #expect(field.text == "xyzqqqnotaword123")
            if let range = field.selectedTextRange {
                #expect(field.offset(from: range.start, to: range.end) == field.text?.count)
            }
        }

        page.selectSegmentForTests(0)
        try? await Task.sleep(for: .milliseconds(80))
        #expect(page.bothEmptyFocusCount == 1)
        #expect(page.didOfferBothEmptyFocus)
        #expect(script.channelCallCount == 1)

        window.isHidden = true
        previous?.makeKeyAndVisible()
    }

    // MARK: - Helpers

    private func presentation(
        _ segment: SearchResultSegment,
        _ phase: SearchListPhase,
        _ other: SearchListPhase,
        _ query: String
    ) -> SearchResultPresentation? {
        SearchResultState.presentation(segment: segment, phase: phase, otherPhase: other, query: query)
    }

    private static func isOnScreen(_ view: UIView) -> Bool {
        var current: UIView? = view
        while let view = current {
            if view.isHidden { return false }
            current = view.superview
        }
        return true
    }

    private static func resultAction(in page: SearchPageViewController) -> UIButton? {
        func find(in view: UIView) -> UIButton? {
            if let button = view as? UIButton, button.accessibilityIdentifier == "search-result-action",
               Self.isOnScreen(button) {
                return button
            }
            for subview in view.subviews {
                if let button = find(in: subview) { return button }
            }
            return nil
        }
        return find(in: page.view)
    }

    private static func tapResultAction(in page: SearchPageViewController) {
        resultAction(in: page)?.sendActions(for: .touchUpInside)
    }

    private static func wrap(_ page: SearchPageViewController) -> UIViewController {
        guard #available(iOS 26.0, *) else { return page }
        let navigation = UINavigationController(rootViewController: page)
        navigation.setNavigationBarHidden(true, animated: false)
        return navigation
    }

    private static func makeWindow() -> UIWindow {
        let frame = CGRect(x: 0, y: 0, width: 402, height: 874)
        if let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first {
            let window = UIWindow(windowScene: scene)
            window.frame = frame
            return window
        }
        return UIWindow(frame: frame)
    }

    private static func makeStore(_ recents: [String]) -> RecentSearchStore {
        let defaults = UserDefaults(suiteName: "SearchResultStateTests-\(UUID().uuidString)")!
        let store = RecentSearchStore(defaults: defaults)
        for query in recents.reversed() { store.record(query) }
        return store
    }

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

/// Scripted channel and episode responses. Call counts are safe to read from
/// the test after a phase has settled. Not actor-isolated, so its fetch
/// methods can be the view model's `@Sendable` transport. The lock is only
/// taken in synchronous helpers: `NSLock` cannot be used directly in `async`.
nonisolated final class ScriptedSearch: @unchecked Sendable {
    struct Failure: Error {}

    private let lock = NSLock()
    private var channelCalls = 0
    private var episodeCalls = 0
    private var channelResult: Result<[SubscriptionRow], Error>
    private var episodeResult: Result<[APIClient.EpisodeWithChannel], Error>

    init(
        channels: Result<[SubscriptionRow], Error> = .success([]),
        episodes: Result<[APIClient.EpisodeWithChannel], Error> = .success([])
    ) {
        channelResult = channels
        episodeResult = episodes
    }

    var channelCallCount: Int { withLock { channelCalls } }

    var episodeCallCount: Int { withLock { episodeCalls } }

    func setChannels(_ result: Result<[SubscriptionRow], Error>) {
        withLock { channelResult = result }
    }

    func setEpisodes(_ result: Result<[APIClient.EpisodeWithChannel], Error>) {
        withLock { episodeResult = result }
    }

    func fetchChannels(_ keyword: String) async throws -> [SubscriptionRow] {
        try reserveChannels().get()
    }

    func fetchEpisodes(_ keyword: String) async throws -> [APIClient.EpisodeWithChannel] {
        try reserveEpisodes().get()
    }

    private func reserveChannels() -> Result<[SubscriptionRow], Error> {
        withLock {
            channelCalls += 1
            return channelResult
        }
    }

    private func reserveEpisodes() -> Result<[APIClient.EpisodeWithChannel], Error> {
        withLock {
            episodeCalls += 1
            return episodeResult
        }
    }

    private func withLock<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }

    @MainActor
    func makeModel(_ query: String) -> SearchPageViewModel {
        SearchPageViewModel(
            searchText: query,
            fetchChannels: { @Sendable [self] keyword in try await self.fetchChannels(keyword) },
            fetchEpisodes: { @Sendable [self] keyword in try await self.fetchEpisodes(keyword) }
        )
    }

    static func channel(_ title: String = "Decoder") -> SubscriptionRow {
        SubscriptionRow(rssFeedUrl: "https://example.com/\(title).rss", title: title)
    }

    static func episode(_ title: String = "Episode") -> APIClient.EpisodeWithChannel {
        APIClient.EpisodeWithChannel(
            episode: FeedEpisodeRow(title: title, enclosureUrl: "https://example.com/\(title).mp3"),
            channel: channel("Show")
        )
    }
}
