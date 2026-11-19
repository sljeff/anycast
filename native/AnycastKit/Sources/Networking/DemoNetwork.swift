#if DEBUG && targetEnvironment(simulator)
import Foundation

/// DEBUG, simulator-only "demo content" mode: lets the real app be captured
/// with a local snapshot of real podcasts (native/DemoContent).
///
/// Active only when the process was launched with `-anycast-demo-content`
/// or `ANYCAST_DEMO_CONTENT=1`. The whole file is compiled out of Release
/// builds and device builds, so a phone can never flip into this mode.
///
/// What it does: answers every request made through `HTTPClient` (API, RSS,
/// importer) and Kingfisher (artwork) from files under
/// `<container>/Documents/demo`. Requests to other hosts fail immediately.
/// Persisted data (database, cache index, moments) is seeded by
/// `native/DemoContent/build_demo_state.py`; nothing here touches it.
public enum DemoMode {

    public static let isActive: Bool = {
        ProcessInfo.processInfo.arguments.contains("-anycast-demo-content")
            || ProcessInfo.processInfo.environment["ANYCAST_DEMO_CONTENT"] == "1"
    }()

    /// Stand-in bearer token so subtitle and chat calls skip the signed-out
    /// 401 path; the stub ignores its value.
    public static let token = "demo-token"

    /// The only host whose files are served.
    static let host = "demo.anycast.example"

    public static var protocolClasses: [AnyClass] { [DemoURLProtocol.self] }

    /// Session configuration for loaders that build their own session
    /// (Kingfisher).
    public static func sessionConfiguration() -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = protocolClasses
        return configuration
    }

    static var root: URL {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return documents.appendingPathComponent("demo", isDirectory: true)
    }
}

final class DemoURLProtocol: URLProtocol {

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        guard let reply = Self.reply(for: request, url: url) else {
            client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
            return
        }
        let response = HTTPURLResponse(
            url: url, statusCode: reply.status, httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": reply.mime, "Content-Length": String(reply.data.count)]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: reply.data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    // MARK: - Routing

    private struct Reply {
        var status = 200
        var mime: String
        var data: Data
    }

    private static func reply(for request: URLRequest, url: URL) -> Reply? {
        guard url.scheme == "https", url.host == DemoMode.host else { return nil }
        if url.path.hasPrefix("/api/") {
            return api(request, url: url)
        }
        return file(at: url.path)
    }

    private static func file(at path: String) -> Reply? {
        let fileURL = DemoMode.root.appendingPathComponent(path)
        guard let data = try? Data(contentsOf: fileURL) else {
            return Reply(status: 404, mime: "text/plain", data: Data())
        }
        let mime: String
        switch fileURL.pathExtension {
        case "png": mime = "image/png"
        case "jpg", "jpeg": mime = "image/jpeg"
        case "xml": mime = "application/rss+xml"
        case "mp3": mime = "audio/mpeg"
        case "m4a": mime = "audio/mp4"
        default: mime = "application/octet-stream"
        }
        return Reply(mime: mime, data: data)
    }

    private static func json(_ object: Any) -> Reply {
        Reply(mime: "application/json", data: (try? JSONSerialization.data(withJSONObject: object)) ?? Data())
    }

    private static func apiFile(_ name: String) -> Reply {
        let url = DemoMode.root.appendingPathComponent("api/\(name).json")
        guard let data = try? Data(contentsOf: url) else { return json(["data": NSNull()]) }
        return Reply(mime: "application/json", data: data)
    }

    private static func api(_ request: URLRequest, url: URL) -> Reply {
        let route = String(url.path.dropFirst("/api/".count))
        switch route {
        case "categories":
            return apiFile("categories")
        case "top-channels":
            let category = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?.first { $0.name == "category_id" }?.value ?? ""
            let specific = DemoMode.root.appendingPathComponent("api/top-channels.\(category).json")
            return FileManager.default.fileExists(atPath: specific.path)
                ? apiFile("top-channels.\(category)") : apiFile("top-channels")
        case "search/channels":
            return apiFile("search.channels")
        case "search/episodes":
            return apiFile("search.episodes")
        case "subtitles/chat":
            return chat(request)
        case "subtitles/translate":
            return json(["translation": NSNull()])
        case "subtitles":
            return json(["status": "processing"])
        default:
            return Reply(status: 404, mime: "application/json", data: Data("{}".utf8))
        }
    }

    /// Scripted chat: the first entry whose `match` is contained in the
    /// question wins; `fallback` answers everything else.
    private static func chat(_ request: URLRequest) -> Reply {
        let body = bodyData(of: request)
        let input = ((try? JSONSerialization.jsonObject(with: body)) as? [String: Any])?["user_input"] as? String ?? ""
        let script = (try? Data(contentsOf: DemoMode.root.appendingPathComponent("api/chat.json")))
            .flatMap { try? JSONSerialization.jsonObject(with: $0) } as? [String: Any]
        let entries = script?["replies"] as? [[String: String]] ?? []
        let hit = entries.first { entry in
            entry["match"].map { input.localizedCaseInsensitiveContains($0) } ?? false
        }
        let text = hit?["result"] ?? (script?["fallback"] as? String) ?? ""
        return json(["result": text])
    }

    private static func bodyData(of request: URLRequest) -> Data {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return Data() }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            if count <= 0 { break }
            data.append(buffer, count: count)
        }
        return data
    }
}
#endif
