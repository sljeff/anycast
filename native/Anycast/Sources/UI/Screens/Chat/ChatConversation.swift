import Foundation
import AnycastKit

/// One text message in the conversation — the Dart `TextMessage`
/// (states/chat.dart): id, author ('human'/'ai'), creation time and text.
struct ChatMessage: Equatable, Sendable {
    enum Author: String, Sendable {
        case human
        case ai
    }

    let id: UUID
    let author: Author
    let createdAt: Date
    let text: String
}

/// How a failed request must surface (K8: an error is NEVER inserted as an
/// AI message). The three dialog/login cases port `ErrorHandler`
/// (lib/api/error_handler.dart, 03 §10.1); `networkFailure` covers thrown
/// transport errors, which the Dart line left wedged with the "..."
/// placeholder on screen forever.
enum ChatErrorPresentation: Equatable, Sendable {
    case loginRequired                              // 401 / 403 code==2 → login sheet
    case errorMessage(String)                       // 403 other: server's `error`
    case errorBody(status: Int, body: String)       // any other non-2xx
    case networkFailure                             // transport-level error
}

/// Outcome of one chat request, transport errors already folded in.
enum ChatTransportOutcome: Equatable, Sendable {
    case reply(String)
    case failure(ChatErrorPresentation)
}

/// Injected chat API so the conversation state machine (and its tests)
/// never touches the network.
@MainActor
protocol ChatTransport: AnyObject {
    func chat(
        enclosureURL: String, input: String, history: [[String: String]]
    ) async -> ChatTransportOutcome
}

/// Production transport: forwards to `APIClient.chat` and folds thrown
/// transport errors (retry-exhausted network, invalid JSON) into the
/// failure case.
@MainActor
final class APIClientChatTransport: ChatTransport {

    private let api: APIClient

    init(api: APIClient) {
        self.api = api
    }

    func chat(
        enclosureURL: String, input: String, history: [[String: String]]
    ) async -> ChatTransportOutcome {
        do {
            switch try await api.chat(
                enclosureURL: enclosureURL, input: input, history: history
            ) {
            case .reply(let text):
                return .reply(text)
            case .error(let signal):
                return .failure(Self.presentation(for: signal))
            }
        } catch {
            return .failure(.networkFailure)
        }
    }

    private static func presentation(
        for signal: APIClient.ErrorSignal
    ) -> ChatErrorPresentation {
        switch signal {
        case .loginRequired:
            return .loginRequired
        case .errorMessage(let text):
            return .errorMessage(text)
        case .errorBody(let status, let body):
            return .errorBody(status: status, body: body)
        }
    }
}

/// The message-list state machine of states/chat.dart, non-streaming:
/// send → append the user message → build the G13 history → append the
/// "..." AI placeholder → POST → on success replace the placeholder with
/// the reply; on failure remove it and signal the error (K8).
@MainActor
final class ChatConversation {

    /// Granular change events the collection view animates on.
    enum MessagesChange: Equatable {
        case appended(count: Int)
        case replaced(index: Int)
        case removedPlaceholder(index: Int)
        case cleared
    }

    /// resolveUser parity (lib/pages/chat.dart): 'human' → "You",
    /// anything else → "AI".
    static func displayName(for author: ChatMessage.Author) -> String {
        author == .human ? "You" : "AI"
    }

    private(set) var messages: [ChatMessage] = []
    private(set) var isLoading = false

    /// Equivalent of `_currentAiMessageId`: the placeholder the next reply
    /// replaces.
    private var currentAiMessageID: UUID?

    /// Bumped by `clear()`; a response landing after a clear is dropped
    /// (the Dart line dropped it through an unhandled `firstWhere` throw).
    private var generation = 0

    private let transport: ChatTransport

    /// K8 error surface: fires only when the placeholder has been removed;
    /// never carries message content.
    var onError: ((ChatErrorPresentation) -> Void)?
    var onMessagesChanged: ((MessagesChange) -> Void)?

    init(transport: ChatTransport) {
        self.transport = transport
    }

    /// sendMessage + send2AI (states/chat.dart:15-59). Blocked while a
    /// request is in flight; the history snapshot is taken after the user
    /// message is appended and before the placeholder is inserted.
    func send(_ text: String, enclosureURL: String) async {
        guard !isLoading else { return }
        isLoading = true

        messages.append(
            ChatMessage(id: UUID(), author: .human, createdAt: .now, text: text)
        )
        let history = ChatHistory.build(
            messages.map { ChatHistory.Message(authorID: $0.author.rawValue, text: $0.text) }
        )

        let placeholderID = UUID()
        currentAiMessageID = placeholderID
        messages.append(
            ChatMessage(id: placeholderID, author: .ai, createdAt: .now, text: "...")
        )
        onMessagesChanged?(.appended(count: 2))

        let generationAtSend = generation
        let outcome = await transport.chat(
            enclosureURL: enclosureURL, input: text, history: history
        )
        defer { isLoading = false }

        // Dismissed/cleared mid-flight: the conversation is gone; drop it.
        guard generation == generationAtSend else { return }

        switch outcome {
        case .reply(let reply):
            guard let index = messages.firstIndex(where: { $0.id == placeholderID })
            else { return }
            // Dart `updateMessage` inserts a NEW id for the reply message.
            messages[index] = ChatMessage(
                id: UUID(), author: .ai, createdAt: .now, text: reply
            )
            currentAiMessageID = nil
            onMessagesChanged?(.replaced(index: index))
        case .failure(let presentation):
            guard let index = messages.firstIndex(where: { $0.id == placeholderID })
            else { return }
            messages.remove(at: index)
            currentAiMessageID = nil
            onMessagesChanged?(.removedPlaceholder(index: index))
            onError?(presentation)
        }
    }

    /// clearMessages (trash button) and the PopScope close hook: wipes the
    /// conversation. Unlike the Dart line, an in-flight request no longer
    /// wedges `isLoading` — its outcome is dropped and sending re-enables.
    func clear() {
        generation += 1
        currentAiMessageID = nil
        isLoading = false
        guard !messages.isEmpty else { return }
        messages.removeAll()
        onMessagesChanged?(.cleared)
    }
}
