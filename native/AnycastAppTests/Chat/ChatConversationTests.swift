import Foundation
import Testing
import AnycastKit
@testable import Anycast

/// ChatConversation state machine (states/chat.dart port): send → "..."
/// placeholder → whole-message replace; K8 (errors never masquerade as AI
/// replies); K27 (401 → login); G13 history wiring through AnycastKit
/// ChatHistory; clear-on-dismiss; isLoading gating.
@MainActor
struct ChatConversationTests {

    // MARK: - Fakes

    /// Records every request; `autoOutcome` (when set) replies immediately,
    /// otherwise the request parks on a continuation the test resolves.
    final class ScriptedChatTransport: ChatTransport {
        struct Request: Equatable {
            var enclosureURL: String
            var input: String
            var history: [[String: String]]
        }

        private(set) var requests: [Request] = []
        private var pending: [CheckedContinuation<ChatTransportOutcome, Never>] = []
        var autoOutcome: ChatTransportOutcome?

        func chat(
            enclosureURL: String, input: String, history: [[String: String]]
        ) async -> ChatTransportOutcome {
            requests.append(
                Request(enclosureURL: enclosureURL, input: input, history: history)
            )
            if let autoOutcome {
                return autoOutcome
            }
            return await withCheckedContinuation { pending.append($0) }
        }

        var parkedRequests: Int { pending.count }

        func resolve(_ outcome: ChatTransportOutcome) {
            pending.removeFirst().resume(returning: outcome)
        }
    }

    private func parkUntilParked(_ transport: ScriptedChatTransport) async {
        for _ in 0..<10_000 where transport.parkedRequests == 0 {
            await Task.yield()
        }
        #expect(transport.parkedRequests == 1, "transport request never arrived")
    }

    // MARK: - Send → placeholder → replace

    @Test("send appends the user message and '...' placeholder, then replaces the placeholder with the reply")
    func sendPlaceholderReplace() async {
        let transport = ScriptedChatTransport()
        transport.autoOutcome = .reply("the answer")
        let conversation = ChatConversation(transport: transport)

        await conversation.send("why", enclosureURL: "enc-1")

        #expect(!conversation.isLoading)
        #expect(conversation.messages.count == 2)
        #expect(conversation.messages[0].author == .human)
        #expect(conversation.messages[0].text == "why")
        // The placeholder is replaced by the whole reply, not appended to.
        #expect(conversation.messages[1].author == .ai)
        #expect(conversation.messages[1].text == "the answer")
        #expect(transport.requests.count == 1)
        #expect(transport.requests[0].enclosureURL == "enc-1")
        #expect(transport.requests[0].input == "why")
    }

    @Test("placeholder is on screen while the request is in flight")
    func placeholderVisibleWhileLoading() async {
        let transport = ScriptedChatTransport()
        let conversation = ChatConversation(transport: transport)

        let sendTask = Task { await conversation.send("hi", enclosureURL: "enc") }
        await parkUntilParked(transport)

        #expect(conversation.isLoading)
        #expect(conversation.messages.map(\.text) == ["hi", "..."])
        #expect(conversation.messages.last?.author == .ai)

        transport.resolve(.reply("done"))
        _ = await sendTask.result

        #expect(!conversation.isLoading)
        #expect(conversation.messages.map(\.text) == ["hi", "done"])
    }

    // MARK: - G13 history wiring

    @Test("history is built by ChatHistory: current input repeated while total ≤ 10")
    func historyRepeatsCurrentInputWithinTen() async {
        let transport = ScriptedChatTransport()
        let conversation = ChatConversation(transport: transport)

        // 4 completed rounds (8 messages), then a paused 5th send → 9
        // messages at snapshot time. The snapshot is prefix(10)-then-
        // reversed (G13): newest first, current input leading the payload
        // AND present in the list itself.
        transport.autoOutcome = .reply("ok")
        for round in 0..<4 {
            await conversation.send("q\(round)", enclosureURL: "enc")
        }
        transport.autoOutcome = nil
        let sendTask = Task { await conversation.send("q4", enclosureURL: "enc") }
        await parkUntilParked(transport)

        let history = transport.requests.last?.history ?? []
        #expect(history.count == 9)
        #expect(history.first == ["human": "q4"], "current input leads the reversed payload (G13)")
        #expect(history.last == ["human": "q0"], "oldest message closes it")
        transport.resolve(.reply("ok"))
        _ = await sendTask.result
    }

    @Test("history over 10 messages sends the FIRST 10 — current input excluded (G13 quirk preserved)")
    func historyOverTenExcludesCurrentInput() async {
        let transport = ScriptedChatTransport()
        let conversation = ChatConversation(transport: transport)

        transport.autoOutcome = .reply("a")
        for round in 0..<5 {
            await conversation.send("q\(round)", enclosureURL: "enc")
        }
        // messages: q0 a0 q1 a1 q2 a2 q3 a3 q4 a4 q5 → 11 total.
        transport.autoOutcome = nil
        let sendTask = Task { await conversation.send("q5", enclosureURL: "enc") }
        await parkUntilParked(transport)

        let expected: [[String: String]] = [
            ["ai": "a"], ["human": "q4"], ["ai": "a"], ["human": "q3"],
            ["ai": "a"], ["human": "q2"], ["ai": "a"], ["human": "q1"],
            ["ai": "a"], ["human": "q0"],
        ]
        #expect(transport.requests.last?.history == expected)
        transport.resolve(.reply("a"))
        _ = await sendTask.result
    }

