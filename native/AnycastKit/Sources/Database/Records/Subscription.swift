import Foundation
import GRDB

// MARK: - subscription

public struct SubscriptionRow: Codable, Sendable, Equatable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "subscription"
    public var id: Int64?
    public var rssFeedUrl: String?
    public var title: String?
    public var description: String?
    public var imageUrl: String?
    public var link: String?
    /// Comma-separated categories (rss_fetcher.dart:108).
    public var categories: String?
    public var author: String?
    public var email: String?
    /// Unix milliseconds; the channel's newest episode pubDate, or import
    /// time when the feed has no episodes.
    public var lastUpdated: Int64?

    public init(id: Int64? = nil, rssFeedUrl: String? = nil, title: String? = nil,
                description: String? = nil, imageUrl: String? = nil, link: String? = nil,
                categories: String? = nil, author: String? = nil, email: String? = nil,
                lastUpdated: Int64? = nil) {
        self.id = id
        self.rssFeedUrl = rssFeedUrl
        self.title = title
        self.description = description
        self.imageUrl = imageUrl
        self.link = link
        self.categories = categories
        self.author = author
        self.email = email
        self.lastUpdated = lastUpdated
    }
}
