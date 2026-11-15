import Foundation
import Testing
import AnycastKit
@testable import Anycast

/// APIClientChatTransport boundary: APIClient.chat results and thrown
/// transport errors fold into the ChatTransportOutcome cases ChatConversation
/// consumes (K8/K27 routing happens downstream of these values).
///
/// Serialized: the canned URLProtocol response is process-global state, and
/// Swift Testing's default parallelism would let one test's `set` clobber
/// another test's in-flight request.
@MainActor
@Suite(.serialized)
struct ChatTransportMappingTests {

    /// URLProtocol stub replying with a canned status/body or failing the
    /// request — feeds APIClient through its public protocolClasses hook.
    nonisolated final class CannedProtocol: URLProtocol, @unchecked Sendable {
        nonisolated(unsafe) private static var canned: Result<(Int, Data), URLError>?
        private static let lock = NSLock()

        static func set(_ result: Result<(Int, Data), URLError>) {
            lock.lock()
            canned = result
            lock.unlock()
        }

        static func take() -> Result<(Int, Data), URLError>? {
            lock.lock()
            defer { lock.unlock() }
            return canned
        }

        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

        override func startLoading() {
            let result = Self.take() ?? .failure(URLError(.unsupportedURL))
            guard let client else { return }
            switch result {
            case .success(let (status, data)):
                let response = HTTPURLResponse(
                    url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil
                )!
                client.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
                client.urlProtocol(self, didLoad: data)
                client.urlProtocolDidFinishLoading(self)
            case .failure(let error):
                client.urlProtocol(self, didFailWithError: error)
            }
        }

        override func stopLoading() {}
    }

    private func makeTransport() -> APIClientChatTransport {
        APIClientChatTransport(
            api: APIClient(
                client: HTTPClient(protocolClasses: [CannedProtocol.self]),
                tokenProvider: { "test-token" }
            )
        )
    }

    @Test("2xx result body maps to a reply")
    func replyMapping() async {
        CannedProtocol.set(.success((200, Data(#"{"result":"hello"}"#.utf8))))
        let outcome = await makeTransport().chat(enclosureURL: "u", input: "i", history: [])
        #expect(outcome == .reply("hello"))
    }

    @Test("401 maps to loginRequired (K27 / 03 §10.1)")
    func unauthorizedMapsToLogin() async {
        CannedProtocol.set(.success((401, Data("Unauthorized".utf8))))
        let outcome = await makeTransport().chat(enclosureURL: "u", input: "i", history: [])
        #expect(outcome == .failure(.loginRequired))
    }

    @Test("403 code=2 maps to loginRequired; other codes carry the server error")
    func forbiddenMapping() async {
        CannedProtocol.set(.success((403, Data(#"{"error":"no quota","code":2}"#.utf8))))
        let code2 = await makeTransport().chat(enclosureURL: "u", input: "i", history: [])
        #expect(code2 == .failure(.loginRequired))

        CannedProtocol.set(.success((403, Data(#"{"error":"no quota","code":7}"#.utf8))))
        let other = await makeTransport().chat(enclosureURL: "u", input: "i", history: [])
        #expect(other == .failure(.errorMessage("no quota")))
    }

    @Test("other non-2xx maps to errorBody carrying the raw body (K8)")
    func errorBodyMapping() async {
        CannedProtocol.set(.success((500, Data("boom".utf8))))
        let outcome = await makeTransport().chat(enclosureURL: "u", input: "i", history: [])
        #expect(outcome == .failure(.errorBody(status: 500, body: "boom")))
    }

    @Test("transport-level failure folds into networkFailure (Dart line wedged isLoading here)")
    func networkFailureMapping() async {
        CannedProtocol.set(.failure(URLError(.cannotConnectToHost)))
        let outcome = await makeTransport().chat(enclosureURL: "u", input: "i", history: [])
        #expect(outcome == .failure(.networkFailure))
    }
}
