import Foundation

/// URLSession wrapper carrying the HTTP contract red lines
/// (docs/migration/02 §6).
///
/// - **Retry**: only transport-level failures (URLError: network down,
///   timedOut, cannotConnect, …) retry — never HTTP 429/5xx. `reqWithAuth`
///   family: 2 total attempts; shortlink: 3 total. Backoff mirrors the Dart
///   `retry` package: 200 ms base with ±25% jitter.
/// - **Timeouts**: request-scoped — 10 s (auth family + fetchWithRetry),
///   3 s (shortlink); categories/top-channels carry no explicit timeout.
/// - **User-Agent**: own API requests send the native URLSession UA (backend
///   has no inbound UA filtering, verified — 02 §7); RSS fetches pin a
///   generic browser UA (K20).
public final class HTTPClient: Sendable {

    public struct Response: Sendable, Equatable {
        public let status: Int
        public let body: Data

        public var bodyString: String { String(decoding: body, as: UTF8.self) }
        public var is2xx: Bool { (200..<300).contains(status) }

        public init(status: Int, body: Data) {
            self.status = status
            self.body = body
        }
    }

    public enum HTTPMethod: String, Sendable {
        case GET, POST, PUT, DELETE
    }

    public enum ClientError: Error, Equatable, Sendable {
        /// Transport failed after all attempts.
        case network(URLError)
        /// Not a transport failure — never retried by this client.
        case cancelled
    }

    public struct Request: Sendable {
        public var url: URL
        public var method: HTTPMethod
        public var headers: [String: String]
        public var body: Data?
        /// Total-request timeout (Dart `.timeout()` equivalent).
        public var timeout: TimeInterval?
        /// Overrides the native UA (RSS fetches pin a browser UA).
        public var userAgent: String?

        public init(url: URL, method: HTTPMethod = .GET,
                    headers: [String: String] = [:], body: Data? = nil,
                    timeout: TimeInterval? = nil, userAgent: String? = nil) {
            self.url = url
            self.method = method
            self.headers = headers
            self.body = body
            self.timeout = timeout
            self.userAgent = userAgent
        }
    }

    private let session: URLSession

    /// - Parameter protocolClasses: test hook — L2 replay injects a
    /// URLProtocol here; production passes nil.
    public init(protocolClasses: [AnyClass]? = nil) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.waitsForConnectivity = false
        if let protocolClasses {
            configuration.protocolClasses = protocolClasses
        }
        self.session = URLSession(configuration: configuration)
    }

    /// Executes with the retry contract. `maxAttempts` = TOTAL attempts
    /// (Dart `retry(maxAttempts:)`), so 2 means one retry.
    public func send(
        _ request: Request,
        maxAttempts: Int = 2
    ) async throws -> Response {
        var lastError: Error = ClientError.network(
            URLError(.notConnectedToInternet)
        )
        for attempt in 1...max(1, maxAttempts) {
            do {
                return try await sendOnce(request)
            } catch let error as ClientError {
                if case .cancelled = error {
                    throw error // cancellation — never retried
                }
                lastError = error // transport failure — retryable
                if attempt < maxAttempts {
                    try? await Task.sleep(for: .milliseconds(Self.retryDelay))
                }
            } catch {
                lastError = error
                if attempt < maxAttempts {
                    try? await Task.sleep(for: .milliseconds(Self.retryDelay))
                }
            }
        }
        throw lastError
    }

    /// Single attempt, no retry.
    public func sendOnce(_ request: Request) async throws -> Response {
        var urlRequest = URLRequest(url: request.url)
        urlRequest.httpMethod = request.method.rawValue
        urlRequest.httpBody = request.body
        if let timeout = request.timeout {
            urlRequest.timeoutInterval = timeout
        }
        for (name, value) in request.headers {
            urlRequest.setValue(value, forHTTPHeaderField: name)
        }
        if let userAgent = request.userAgent {
            urlRequest.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        }

        do {
            let (data, response) = try await session.data(for: urlRequest)
            guard let http = response as? HTTPURLResponse else {
                throw ClientError.network(URLError(.badServerResponse))
            }
            return Response(status: http.statusCode, body: data)
        } catch let error as URLError {
            // Transport-level failure: the retryable family.
            throw ClientError.network(error)
        } catch is CancellationError {
            throw ClientError.cancelled
        } catch {
            throw ClientError.network(URLError(.unknown, userInfo: [NSUnderlyingErrorKey: error]))
        }
    }

    /// Dart retry package default: base 200 ms with factor-based exponential
    /// growth and ±25% jitter. The observed production paths never exceeded
    /// the first delay, so a single randomized base delay is used.
    static let retryDelay: UInt64 = {
        let jitter = Double.random(in: 0.75...1.25)
        return UInt64(200 * jitter)
    }()
}
