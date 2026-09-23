import Foundation
import Testing
@testable import AnycastKit

/// L2 API contract replay (docs/migration/05 §4): every request is captured
/// through a URLProtocol stub and asserted shape-for-shape against the
/// 14 red lines (docs/migration/02 §6); responses replay the M0 API
/// fixtures branch by branch.
@Suite(.serialized)
struct L2ContractTests {

    // MARK: - URLProtocol stub

    final class ReplayProtocol: URLProtocol {
        enum Outcome {
            case response(status: Int, body: String)
            case failure(code: URLError.Code)
            /// Delay then respond — used to observe concurrency.
            case delayedResponse(status: Int, body: String, milliseconds: Int)
        }

        static let lock = NSLock()
        nonisolated(unsafe) static var handler: (@Sendable (URLRequest) -> Outcome)?
        nonisolated(unsafe) static var recorded: [URLRequest] = []
        nonisolated(unsafe) static var inFlight = 0
        nonisolated(unsafe) static var maxInFlight = 0

        static func reset(_ handler: @escaping @Sendable (URLRequest) -> Outcome) {
            lock.lock()
            self.handler = handler
            recorded = []
            inFlight = 0
            maxInFlight = 0
            lock.unlock()
        }

        static func requests() -> [URLRequest] {
            lock.lock(); defer { lock.unlock() }
            return recorded
        }

        /// URLProtocol sees request bodies as a stream, never `httpBody`.
        static func body(of request: URLRequest) -> Data {
            if let data = request.httpBody { return data }
            guard let stream = request.httpBodyStream else { return Data() }
            stream.open()
            defer { stream.close() }
            var data = Data()
            let bufferSize = 4096
            let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
            defer { buffer.deallocate() }
            while stream.hasBytesAvailable {
                let read = stream.read(buffer, maxLength: bufferSize)
                if read <= 0 { break }
                data.append(buffer, count: read)
            }
            return data
        }

        static func maximumInFlight() -> Int {
            lock.lock(); defer { lock.unlock() }
            return maxInFlight
        }

        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

        override func startLoading() {
            Self.lock.lock()
            Self.recorded.append(request)
            Self.inFlight += 1
            Self.maxInFlight = max(Self.maxInFlight, Self.inFlight)
            let handler = Self.handler
            Self.lock.unlock()

            let outcome = handler?(request) ?? .response(status: 500, body: "{}")

            var delay: TimeInterval = 0
            let resolved: Outcome
            switch outcome {
            case let .delayedResponse(status, body, milliseconds):
                delay = TimeInterval(milliseconds) / 1000
                resolved = .response(status: status, body: body)
            default:
                resolved = outcome
            }

            // Respond asynchronously: blocking startLoading serializes the
            // session's protocol queue and hides real concurrency.
            let client = self.client
            let url = request.url
            DispatchQueue.global().asyncAfter(deadline: .now() + delay) {
                switch resolved {
                case let .response(status, body):
                    let response = HTTPURLResponse(
                        url: url!, statusCode: status,
                        httpVersion: "HTTP/1.1", headerFields: [:]
                    )!
                    client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
                    client?.urlProtocol(self, didLoad: Data(body.utf8))
                    client?.urlProtocolDidFinishLoading(self)
                case let .failure(code):
                    client?.urlProtocol(self, didFailWithError: URLError(code))
                case .delayedResponse:
                    break // normalized away above
                }
                Self.lock.lock()
                Self.inFlight -= 1
                Self.lock.unlock()
            }
        }

        override func stopLoading() {}
    }

    /// Mutable capture helper for @Sendable stub closures.
    final class Locked<T>: @unchecked Sendable {
        private var value: T
        private let lock = NSLock()
        init(_ value: T) { self.value = value }
        func with<R>(_ body: (inout T) -> R) -> R {
            lock.lock()
            defer { lock.unlock() }
            return body(&value)
        }
    }

    private func makeClient(token: String? = "test-token") -> APIClient {
        APIClient(
            client: HTTPClient(protocolClasses: [ReplayProtocol.self]),
            tokenProvider: { token }
        )
    }

