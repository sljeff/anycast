import Foundation

/// Identity rules for list-owned action groups over episode rows.
///
/// The enclosure URL is the group's id — but a feed can serve the same
/// URL twice (refetch overlap, feed bugs), and an id shared by two rows
/// opens the group at the FIRST row's position and gaps BOTH cells. Later
/// occurrences get no id, exactly like the Inbox's `.unidentified` rows:
/// a duplicate carries no group of its own and no gap.
nonisolated enum ListActionIdentity {

    /// One id per row, aligned with `urls`. The first occurrence of a URL
    /// keeps it; repeats and empty URLs read as nil (no action identity).
    static func ids(for urls: [String?]) -> [String?] {
        var seen = Set<String>()
        return urls.map { url in
            guard let url, !url.isEmpty, seen.insert(url).inserted else { return nil }
            return url
        }
    }
}
