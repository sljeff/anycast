import Foundation
import GRDB

// Repositories: the only path production code takes to the database. Every
// method is `@concurrent` async — SQLite never executes on a @MainActor
// stack (docs/migration/06 §4, 08 §1.1). Rows cross the boundary as
// `Codable & Sendable` values only.

// MARK: - Shared helpers

/// Dynamic `IN (?,?,...)` deletion, chunked well below any SQLite
/// host-parameter ceiling (the old single-statement version sits right at
/// the legacy 999 boundary, docs/migration/01 §8).
func deleteByEnclosureUrls(_ db: Database, table: String, urls: [String]) throws {
    guard !urls.isEmpty else { return }
    for chunk in urls.chunked(maxLength: 500) {
        let placeholders = Array(repeating: "?", count: chunk.count).joined(separator: ",")
        try db.execute(
            sql: "DELETE FROM \(table) WHERE enclosureUrl IN (\(placeholders))",
            arguments: StatementArguments(chunk)
        )
    }
}

extension Array {
    func chunked(maxLength: Int) -> [[Element]] {
        guard maxLength > 0 else { return [self] }
        return stride(from: 0, to: count, by: maxLength).map {
            Array(self[$0..<Swift.min($0 + maxLength, count)])
        }
    }
}