    // MARK: - K8: errors are never AI messages

    @Test("non-2xx failure removes the placeholder and signals errorBody — no AI message inserted")
    func errorRemovesPlaceholder() async {
        let transport = ScriptedChatTransport()
        let conversation = ChatConversation(transport: transport)
        var errors: [ChatErrorPresentation] = []
        conversation.onError = { errors.append($0) }

        let sendTask = Task { await conversation.send("hi", enclosureURL: "enc") }
        await parkUntilParked(transport)
        transport.resolve(.failure(.errorBody(status: 500, body: "boom")))
        _ = await sendTask.result

        #expect(conversation.messages.map(\.author) == [.human])
        #expect(conversation.messages.map(\.text) == ["hi"])
        #expect(errors == [.errorBody(status: 500, body: "boom")])
        #expect(!conversation.isLoading)
    }

    @Test("403 non-code-2 surfaces the server error text")
    func error403Other() async {
        let transport = ScriptedChatTransport()
        let conversation = ChatConversation(transport: transport)
        var errors: [ChatErrorPresentation] = []
        conversation.onError = { errors.append($0) }

        transport.autoOutcome = .failure(.errorMessage("quota exceeded"))
        await conversation.send("hi", enclosureURL: "enc")

        #expect(conversation.messages.map(\.text) == ["hi"])
        #expect(errors == [.errorMessage("quota exceeded")])
    }

    @Test("transport-level failure removes the placeholder too (Dart line wedged here)")
    func networkFailureRecovers() async {
        let transport = ScriptedChatTransport()
        let conversation = ChatConversation(transport: transport)
        var errors: [ChatErrorPresentation] = []
        conversation.onError = { errors.append($0) }

        transport.autoOutcome = .failure(.networkFailure)
        await conversation.send("hi", enclosureURL: "enc")

        #expect(conversation.messages.map(\.text) == ["hi"])
        #expect(errors == [.networkFailure])
        #expect(!conversation.isLoading)
    }

    // MARK: - K27: 401 → login

    @Test("401 failure routes to the login-required event")
    func loginRequiredRouting() async {
        let transport = ScriptedChatTransport()
        let conversation = ChatConversation(transport: transport)
        var errors: [ChatErrorPresentation] = []
        conversation.onError = { errors.append($0) }

        let sendTask = Task { await conversation.send("hi", enclosureURL: "enc") }
        await parkUntilParked(transport)
        transport.resolve(.failure(.loginRequired))
        _ = await sendTask.result

        #expect(errors == [.loginRequired])
        #expect(conversation.messages.map(\.text) == ["hi"])
        #expect(!conversation.isLoading)
    }

    // MARK: - Clear-on-dismiss

    @Test("clear wipes messages; an in-flight reply lands on a dead conversation")
    func clearDuringFlight() async {
        let transport = ScriptedChatTransport()
        let conversation = ChatConversation(transport: transport)

        let sendTask = Task { await conversation.send("hi", enclosureURL: "enc") }
        await parkUntilParked(transport)
        conversation.clear()
        #expect(conversation.messages.isEmpty)

        transport.resolve(.reply("late reply"))
        _ = await sendTask.result

        #expect(conversation.messages.isEmpty, "late reply must not resurrect the cleared list")
        #expect(!conversation.isLoading, "sending re-enables after clear")
    }

    @Test("clear after a completed round wipes the transcript")
    func clearAfterRound() async {
        let transport = ScriptedChatTransport()
        transport.autoOutcome = .reply("a")
        let conversation = ChatConversation(transport: transport)
        await conversation.send("q", enclosureURL: "enc")
        #expect(conversation.messages.count == 2)

        conversation.clear()
        #expect(conversation.messages.isEmpty)
    }

    // MARK: - isLoading gating

    @Test("send is blocked while a request is in flight")
    func sendGatedWhileLoading() async {
        let transport = ScriptedChatTransport()
        let conversation = ChatConversation(transport: transport)

        let sendTask = Task { await conversation.send("first", enclosureURL: "enc") }
        await parkUntilParked(transport)
        await conversation.send("second", enclosureURL: "enc")

        #expect(transport.requests.count == 1, "gated send must not reach the transport")
        #expect(conversation.messages.map(\.text) == ["first", "..."])

        transport.resolve(.reply("r"))
        _ = await sendTask.result
        #expect(conversation.messages.map(\.text) == ["first", "r"])
    }

    // MARK: - resolveUser parity

    @Test("display names: human → You, ai → AI")
    func displayNames() {
        #expect(ChatConversation.displayName(for: .human) == "You")
        #expect(ChatConversation.displayName(for: .ai) == "AI")
    }
}