    private func fixtureResponse(_ endpoint: String, _ name: String) throws -> ReplayProtocol.Outcome {
        let data = try Data(contentsOf: RepoAssets.fixture("api/\(endpoint)/\(name).json"))
        let object = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        let status = object["status"] as! Int
        let body = object["body"] as! String
        return .response(status: status, body: body)
    }

    // MARK: - Red line 1/2: auth headers exactly where they belong

    @Test("Authenticated endpoints carry Bearer; Content-Type only with a body")
    func authHeaders() async throws {
        ReplayProtocol.reset { _ in .response(status: 200, body: "{}") }
        let client = makeClient()

        _ = try await client.getSubtitles(enclosureURL: "https://x.example/ep.mp3")
        _ = try await client.getUser()
        _ = try? await client.deleteUser()
        _ = try await client.chat(enclosureURL: "u", input: "hi", history: [])

        let requests = ReplayProtocol.requests()
        #expect(requests.count == 4)

        let subtitles = requests[0]
        #expect(subtitles.httpMethod == "POST")
        #expect(subscribersAuth(subtitles) == "Bearer test-token")
        #expect(subtitles.value(forHTTPHeaderField: "Content-Type") == "application/json")

        let user = requests[1]
        #expect(user.httpMethod == "GET")
        #expect(subscribersAuth(user) == "Bearer test-token")
        #expect(user.value(forHTTPHeaderField: "Content-Type") == nil,
                "GET carries no Content-Type")

