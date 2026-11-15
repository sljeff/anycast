import Foundation
import Testing
@testable import AnycastKit

/// M2 additions to the L2 contract suite: every M0 API fixture not yet
/// replayed by `L2ContractTests`, plus red line 11 (share-URL format —
/// lowercase query keys, Dart encoding).
///
/// Coverage invariant (M2 review fix): EVERY fixture file under
/// `test/fixtures/api/` is replayed by name across the two suites — the
/// `network_timeout`/`network_failure`/`slow_response` recordings are
/// status-0 metadata (no body), so their replay maps to the synthetic
/// transport failure through `fixture()`'s status-0 branch. The one name
/// this suite never references, `shortlink_post/ok.json`, is replayed in
/// `L2ContractTests.shortlink` via `fixtureResponse`.
@Suite(.serialized)
struct L2ContractReplayTests {

    private func makeClient(token: String? = "test-token") -> APIClient {
        APIClient(
            client: HTTPClient(protocolClasses: [L2ContractTests.ReplayProtocol.self]),
            tokenProvider: { token }
        )
    }

    private func fixture(_ endpoint: String, _ name: String) throws -> L2ContractTests.ReplayProtocol.Outcome {
        let data = try Data(contentsOf: RepoAssets.fixture("api/\(endpoint)/\(name).json"))
        let object = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        let status = object["status"] as! Int
        if status == 0 {
            return .failure(code: .timedOut)
        }
        return .response(status: status, body: object["body"] as! String)
    }

    // MARK: - Red line 11: share URL format

    @Test("Red line 11: player/channel share URLs use lowercase keys and Dart encoding")
    func shareURLs() {
        let player = ShareURL.player(
            rssFeedURL: "https://example.com/feed.xml",
            enclosureURL: "https://cdn.example.com/a+b episode.mp3"
        )
        #expect(player == "https://anycast.website/player?rssfeedurl=https%3A%2F%2Fexample.com%2Ffeed.xml&enclosureurl=https%3A%2F%2Fcdn.example.com%2Fa%2Bb+episode.mp3",
                "keys are lowercase, `+` encodes as %2B, space as +")

        let channel = ShareURL.channel(rssFeedURL: "https://example.com/feed.xml")
        #expect(channel == "https://anycast.website/channel?rssfeedurl=https%3A%2F%2Fexample.com%2Ffeed.xml")

