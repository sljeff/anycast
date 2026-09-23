import Foundation
import GRDB

// MARK: - Subscriptions

public struct SubscriptionRepository: Sendable {
    let database: AppDatabase
    init(database: AppDatabase) { self.database = database }

    /// ORDER BY title ASC under SQLite BINARY collation (uppercase <
    /// lowercase < non-ASCII) — deliberately not localized (05 §2.1 ④).
    @concurrent
    public func listAll() async throws -> [SubscriptionRow] {
        try await database.queue.read { db in
            try SubscriptionRow.fetchAll(db, sql: "SELECT * FROM subscription ORDER BY title ASC")
        }
    }

    @concurrent
    public func get(byRSSFeedURL url: String) async throws -> SubscriptionRow? {
        try await database.queue.read { db in
            try SubscriptionRow.fetchOne(
                db, sql: "SELECT * FROM subscription WHERE rssFeedUrl = ?", arguments: [url]
            )
        }
    }

    /// Batch INSERT OR REPLACE: colliding on rssFeedUrl **or title** replaces
    /// the whole row with a new id (subscription.dart:86-95). Same-title
    /// channels legitimately evict each other (K13).
    @concurrent
    public func addMany(_ subscriptions: [SubscriptionRow]) async throws {
        try await database.queue.write { db in
            for subscription in subscriptions {
                try subscription.insert(db, onConflict: .replace)
            }
        }
    }

    /// Delete matches EITHER url or title (subscription.dart:97-102).
    @concurrent
    public func remove(_ subscription: SubscriptionRow) async throws {
        try await database.queue.write { db in
            try db.execute(
                sql: "DELETE FROM subscription WHERE rssFeedUrl = ? or title = ?",
                arguments: [subscription.rssFeedUrl, subscription.title]
            )
        }
    }
}
