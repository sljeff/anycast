import Foundation

/// The Search tab's recent queries: most recent first, at most `limit`,
/// unique ignoring case, kept in `UserDefaults` as a `[String]` under
/// `key`. Queries are trimmed before they are stored; empty ones are
/// ignored. A missing or malformed stored value reads as no recents.
struct RecentSearchStore {

    /// `UserDefaults` key of the `[String]` list.
    static let key = "search.recentQueries"
    static let limit = 8

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var queries: [String] {
        defaults.array(forKey: Self.key) as? [String] ?? []
    }

    /// Moves `query` to the front, replacing any entry that differs only by
    /// case, and drops the oldest entries past `limit`.
    func record(_ query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        var updated = queries.filter { $0.caseInsensitiveCompare(trimmed) != .orderedSame }
        updated.insert(trimmed, at: 0)
        defaults.set(Array(updated.prefix(Self.limit)), forKey: Self.key)
    }

    /// Removes the entry equal to `query` ignoring case.
    func remove(_ query: String) {
        defaults.set(queries.filter { $0.caseInsensitiveCompare(query) != .orderedSame }, forKey: Self.key)
    }

    func clear() {
        defaults.removeObject(forKey: Self.key)
    }
}
