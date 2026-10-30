import Foundation

/// In-memory per-episode chat threads, keyed by enclosure URL. Closing the
/// sheet does not clear a thread, and an in-flight request lands in it even
/// while no sheet is showing. Threads live for the app's lifetime and are
/// not persisted.
@MainActor
final class ChatThreadStore {

    static let shared = ChatThreadStore()

    private var threads: [String: ChatConversation] = [:]

    /// Internal so tests can use an isolated store.
    init() {}

    /// The thread for `enclosureURL`, created with `makeTransport` on first use.
    func conversation(
        for enclosureURL: String, makeTransport: () -> ChatTransport
    ) -> ChatConversation {
        if let existing = threads[enclosureURL] { return existing }
        let conversation = ChatConversation(transport: makeTransport())
        threads[enclosureURL] = conversation
        return conversation
    }
}

/// The three fixed example questions shown on an empty thread.
enum ChatExamplePrompts {

    static let summarize = "Summarize this episode"
    static let takeaways = "What are the key takeaways?"
    static let explainNow = "Explain what I'm hearing now"

    static let all = [summarize, takeaways, explainNow]

    /// The question sent for `prompt`. "Explain what I'm hearing now" carries
    /// the current transcript line when there is one.
    static func question(for prompt: String, currentLine: String?) -> String {
        guard prompt == explainNow else { return prompt }
        let line = currentLine?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return line.isEmpty ? prompt : "Explain this part: \"\(line)\""
    }
}
