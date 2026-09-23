import Foundation

/// Chat history construction for POST /api/subtitles/chat (G13).
///
/// The shipped quirk is pinned byte-for-byte: the controller APPENDS the new
/// message first, then takes the FIRST 10 messages of the list (oldest
/// first) and reverses them into chronological order. Consequences the
/// golden locks in: with ≤10 total the newest message (the current
/// user_input) appears AGAIN as the last history element; with >10 the
/// current input is NOT part of the payload at all. Do not "fix" this
/// (docs/migration/05 §1.5 G13 / 08 §11.5-2).
public enum ChatHistory {

    public struct Message: Equatable, Sendable {
        /// "human" or "ai"
        public var authorID: String
        public var text: String

        public init(authorID: String, text: String) {
            self.authorID = authorID
            self.text = text
        }

        public var isText: Bool { true } // every message in this app is text
    }

    /// Single-key objects, first-10-then-reversed, exactly like
    /// buildChatHistory (states/chat.dart:80-91).
    public static func build(_ messages: [Message]) -> [[String: String]] {
        var history: [[String: String]] = []
        for message in messages.prefix(10) where message.isText {
            history.append([message.authorID: message.text])
        }
        return history.reversed()
    }
}
