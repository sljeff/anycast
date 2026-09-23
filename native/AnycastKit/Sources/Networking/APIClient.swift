import Foundation

/// The anycast.website API client, endpoint by endpoint from
/// docs/migration/02. The red lines (§6) are encoded here:
/// - `Authorization: Bearer <Firebase ID token>` on exactly the four
///   authenticated endpoints; `Content-Type: application/json` ONLY when a
///   body exists (GET/DELETE carry neither header beyond auth).
/// - No client-side 401 refresh — the signed-out state short-circuits with
///   a synthetic 401 without emitting a request.
/// - Timeouts: auth family 10 s, shortlink 3 s; categories/top-channels have
///   no explicit timeout; translation gets the K9-decided 30 s.
/// - Retry: transport failures only; 2 total attempts (3 for shortlink);
///   never 429/5xx.
/// - Error signaling: the old ErrorHandler dialogs become values the UI
///   layer presents (401 and 403 code=2 → login sheet; 403 other → the
///   server's error text; everything else → raw body dialog).
public struct APIClient: Sendable {

    public let host: URL
    public let client: HTTPClient
    /// Firebase ID token, or nil when signed out.
    public let tokenProvider: @Sendable () async throws -> String?

    public init(
        host: URL = URL(string: "https://anycast.website")!,
        client: HTTPClient,
        tokenProvider: @escaping @Sendable () async throws -> String?
    ) {
        self.host = host
        self.client = client
        self.tokenProvider = tokenProvider
    }

    // MARK: - Error model

    /// What the old ErrorHandler would have done, as a value.
    public enum ErrorSignal: Error, Equatable, Sendable {
        case loginRequired                                  // 401 / 403 code==2
        case errorMessage(String)                           // 403 other: server's `error`
        case errorBody(status: Int, body: String)           // any other non-2xx
    }

    public enum APIError: Error, Equatable, Sendable {
        /// Body was not JSON where JSON was required (K4 fix: surfaced as an
        /// error instead of an eternal spinner).
        case invalidJSON
        /// Transport-level failure after all retries.
        case network
        /// The host/path/query could not form a valid URL.
        case invalidRequestURL
    }

    // MARK: - Core plumbing

    /// reqWithAuth port. Signed out → synthetic 401 "Unauthorized", no
    /// request on the wire.
    func authorizedSend(
        path: String,
        method: HTTPClient.HTTPMethod = .GET,
        body: Data? = nil
    ) async throws -> HTTPClient.Response {
        guard let token = try await tokenProvider() else {
            return HTTPClient.Response(status: 401, body: Data("Unauthorized".utf8))
        }
        var headers = ["Authorization": "Bearer \(token)"]
        if body != nil {
            headers["Content-Type"] = "application/json"
        }
        let request = HTTPClient.Request(
            url: host.appendingPathComponent(path),
            method: method,
            headers: headers,
            body: body,
            timeout: 10
        )
        return try await client.send(request, maxAttempts: 2)
    }