        let delete = requests[2]
        #expect(delete.httpMethod == "DELETE")
        #expect(subscribersAuth(delete) == "Bearer test-token",
                "all four authenticated endpoints carry Bearer")
        #expect(delete.value(forHTTPHeaderField: "Content-Type") == nil,
                "DELETE carries no body and no Content-Type")

        let chat = requests[3]
        #expect(subscribersAuth(chat) == "Bearer test-token",
                "chat is one of the four authenticated endpoints")
        #expect(chat.value(forHTTPHeaderField: "Content-Type") == "application/json")
    }

    @Test("Unauthenticated endpoints carry no Authorization")
    func noAuthEndpoints() async throws {
        // One path-aware stub for the whole test; the recorder is NOT cleared
        // between calls, so the final assertion sees every endpoint (a reset
        // per endpoint used to wipe the earlier evidence).
        ReplayProtocol.reset { request in
            switch request.url?.path {
            case "/api/search/channels":
                return .response(status: 200, body: #"{"data": {"channel_list": []}}"#)
            case "/api/search/episodes", "/api/categories":
                return .response(status: 200, body: #"{"data": []}"#)
            case "/api/top-channels":
                return .response(status: 200, body: #"{"data": null}"#)
            default:
                return .response(status: 200, body: #"{"translation": null}"#)
            }
        }
        let client = makeClient()

        _ = try await client.searchChannels(keyword: "x")
        _ = try await client.searchEpisodes(keyword: "x")
        _ = try await client.listCategories()
        _ = try await client.listChannels(categoryID: "arts", country: "US")
        _ = try await client.getTranslation(enclosureURL: "u", language: "zh")
        _ = await client.getShortURL(for: URL(string: "https://anycast.website/player?rssfeedurl=a")!)

        let requests = ReplayProtocol.requests()
        #expect(requests.count >= 6,
                "search ×2, categories, top-channels, translation, shortlink")
        for (index, request) in requests.enumerated() {
            #expect(subscribersAuth(request) == nil,
                    "\(request.url?.path ?? "request \(index)") must be unauthenticated")
        }
    }

    private func subscribersAuth(_ request: URLRequest) -> String? {
        request.value(forHTTPHeaderField: "Authorization")
    }

    @Test("Signed-out token: synthetic 401, zero requests on the wire")
    func signedOutSynthetic401() async throws {
        ReplayProtocol.reset { _ in .response(status: 200, body: "{}") }
        let client = makeClient(token: nil)

        let result = try await client.getUser()
        guard case .error(let signal) = result else {
            Issue.record("expected error result")
            return
        }
        #expect(signal == .loginRequired)
        #expect(ReplayProtocol.requests().isEmpty, "no request may be emitted")
    }

    // MARK: - Red line: timeouts per endpoint family

    @Test("Timeouts: 10s auth family, 3s shortlink, 30s translation, none for categories/top-channels")
    func timeouts() async throws {
        let client = makeClient()
        var byTimeout: [Int: Int] = [:]
        func tally() {
            for request in ReplayProtocol.requests() {
                let timeout = Int(request.timeoutInterval.rounded())
                byTimeout[timeout, default: 0] += 1
            }
            ReplayProtocol.reset { _ in .response(status: 200, body: "{}") }
        }

        ReplayProtocol.reset { _ in .response(status: 200, body: "{}") }
        _ = try await client.getUser()
        _ = try? await client.deleteUser()
        _ = try await client.getSubtitles(enclosureURL: "u")
        _ = try await client.chat(enclosureURL: "u", input: "i", history: [])
        tally()

        _ = await client.getShortURL(for: URL(string: "https://anycast.website/player?rssfeedurl=a")!)
        tally()

        ReplayProtocol.reset { _ in .response(status: 200, body: #"{"data": []}"#) }
        _ = try await client.listCategories()
        tally()

        ReplayProtocol.reset { _ in .response(status: 200, body: #"{"data": {"list": []}}"#) }
        _ = try await client.listChannels(categoryID: "a", country: "US")
        tally()

        ReplayProtocol.reset { _ in .response(status: 200, body: #"{"translation": null}"#) }
        _ = try await client.getTranslation(enclosureURL: "u", language: "zh")
        tally()

        _ = try await client.getUser()
        tally()

        #expect(byTimeout[10] == 5, "auth family 10s (user ×2, delete, subtitles, chat)")
        #expect(byTimeout[3] == 1, "shortlink 3s")
        #expect(byTimeout[30] == 1, "translation 30s (K9)")
        #expect(byTimeout[60] == 2, "categories/top-channels carry no override")
    }

    // MARK: - Red line 8: retry semantics

    @Test("Retries: transport failure retries once (2 total); HTTP 500/429 never retry")
    func retrySemantics() async throws {
        // Transport failure then success.
        let attempt = Locked(0)
        ReplayProtocol.reset { _ in
            let number = attempt.with { $0 += 1; return $0 }
            return number == 1 ? .failure(code: .notConnectedToInternet) : .response(status: 200, body: "{}")
        }
        _ = try await makeClient().getUser()
        #expect(ReplayProtocol.requests().count == 2)

        // 500: single attempt (no retry — would double-bill on subtitles).
        ReplayProtocol.reset { _ in .response(status: 500, body: "server error") }
        let result = try await makeClient().getSubtitles(enclosureURL: "u")
        #expect(ReplayProtocol.requests().count == 1)
        #expect(result.status == "failed")

        // 429: identical treatment (K10 — no backoff special-casing).
        ReplayProtocol.reset { _ in .response(status: 429, body: "slow down") }
        let result429 = try await makeClient().getSubtitles(enclosureURL: "u")
        #expect(ReplayProtocol.requests().count == 1)
        #expect(result429.status == "failed")
        guard case .errorBody(let status, _)? = result429.error else {
            Issue.record("429 must surface as a raw-body error")
            return
        }
        #expect(status == 429)

        // Transport failure twice → network error.
        ReplayProtocol.reset { _ in .failure(code: .timedOut) }
        await #expect(throws: (any Error).self) {
            _ = try await makeClient().getUser()
        }
        #expect(ReplayProtocol.requests().count == 2, "exactly 2 total attempts")
    }

    // MARK: - Shortlink contract (G12 red line 7)

    @Test("Shortlink: body bytes, 3 attempts, degradation to nil")
    func shortlink() async throws {
        // Real recording (replayed by name — the L2 replay invariant covers
        // every api fixture): 200 + the recorded key.
        let url = "https://anycast.website/player?rssfeedurl=https%3A%2F%2Fexample.com%2Ffeed.xml&enclosureurl=https%3A%2F%2Fexample.com%2Fep1.mp3"
        let recordedOK = try fixtureResponse("shortlink_post", "ok")
        ReplayProtocol.reset { _ in recordedOK }
        let short = await makeClient().getShortURL(for: URL(string: url)!)
        #expect(short?.absoluteString == "https://s.kindjeff.com/c8441b6c1eaabe3e183f5ff28c5e2ae7")

        let sent = ReplayProtocol.requests()[0]
        let sentBody = String(decoding: ReplayProtocol.body(of: sent), as: UTF8.self)
        #expect(sentBody == Shortlink.requestBody(for: url))
        #expect(sentBody.contains(#""password":"cjp2PGN3zuf5cfh""#))

        // status != 200 → nil, single attempt per response.
        let outcome1 = try fixtureResponse("shortlink_post", "status_not_200")
        ReplayProtocol.reset { _ in outcome1 }
        let degraded = await makeClient().getShortURL(for: URL(string: url)!)
        #expect(degraded == nil)

        // Transport failures: 3 total attempts then nil (never throws).
        let attempts = Locked(0)
        ReplayProtocol.reset { _ in
            attempts.with { $0 += 1 }
            return .failure(code: .timedOut)
        }
        let degradedNetwork = await makeClient().getShortURL(for: URL(string: url)!)
        #expect(degradedNetwork == nil)
        #expect(attempts.with { $0 } == 3)
    }

    // MARK: - Subtitles state machine responses (fixtures)

    @Test("Subtitles: processing / succeeded / failed / 403 branches")
    func subtitlesBranches() async throws {
        let client = makeClient()

        let outcome2 = try fixtureResponse("subtitles_post", "processing_frame_1")
        ReplayProtocol.reset { _ in outcome2 }
        var result = try await client.getSubtitles(enclosureURL: "u")
        #expect(result.status == "processing")
        #expect(result.error == nil)

        let outcome3 = try fixtureResponse("subtitles_post", "succeeded_special_chars")
        ReplayProtocol.reset { _ in outcome3 }
        result = try await client.getSubtitles(enclosureURL: "u")
        #expect(result.status == "succeeded")
        #expect(result.language != nil)
        #expect((result.segments ?? []).count > 0)

        let outcome4 = try fixtureResponse("subtitles_post", "failed")
        ReplayProtocol.reset { _ in outcome4 }
        result = try await client.getSubtitles(enclosureURL: "u")
        #expect(result.status == "failed")

        // 403 code=2 → session expired → login sheet signal.
        let outcome5 = try fixtureResponse("subtitles_post", "error_403_code2")
        ReplayProtocol.reset { _ in outcome5 }
        result = try await client.getSubtitles(enclosureURL: "u")
        #expect(result.error == .loginRequired)

        // 403 quota → server's error text dialog.
        let outcome6 = try fixtureResponse("subtitles_post", "error_403_quota")
        ReplayProtocol.reset { _ in outcome6 }
        result = try await client.getSubtitles(enclosureURL: "u")
        guard case .errorMessage(let message)? = result.error else {
            Issue.record("403 quota must surface the error text")
            return
        }
        #expect(!message.isEmpty)

        // 500 → raw body dialog.
        let outcome7 = try fixtureResponse("subtitles_post", "error_500")
        ReplayProtocol.reset { _ in outcome7 }
        result = try await client.getSubtitles(enclosureURL: "u")
        guard case .errorBody(let status, _)? = result.error else {
            Issue.record("500 must surface as raw body")
            return
        }
        #expect(status == 500)
    }

    // MARK: - Translation (no auth)

    @Test("Translation: null → none, segments parse, no Authorization header")
    func translation() async throws {
        let outcome8 = try fixtureResponse("subtitles_translate_post", "translation_null")
        ReplayProtocol.reset { _ in outcome8 }
        var result = try await makeClient().getTranslation(enclosureURL: "u", language: "zh")
        if case .segments = result { Issue.record("null translation must map to .none") }
        #expect(ReplayProtocol.requests()[0].value(forHTTPHeaderField: "Authorization") == nil)

        let outcome9 = try fixtureResponse("subtitles_translate_post", "ok_zh")
        ReplayProtocol.reset { _ in outcome9 }
        result = try await makeClient().getTranslation(enclosureURL: "u", language: "zh")
        guard case .segments(let segments) = result else {
            Issue.record("ok fixture must produce segments")
            return
        }
        #expect(!segments.isEmpty)
    }

    // MARK: - Chat (K8)

    @Test("Chat: single-key history body; non-2xx surfaces as error, never as an AI reply")
    func chatContract() async throws {
        let seenBody = Locked<[String: Any]>([:])
        ReplayProtocol.reset { request in
            let object = (try? JSONSerialization.jsonObject(
                with: ReplayProtocol.body(of: request)
            )) as? [String: Any] ?? [:]
            seenBody.with { $0 = object }
            return .response(status: 200, body: #"{"result": "the answer"}"#)
        }
        let history = ChatHistory.build([
            ChatHistory.Message(authorID: "human", text: "hello"),
            ChatHistory.Message(authorID: "ai", text: "hi"),
        ])
        let result = try await makeClient().chat(enclosureURL: "u", input: "why", history: history)
        guard case .reply(let answer) = result else {
            Issue.record("expected reply")
            return
        }
        #expect(answer == "the answer")
        #expect(seenBody.with { $0["enclosure_url"] as? String } == "u")
        #expect(seenBody.with { $0["user_input"] as? String } == "why")
        let sentHistory = seenBody.with { $0["history"] as? [[String: String]] } ?? []
        #expect(sentHistory == [["ai": "hi"], ["human": "hello"]],
                "reversed, single-key maps — the pinned quirk")

        // 403 error body is NOT an AI reply (K8).
        let outcome10 = try fixtureResponse("subtitles_chat_post", "non2xx_body_as_reply")
        ReplayProtocol.reset { _ in outcome10 }
        var chatResult = try await makeClient().chat(enclosureURL: "u", input: "x", history: [])
        if case .reply = chatResult {
            Issue.record("non-2xx body must not be displayed as a reply (K8)")
        }

        ReplayProtocol.reset { _ in .response(status: 401, body: "Unauthorized") }
        chatResult = try await makeClient().chat(enclosureURL: "u", input: "x", history: [])
        #expect(chatResult == .error(.loginRequired))
    }

    // MARK: - User fixtures

    @Test("User: fixture branches (free/plus/401/non-JSON)")
    func userBranches() async throws {
        let client = makeClient()

        let outcome11 = try fixtureResponse("user_get", "ok_free_plus0_expired_null")
        ReplayProtocol.reset { _ in outcome11 }
        guard case .user(let free) = try await client.getUser() else {
            Issue.record("free fixture should decode")
            return
        }
        #expect(free.plus == 0)
        #expect(free.expireAtEpochMilliseconds == nil)

        let outcome12 = try fixtureResponse("user_get", "ok_plus1_expired_set")
        ReplayProtocol.reset { _ in outcome12 }
        guard case .user(let plus) = try await client.getUser() else {
            Issue.record("plus fixture should decode")
            return
        }
        #expect(plus.plus == 1)
        #expect(plus.expireAtEpochMilliseconds != nil)

        let outcome13 = try fixtureResponse("user_get", "ok_remaining_zero")
        ReplayProtocol.reset { _ in outcome13 }
        guard case .user(let zero) = try await client.getUser() else {
            Issue.record("remaining-zero fixture should decode")
            return
        }
        #expect(zero.remaining == 0)

        let outcome14 = try fixtureResponse("user_get", "unauthenticated_401")
        ReplayProtocol.reset { _ in outcome14 }
        guard case .error(.loginRequired) = try await client.getUser() else {
            Issue.record("401 must signal login")
            return
        }

        // Non-JSON body → thrown error (K4 ②), not an eternal spinner.
        let outcome15 = try fixtureResponse("user_get", "not_json_body")
        ReplayProtocol.reset { _ in outcome15 }
        do {
            _ = try await client.getUser()
            Issue.record("non-JSON body must throw")
        } catch {
            // expected
        }
    }

    // MARK: - Search / categories / top-channels fixtures

    @Test("Search URL shape and G16 trims; Dart query encoding; top-channels data:null → empty")
    func searchShapes() async throws {
        let outcome16 = try fixtureResponse("search_channels", "ok")
        ReplayProtocol.reset { _ in outcome16 }
        let channels = try await makeClient().searchChannels(keyword: "daily")
        #expect(!channels.isEmpty)

        let request = ReplayProtocol.requests()[0]
        #expect(request.url?.path == "/api/search/channels")
        let query = request.url?.query ?? ""
        #expect(query.contains("keyword=daily"))
        #expect(query.contains("limit=20"))

        // Dart Uri(queryParameters:) encoding: `+` must be %2B (a raw `+`
        // decodes as a space server-side — "C++" would become "C  ") and
        // space encodes as `+`, not %20.
        ReplayProtocol.reset { _ in outcome16 }
        _ = try await makeClient().searchChannels(keyword: "C++ daily")
        #expect(ReplayProtocol.requests()[0].url?.query == "keyword=C%2B%2B+daily&limit=20")

        // data:null is a valid empty answer, not an error.
        let outcome17 = try fixtureResponse("top_channels", "null_data")
        ReplayProtocol.reset { _ in outcome17 }
        let list = try await makeClient().listChannels(categoryID: "arts", country: "US")
        #expect(list.isEmpty)
    }

    // MARK: - RSS fetcher: 8-way batching + browser UA (K20)

    @Test("RSS fetch: batches of 8 concurrent, browser UA, failed sources skipped")
    func rssBatching() async throws {
        let urls = (0..<10).map { "https://rss\($0).example.com/feed.xml" }
        ReplayProtocol.reset { request in
            let failing = (request.url?.host?.hasPrefix("rss3") == true
                           || request.url?.host?.hasPrefix("rss7") == true)
            // Every request is delayed so in-flight overlap is observable;
            // the two failing sources answer 500 (fetchWithRetry does NOT
            // retry HTTP failures — the source is skipped).
            return .delayedResponse(
                status: failing ? 500 : 200,
                body: """
                <rss version="2.0"><channel><title>T</title><item><title>i</title>\
                <enclosure url="https://a.example/\(request.url?.host ?? "x").mp3"/></item></channel></rss>
                """,
                milliseconds: 120
            )
        }
        let fetcher = RSSFetcher(
            client: HTTPClient(protocolClasses: [ReplayProtocol.self]),
            userAgent: AppConfigurationRSSUAForTests
        )

        let batches = Locked<[(progress: Int, total: Int)]>([])
        let podcasts = await fetcher.fetchPodcasts(urls: urls) { progress, total, _ in
            batches.with { $0.append((progress, total)) }
        }

        if ReplayProtocol.maximumInFlight() != 8 {
            Issue.record("maxInFlight=\(ReplayProtocol.maximumInFlight()) (want 8)")
        }
        #expect(ReplayProtocol.maximumInFlight() == 8)
        #expect(batches.with { $0.map(\.progress) } == [0, 8], "batch start indices")
        #expect(batches.with { $0.allSatisfy { $0.total == 10 } })
        #expect(podcasts.count == 8, "2 failed sources skipped")

        // Browser UA on RSS fetches (K20).
        #expect(ReplayProtocol.requests().allSatisfy {
            $0.value(forHTTPHeaderField: "User-Agent") == AppConfigurationRSSUAForTests
        })
    }
}

// The kit does not export AppConfiguration (app target); the contract pins
// the UA string value directly here.
let AppConfigurationRSSUAForTests = "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1"