        // The shortlink md5 is over exactly this string — pin the composed
        // form byte-for-byte for a URL with mixed escaping.
        let tricky = ShareURL.player(
            rssFeedURL: "https://example.com/_feed?x=1&y=2",
            enclosureURL: "https://a.example/ep(1).mp3"
        )
        #expect(tricky == "https://anycast.website/player?rssfeedurl=https%3A%2F%2Fexample.com%2F_feed%3Fx%3D1%26y%3D2&enclosureurl=https%3A%2F%2Fa.example%2Fep%281%29.mp3")
    }

    // MARK: - search_episodes (all five fixtures)

    @Test("search/episodes: ok decodes episodes + channels; varied release dates; empty branches; network failure is an error state (K4)")
    func searchEpisodesFixtures() async throws {
        let client = makeClient()

        L2ContractTests.ReplayProtocol.reset { _ in try! fixture("search_episodes", "ok") }
        var results = try await client.searchEpisodes(keyword: "science")
        #expect(!results.isEmpty)
        #expect(results.allSatisfy { $0.episode.enclosureUrl != nil && $0.channel.rssFeedUrl != nil })

        // release_date variants (ISO formats) — parse or nil, never a crash
        // (the Dart `parsePubDate(...)!` crash is the K4 fix).
        L2ContractTests.ReplayProtocol.reset { _ in try! fixture("search_episodes", "ok_varied_release_dates") }
        results = try await client.searchEpisodes(keyword: "science")
        #expect(!results.isEmpty)

        L2ContractTests.ReplayProtocol.reset { _ in try! fixture("search_episodes", "no_results") }
        #expect(try await client.searchEpisodes(keyword: "zzz").isEmpty)

        L2ContractTests.ReplayProtocol.reset { _ in try! fixture("search_episodes", "empty_data") }
        #expect(try await client.searchEpisodes(keyword: "zzz").isEmpty)

        // Transport failure propagates as an error the UI turns into an
        // error state — the old `response!` crash family (K4).
        L2ContractTests.ReplayProtocol.reset { _ in try! fixture("search_episodes", "network_failure") }
        await #expect(throws: (any Error).self) {
            _ = try await client.searchEpisodes(keyword: "x")
        }
    }

    // MARK: - search_channels remaining branches

    @Test("search/channels: no-results and empty list decode to empty; network failure errors")
    func searchChannelsFixtures() async throws {
        let client = makeClient()

        L2ContractTests.ReplayProtocol.reset { _ in try! fixture("search_channels", "no_results") }
        #expect(try await client.searchChannels(keyword: "zzz").isEmpty)

        L2ContractTests.ReplayProtocol.reset { _ in try! fixture("search_channels", "empty_channel_list") }
        #expect(try await client.searchChannels(keyword: "zzz").isEmpty)

        L2ContractTests.ReplayProtocol.reset { _ in try! fixture("search_channels", "network_failure") }
        await #expect(throws: (any Error).self) {
            _ = try await client.searchChannels(keyword: "x")
        }
    }

    // MARK: - categories / top-channels remaining branches

    @Test("categories: ok decodes, empty list, transport failure propagates")
    func categoriesFixtures() async throws {
        let client = makeClient()

        L2ContractTests.ReplayProtocol.reset { _ in try! fixture("categories", "ok") }
        let categories = try await client.listCategories()
        #expect(!categories.isEmpty)

        // Real recorded probe of the full category tree (sub_categories are
        // not part of the model — name/id/images must still decode).
        L2ContractTests.ReplayProtocol.reset { _ in try! fixture("categories", "empty_country_probe") }
        let probed = try await client.listCategories()
        #expect(!probed.isEmpty)
        #expect(probed.contains { $0.name == "Arts" })

        L2ContractTests.ReplayProtocol.reset { _ in try! fixture("categories", "empty_list") }
        #expect(try await client.listCategories().isEmpty)

        L2ContractTests.ReplayProtocol.reset { _ in try! fixture("categories", "network_failure") }
        await #expect(throws: (any Error).self) {
            _ = try await client.listCategories()
        }
    }

    @Test("top-channels: ok_us/ok_cn/ok_jp decode; unknown category list still fills; network failure errors")
    func topChannelsFixtures() async throws {
        let client = makeClient()
        for name in ["ok_us", "ok_cn", "ok_jp", "unknown_category_null_data"] {
            L2ContractTests.ReplayProtocol.reset { _ in try! fixture("top_channels", name) }
            let list = try await client.listChannels(categoryID: "arts", country: "US")
            #expect(!list.isEmpty, "\(name) should decode channels")
        }

        L2ContractTests.ReplayProtocol.reset { _ in try! fixture("top_channels", "network_failure") }
        await #expect(throws: (any Error).self) {
            _ = try await client.listChannels(categoryID: "arts", country: "US")
        }
    }

    // MARK: - user_delete (all three)

    @Test("DELETE /api/user: 200 deletes; 500/401 route through ErrorHandler signals")
    func deleteUserFixtures() async throws {
        let client = makeClient()

        L2ContractTests.ReplayProtocol.reset { _ in try! fixture("user_delete", "ok_200") }
        guard case .deleted = try await client.deleteUser() else {
            Issue.record("200 must report deleted")
            return
        }

        L2ContractTests.ReplayProtocol.reset { _ in try! fixture("user_delete", "error_500") }
        guard case .error(.errorBody(let status, _)) = try await client.deleteUser() else {
            Issue.record("500 must carry the raw body signal")
            return
        }
        #expect(status == 500)

        L2ContractTests.ReplayProtocol.reset { _ in try! fixture("user_delete", "unauthenticated_401") }
        guard case .error(.loginRequired) = try await client.deleteUser() else {
            Issue.record("401 must signal login")
            return
        }
    }

    @Test("GET /api/user transport timeout throws (no silent nil)")
    func userNetworkTimeout() async throws {
        L2ContractTests.ReplayProtocol.reset { _ in try! fixture("user_get", "network_timeout") }
        await #expect(throws: (any Error).self) {
            _ = try await makeClient().getUser()
        }
    }

    // MARK: - subtitles remaining branches

    @Test("subtitles: processing frames 2/3, succeeded_english, 429 raw body, 401 synthetic")
    func subtitlesRemainingFixtures() async throws {
        let client = makeClient()

        for frame in ["processing_frame_2", "processing_frame_3"] {
            L2ContractTests.ReplayProtocol.reset { _ in try! fixture("subtitles_post", frame) }
            let result = try await client.getSubtitles(enclosureURL: "u")
            #expect(result.status == "processing", "fixture \(frame)")
        }

        L2ContractTests.ReplayProtocol.reset { _ in try! fixture("subtitles_post", "succeeded_english") }
        let succeeded = try await client.getSubtitles(enclosureURL: "u")
        #expect(succeeded.status == "succeeded")
        #expect(succeeded.language == "en")
        #expect((succeeded.segments ?? []).count > 1)

        L2ContractTests.ReplayProtocol.reset { _ in try! fixture("subtitles_post", "error_429") }
        let throttled = try await client.getSubtitles(enclosureURL: "u")
        guard case .errorBody(let status, let body)? = throttled.error else {
            Issue.record("429 must surface as raw body")
            return
        }
        #expect(status == 429)
        #expect(body == "\"Too Many Requests\"", "the recorded body is a JSON-quoted string")

        L2ContractTests.ReplayProtocol.reset { _ in try! fixture("subtitles_post", "unauthenticated_401") }
        let unauthenticated = try await client.getSubtitles(enclosureURL: "u")
        #expect(unauthenticated.error == .loginRequired)

        // Transport timeout (2 attempts, auth family) throws — the caller
        // decides visibility (K27: dialog on add(), silence when polling).
        L2ContractTests.ReplayProtocol.reset { _ in try! fixture("subtitles_post", "network_timeout") }
        await #expect(throws: (any Error).self) {
            _ = try await client.getSubtitles(enclosureURL: "u")
        }
    }

    // MARK: - translation remaining branches

    @Test("translation: ok_de/ok_ja decode; unknown_url answers null translation")
    func translationRemainingFixtures() async throws {
        let client = makeClient()
        for name in ["ok_de", "ok_ja"] {
            L2ContractTests.ReplayProtocol.reset { _ in try! fixture("subtitles_translate_post", name) }
            guard case .segments(let segments) = try await client.getTranslation(enclosureURL: "u", language: "de") else {
                Issue.record("\(name) must produce segments")
                return
            }
            #expect(!segments.isEmpty)
        }
        L2ContractTests.ReplayProtocol.reset { _ in try! fixture("subtitles_translate_post", "unknown_url") }
        let unknown = try await client.getTranslation(enclosureURL: "unknown", language: "zh")
        if case .segments = unknown {
            Issue.record("unknown url fixture answered translation:null")
        }

        // K9's slow-response asset: a request that never completes inside
        // the 30 s window is a transport failure, not a stuck UI.
        L2ContractTests.ReplayProtocol.reset { _ in try! fixture("subtitles_translate_post", "slow_response") }
        await #expect(throws: (any Error).self) {
            _ = try await client.getTranslation(enclosureURL: "u", language: "zh")
        }
    }

    // MARK: - chat remaining branches

    @Test("chat: ok_short/ok_long reply; 401 signal; transport timeout throws")
    func chatRemainingFixtures() async throws {
        let client = makeClient()

        for name in ["ok_short", "ok_long"] {
            L2ContractTests.ReplayProtocol.reset { _ in try! fixture("subtitles_chat_post", name) }
            guard case .reply(let text) = try await client.chat(enclosureURL: "u", input: "hi", history: []) else {
                Issue.record("\(name) must reply")
                return
            }
            #expect(!text.isEmpty)
        }

        // The captured unauthenticated chat response is a real 404 with a
        // JSON body (server answers before auth matters here) — the raw
        // body dialog signal, not a login redirect.
        L2ContractTests.ReplayProtocol.reset { _ in try! fixture("subtitles_chat_post", "unauthenticated_401") }
        let unauthenticated = try await client.chat(enclosureURL: "u", input: "x", history: [])
        guard case .error(.errorBody(let status, let body))? = Optional(unauthenticated) else {
            Issue.record("expected raw-body signal, got \(unauthenticated)")
            return
        }
        #expect(status == 404)
        #expect(body.contains("Subtitle not found"))

        L2ContractTests.ReplayProtocol.reset { _ in try! fixture("subtitles_chat_post", "network_timeout") }
        await #expect(throws: (any Error).self) {
            _ = try await client.chat(enclosureURL: "u", input: "x", history: [])
        }
    }

    // MARK: - shortlink transport timeout

    @Test("POST /api/shortlink timeout: 3 attempts, then degrade to the original URL")
    func shortlinkNetworkTimeout() async throws {
        L2ContractTests.ReplayProtocol.reset { _ in try! fixture("shortlink_post", "network_timeout") }
        let original = URL(string: "https://anycast.website/player?rssfeedurl=a")!
        let short = await makeClient().getShortURL(for: original)
        #expect(short == nil, "ANY shortlink failure degrades to the long URL")
        #expect(L2ContractTests.ReplayProtocol.requests().count == 3,
                "3 total attempts (3 s timeout each) before giving up")
    }
}
