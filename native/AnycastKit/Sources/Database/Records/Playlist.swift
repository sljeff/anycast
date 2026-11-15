import Foundation
import GRDB

// MARK: - playlist

public struct PlaylistRow: Codable, Sendable, Equatable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "playlist"
    public var id: Int64?
    public var title: String?
    public var position: Int64?

    public init(id: Int64? = nil, title: String? = nil, position: Int64? = nil) {
        self.id = id
        self.title = title
        self.position = position
    }
}
