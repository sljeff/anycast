import Foundation
import GRDB

/// Row types mirroring the inherited episode tables one-to-one
/// (docs/migration/01 §1). Column names are the Dart-era camelCase names;
/// GRDB's Codable mapping matches property names to columns directly.
///
/// Optionalality mirrors the schema, not convenience: nearly every column is
/// nullable in shipped databases and `db_dirty` exercises them
/// (docs/migration/08 §1.3). All INTEGER time/duration fields are Unix
/// **milliseconds**; booleans are INTEGER 0/1.
public protocol EpisodeFields: Codable, Sendable, FetchableRecord, PersistableRecord {
    var id: Int64? { get set }
    var title: String? { get set }
    var description: String? { get set }
    var duration: Int64? { get set }          // milliseconds
    var enclosureUrl: String? { get set }
    var pubDate: Int64? { get set }           // Unix milliseconds
    var imageUrl: String? { get set }
    var channelTitle: String? { get set }
    var rssFeedUrl: String? { get set }
}

// MARK: - feedEpisode

public struct FeedEpisodeRow: EpisodeFields, Equatable {
    public static let databaseTableName = "feedEpisode"
    public var id: Int64?
    public var title: String?
    public var description: String?
    public var duration: Int64?
    public var enclosureUrl: String?
    public var pubDate: Int64?
    public var imageUrl: String?
    public var channelTitle: String?
    public var rssFeedUrl: String?

    public init(id: Int64? = nil, title: String? = nil, description: String? = nil,
                duration: Int64? = nil, enclosureUrl: String? = nil, pubDate: Int64? = nil,
                imageUrl: String? = nil, channelTitle: String? = nil, rssFeedUrl: String? = nil) {
        self.id = id
        self.title = title
        self.description = description
        self.duration = duration
        self.enclosureUrl = enclosureUrl
        self.pubDate = pubDate
        self.imageUrl = imageUrl
        self.channelTitle = channelTitle
        self.rssFeedUrl = rssFeedUrl
    }
}

// MARK: - historyEpisode (identical shape; "latest" = ORDER BY id DESC)

public struct HistoryEpisodeRow: EpisodeFields, Equatable {
    public static let databaseTableName = "historyEpisode"
    public var id: Int64?
    public var title: String?
    public var description: String?
    public var duration: Int64?
    public var enclosureUrl: String?
    public var pubDate: Int64?
    public var imageUrl: String?
    public var channelTitle: String?
    public var rssFeedUrl: String?

    public init(id: Int64? = nil, title: String? = nil, description: String? = nil,
                duration: Int64? = nil, enclosureUrl: String? = nil, pubDate: Int64? = nil,
                imageUrl: String? = nil, channelTitle: String? = nil, rssFeedUrl: String? = nil) {
        self.id = id
        self.title = title
        self.description = description
        self.duration = duration
        self.enclosureUrl = enclosureUrl
        self.pubDate = pubDate
        self.imageUrl = imageUrl
        self.channelTitle = channelTitle
        self.rssFeedUrl = rssFeedUrl
    }
}

// MARK: - playlistEpisode (adds playlistId / REAL position / playedDuration)

public struct PlaylistEpisodeRow: EpisodeFields, Equatable {
    public static let databaseTableName = "playlistEpisode"
    public var id: Int64?
    public var title: String?
    public var description: String?
    public var duration: Int64?
    public var enclosureUrl: String?
    public var pubDate: Int64?
    public var imageUrl: String?
    public var channelTitle: String?
    public var rssFeedUrl: String?
    /// Fractional ordering key, `ORDER BY position ASC`. Allocation algorithm:
    /// see `PlaylistPositioning`.
    public var position: Double?
    /// Milliseconds of playback progress; periodically written to the queue
    /// head row (matched BY enclosureUrl, not by id).
    public var playedDuration: Int64?
    public var playlistId: Int64?

    public init(id: Int64? = nil, title: String? = nil, description: String? = nil,
                duration: Int64? = nil, enclosureUrl: String? = nil, pubDate: Int64? = nil,
                imageUrl: String? = nil, channelTitle: String? = nil, rssFeedUrl: String? = nil,
                playlistId: Int64? = nil, position: Double? = nil, playedDuration: Int64? = nil) {
        self.id = id
        self.title = title
        self.description = description
        self.duration = duration
        self.enclosureUrl = enclosureUrl
        self.pubDate = pubDate
        self.imageUrl = imageUrl
        self.channelTitle = channelTitle
        self.rssFeedUrl = rssFeedUrl
        self.playlistId = playlistId
        self.position = position
        self.playedDuration = playedDuration
    }
}
