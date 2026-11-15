import Foundation
import GRDB

// MARK: - player (pointer; row id=1, may be absent after `clear()`)

public struct PlayerRow: Codable, Sendable, Equatable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "player"
    public var id: Int64?
    public var currentPlaylistId: Int64?

    public init(id: Int64? = nil, currentPlaylistId: Int64? = nil) {
        self.id = id
        self.currentPlaylistId = currentPlaylistId
    }
}

/// Restored playback pointer: which playlist the queue is, with a nil
/// `currentPlaylistId` meaning "no playback state" (K31: a missing row is a
/// value, not an error).
public struct PlayerPointer: Codable, Sendable, Equatable {
    public var currentPlaylistId: Int64?
    public init(currentPlaylistId: Int64?) {
        self.currentPlaylistId = currentPlaylistId
    }
}