    static func decodeJSON(_ data: Data) throws -> [String: Any] {
        guard let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            throw APIError.invalidJSON
        }
        return object
    }

    // MARK: - Query encoding

    /// Dart `Uri(queryParameters:)` encodes each component with
    /// `Uri.encodeQueryComponent`: space → `+`, `+` → `%2B`; the only
    /// characters left raw are `A-Za-z0-9-_.~` (verified against Dart
    /// 2026-09-23: `!'()*` ARE percent-encoded — `%21%27%28%29%2A` — unlike
    /// the RFC 2396 unreserved set). Foundation's `URLComponents`
    /// percent-encodes space as `%20` (harmless) but leaves `+` RAW — a
    /// server decoding form-style would read it as a space ("C++" → "C  ").
    static func dartQueryComponent(_ value: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-_.~")
        let encoded = value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
        return encoded.replacingOccurrences(of: "%20", with: "+")
    }

    /// URL with a Dart-encoded query string (`+` for space, `%2B` for plus).
    func queryURL(path: String, query: [(name: String, value: String)]) throws -> URL {
        guard var components = URLComponents(
            url: host.appendingPathComponent(path),
            resolvingAgainstBaseURL: false
        ) else { throw APIError.invalidRequestURL }
        components.percentEncodedQuery = query
            .map { "\(Self.dartQueryComponent($0.name))=\(Self.dartQueryComponent($0.value))" }
            .joined(separator: "&")
        guard let url = components.url else { throw APIError.invalidRequestURL }
        return url
    }

    /// ErrorHandler.handle/handle403 distilled (02 §2.4): 401 → login;
    /// 403 → parse {error, code}, code==2 → login, else error text; other
    /// non-2xx → raw-body dialog signal.
    public static func errorSignal(status: Int, body: Data) -> ErrorSignal {
        if status == 401 {
            return .loginRequired
        }
        if status == 403 {
            if let object = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
               let code = object["code"] as? Int {
                if code == 2 { return .loginRequired }
                return .errorMessage(object["error"] as? String ?? "")
            }
            return .errorMessage(String(decoding: body, as: UTF8.self))
        }
        return .errorBody(status: status, body: String(decoding: body, as: UTF8.self))
    }

    // MARK: - Search / categories / trending (no auth)

    /// GET /api/search/channels?keyword=<text>&limit=20 (G16: title/
    /// description/author trimmed; keywords joined with ',' as-is).
    public func searchChannels(keyword: String) async throws -> [SubscriptionRow] {
        let url = try queryURL(path: "api/search/channels", query: [
            ("keyword", keyword), ("limit", "20"),
        ])
        let request = HTTPClient.Request(url: url, timeout: 10)
        // fetchWithRetry → nil on network failure; the Dart `response!` crash
        // is the K4 fix: propagate as a failure state instead.
        let response = try await client.send(request, maxAttempts: 2)
        return try Self.parseChannelList(response.body)
    }

    static func parseChannelList(_ body: Data) throws -> [SubscriptionRow] {
        let object = try decodeJSON(body)
        guard let list = (object["data"] as? [String: Any])?["channel_list"] as? [[String: Any]] else {
            throw APIError.invalidJSON
        }
        return list.map(Self.channel(from:))
    }

    /// resMap2Channel (G16) — the Dart mapping trims title/description/
    /// author (Dart `.trim()` → `dartTrimmed()`, K40).
    static func channel(from item: [String: Any]) -> SubscriptionRow {
        var row = SubscriptionRow()
        row.rssFeedUrl = item["rss_url"] as? String
        row.title = (item["title"] as? String ?? "").dartTrimmed()
        row.description = (item["description"] as? String ?? "").dartTrimmed()
        row.imageUrl = item["small_cover_url"] as? String
        row.link = item["link"] as? String
        row.categories = ((item["keywords"] as? [Any]) ?? [])
            .compactMap { $0 as? String }
            .joined(separator: ",")
        row.author = (item["author"] as? String ?? "").dartTrimmed()
        row.email = ""
        return row
    }

    public struct EpisodeWithChannel: Sendable, Equatable {
        public var episode: FeedEpisodeRow
        public var channel: SubscriptionRow
    }

    /// GET /api/search/episodes?keyword=<text>&limit=20.
    public func searchEpisodes(keyword: String) async throws -> [EpisodeWithChannel] {
        let url = try queryURL(path: "api/search/episodes", query: [
            ("keyword", keyword), ("limit", "20"),
        ])
        let request = HTTPClient.Request(url: url, timeout: 10)
        let response = try await client.send(request, maxAttempts: 2)

        let object = try Self.decodeJSON(response.body)
        guard let list = object["data"] as? [[String: Any]] else {
            throw APIError.invalidJSON
        }
        return list.compactMap { item in
            guard let channelObject = item["channel"] as? [String: Any] else { return nil }
            var episode = FeedEpisodeRow()
            // No trim on channel title here: Dart's episode mapping does not
            // trim it (only resMap2Channel fields are trimmed, G16).
            episode.channelTitle = channelObject["title"] as? String ?? ""
            episode.rssFeedUrl = channelObject["rss_url"] as? String
            episode.title = item["title"] as? String
            episode.description = item["description"] as? String
            episode.duration = (item["duration"] as? NSNumber)?.int64Value
            episode.enclosureUrl = item["url"] as? String
            // release_date ISO → epoch ms; unparseable → nil (K4: the Dart
            // force-unwrap crash is fixed).
            if let releaseDate = item["release_date"] as? String {
                episode.pubDate = DartDate.parseToEpochMilliseconds(releaseDate)
            }
            episode.imageUrl = item["cover_url"] as? String
            return EpisodeWithChannel(episode: episode, channel: Self.channel(from: channelObject))
        }
    }

    public struct Category: Sendable, Equatable {
        public var name: String
        public var id: String
        public var imageURL: String
        public var nightImageURL: String
    }

    /// GET /api/categories — bare GET: no timeout override, no retry; errors
    /// propagate to the caller (the old code had no error handling here).
    public func listCategories() async throws -> [Category] {
        let request = HTTPClient.Request(url: host.appendingPathComponent("api/categories"))
        let response = try await client.sendOnce(request)
        let object = try Self.decodeJSON(response.body)
        let list = (object["data"] as? [[String: Any]]) ?? []
        return list.compactMap { item in
            guard let name = item["name"] as? String,
                  let id = item["id"] as? String
            else { return nil }
            return Category(
                name: name,
                id: id,
                imageURL: item["image_url"] as? String ?? "",
                nightImageURL: item["night_image_url"] as? String ?? ""
            )
        }
    }

    /// GET /api/top-channels?category_id=&country= — bare GET; `data: null`
    /// is a VALID empty answer (02 §1.2).
    public func listChannels(categoryID: String, country: String) async throws -> [SubscriptionRow] {
        let url = try queryURL(path: "api/top-channels", query: [
            ("category_id", categoryID), ("country", country),
        ])
        let request = HTTPClient.Request(url: url)
        let response = try await client.sendOnce(request)
        let object = try Self.decodeJSON(response.body)
        guard let data = object["data"] as? [String: Any],
              let list = data["list"] as? [[String: Any]]
        else { return [] } // data:null → empty
        return list.map(Self.channel(from:))
    }

    // MARK: - User (auth)

    public enum UserResult: Sendable, Equatable {
        case user(User)
        case invalidFields           // Dart ①: fromJson threw → null (no dialog)
        case error(ErrorSignal)
    }

    /// GET /api/user — non-JSON bodies raise (K4 ②); 401 surfaces as the
    /// login-sheet signal (`.error(.loginRequired)`), covering both the
    /// server-side and the signed-out synthetic 401.
    public func getUser() async throws -> UserResult {
        let response = try await authorizedSend(path: "api/user")
        if response.status == 401 {
            return .error(.loginRequired)
        }
        guard let user = User.from(jsonBody: response.body) else {
            // jsonDecode succeeded but fields are wrong → nil without a
            // dialog (Dart ①). Distinguish from non-JSON (②), which throws.
            let object = try? JSONSerialization.jsonObject(with: response.body)
            if object == nil { throw APIError.invalidJSON }
            return .invalidFields
        }
        return .user(user)
    }

    public enum DeleteResult: Sendable, Equatable {
        case deleted                 // 200
        case error(ErrorSignal)      // non-200 routes through ErrorHandler
    }

    /// DELETE /api/user — 200 → deleted; any non-200 carries the
    /// ErrorHandler signal (lib/api/user.dart ran every status through
    /// ErrorHandler.handle — a swallowed 403 code=2 here would hide a
    /// session-invalidated account deletion).
    public func deleteUser() async throws -> DeleteResult {
        let response = try await authorizedSend(path: "api/user", method: .DELETE)
        if response.status == 200 { return .deleted }
        return .error(Self.errorSignal(status: response.status, body: response.body))
    }

    // MARK: - Transcription state machine (auth, K27/K28)

    public struct SubtitleResult: Sendable, Equatable {
        /// "processing" / "succeeded" / "failed" / server intermediate
        /// values pass through as-is.
        public var status: String
        public var language: String?
        public var segments: [SubtitleSegment]?
        public var summary: String?
        public var error: ErrorSignal?
    }

    /// POST /api/subtitles — trigger + poll in one idempotent endpoint.
    /// Error signaling follows K27: the SIGNAL is returned; whether it
    /// surfaces as a dialog (user-triggered) or is silenced (background
    /// polling) is the caller's decision.
    public func getSubtitles(enclosureURL: String) async throws -> SubtitleResult {
        let body = try jsonBody(["enclosure_url": enclosureURL])
        let response = try await authorizedSend(path: "api/subtitles", method: .POST, body: body)

        guard response.is2xx else {
            return SubtitleResult(
                status: "failed",
                language: nil, segments: nil, summary: nil,
                error: Self.errorSignal(status: response.status, body: response.body)
            )
        }

        let object = try Self.decodeJSON(response.body)
        let status = object["status"] as? String ?? ""
        if status != "succeeded" {
            return SubtitleResult(status: status, language: nil, segments: nil, summary: nil, error: nil)
        }
        let subtitle = object["subtitle"] as? [String: Any]
        let language = subtitle?["detected_language"] as? String
        let rawSegments = (subtitle?["segments"] as? [[String: Any]]) ?? []
        let segments = rawSegments.map { segment in
            SubtitleSegment(
                start: (segment["start"] as? NSNumber)?.doubleValue,
                end: (segment["end"] as? NSNumber)?.doubleValue,
                text: segment["text"] as? String
            )
        }
        return SubtitleResult(status: status, language: language, segments: segments, summary: "", error: nil)
    }

    // MARK: - Translation (NO auth — contract)

    public enum TranslationResult: Sendable, Equatable {
        case segments([SubtitleSegment])
        case none            // {"translation": null}
    }

    /// POST /api/subtitles/translate — deliberately unauthenticated; 30 s
    /// timeout and caught failures are the K9 decision.
    public func getTranslation(enclosureURL: String, language: String) async throws -> TranslationResult {
        let body = try jsonBody(["enclosure_url": enclosureURL, "language": language])
        let request = HTTPClient.Request(
            url: host.appendingPathComponent("api/subtitles/translate"),
            method: .POST,
            headers: ["Content-Type": "application/json"],
            body: body,
            timeout: 30
        )
        let response = try await client.sendOnce(request)
        let object = try Self.decodeJSON(response.body)
        guard let raw = object["translation"] as? [[String: Any]] else {
            return .none
        }
        return .segments(raw.map { segment in
            SubtitleSegment(
                start: (segment["start"] as? NSNumber)?.doubleValue,
                end: (segment["end"] as? NSNumber)?.doubleValue,
                text: segment["text"] as? String
            )
        })
    }

    // MARK: - Chat (auth, non-streaming, K8)

    public enum ChatResult: Sendable, Equatable {
        case reply(String)
        case error(ErrorSignal)
    }

    /// POST /api/subtitles/chat — single shot, 10 s. Non-2xx bodies are NO
    /// LONGER displayed as AI replies (K8): 401/403 route to their signals,
    /// other statuses surface as errors carrying the body.
    public func chat(enclosureURL: String, input: String, history: [[String: String]]) async throws -> ChatResult {
        let payload: [String: Any] = [
            "enclosure_url": enclosureURL,
            "user_input": input,
            "history": history,
        ]
        let body = try jsonBody(payload)
        let response = try await authorizedSend(path: "api/subtitles/chat", method: .POST, body: body)
        if !response.is2xx {
            return .error(Self.errorSignal(status: response.status, body: response.body))
        }
        let object = try Self.decodeJSON(response.body)
        return .reply(object["result"] as? String ?? "")
    }

    // MARK: - Short links (no auth, hardcoded contract)

    /// POST /api/shortlink — 3 s timeout, 3 total attempts, body pinned by
    /// G12; ANY failure → nil → the caller degrades to the original URL.
    public func getShortURL(for original: URL) async -> URL? {
        let request = HTTPClient.Request(
            url: host.appendingPathComponent("api/shortlink"),
            method: .POST,
            headers: ["Content-Type": "application/json"],
            body: Data(Shortlink.requestBody(for: original.absoluteString).utf8),
            timeout: 3
        )
        guard let response = try? await client.send(request, maxAttempts: 3),
              response.status == 200,
              let short = Shortlink.shortURL(fromResponseBody: response.bodyString)
        else { return nil }
        return URL(string: short)
    }

    // MARK: - Helpers

    func jsonBody(_ object: [String: Any]) throws -> Data {
        guard JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(withJSONObject: object)
        else { throw APIError.invalidJSON }
        return data
    }
}
