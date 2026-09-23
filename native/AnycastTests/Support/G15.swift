import Foundation
import GRDB
@testable import AnycastKit

/// G15 golden-dump comparison: reads the live database table-by-table in
/// stable order and compares row-for-row against the exported dump.
///
/// Rows are canonicalized on BOTH sides into `[String: String]` maps
/// (`"i:…"` / `"d:…"` / `"s:…"` / `"null"`) — Sendable across executor
/// boundaries and immune to Int/Double JSON parsing differences.
enum G15 {

    struct Comparison {
        var mismatches: [String] = []
    }

    static let mainTables = [
        "playlist", "player", "settings", "subscription", "feedEpisode",
        "playlistEpisode", "historyEpisode", "subtitle", "translation",
    ]

    static func compare(
        database: AppDatabase,
        goldenBucket: String,
        sandbox: URL? = nil,
        ignoringColumns: Set<String> = []
    ) async throws -> Comparison {
        var comparison = Comparison()
        let golden = try loadGoldenObject(RepoAssets.golden("G15_db_dump/\(goldenBucket).json"))

        for table in mainTables {
            let expected = canonicalRows(golden[table] as? [[String: Any]] ?? [])
            let live = try await dumpRows(database: database, table: table)
            compare(expected: expected, live: live, table: table,
                    ignoringColumns: ignoringColumns, into: &comparison)
        }

        // sqlite_sequence (translation AUTOINCREMENT): read must not error.
        let expectedSequence = canonicalRows(golden["sqlite_sequence"] as? [[String: Any]] ?? [])
        let liveSequence = try await database.queue.read { db in
            try canonicalRowsFromSQL(db, sql: "SELECT name, seq FROM sqlite_sequence ORDER BY name")
        }
        compare(expected: expectedSequence, live: liveSequence, table: "sqlite_sequence", into: &comparison)

        // Cache meta databases (bucket layout: Library/Application Support).
        if let sandbox {
            let support = sandbox.appendingPathComponent("Library/Application Support")
            await compareMeta(
                at: support.appendingPathComponent("anycast_episode.db"),
                golden: golden["anycast_episode"] as? [String: Any],
                key: "anycast_episode",
                into: &comparison
            )
            await compareMeta(
                at: support.appendingPathComponent("libCachedImageData.db"),
                golden: golden["libCachedImageData"] as? [String: Any],
                key: "libCachedImageData",
                into: &comparison
            )
        }

        return comparison
    }

    // MARK: - Canonicalization

    /// `"i:403000"` / `"d:1.5"` / `"s:text"` / `"null"`. Golden REAL columns
    /// export as JSON floats; live SQLite REAL columns canonicalize as `d:`
    /// — both sides agree because objCType distinguishes stored doubles.
    static func canonical(_ value: Any) -> String {
        if let number = value as? NSNumber {
            if CFGetTypeID(number) == CFBooleanGetTypeID() {
                return "i:\(number.boolValue ? 1 : 0)"
            }
            let typeChar = number.objCType[0]
            if typeChar == UInt8(ascii: "d") || typeChar == UInt8(ascii: "f") {
                return "d:" + Self.stableDouble(number.doubleValue)
            }
            return "i:\(number.int64Value)"
        }
        if let string = value as? String {
            return "s:\(string)"
        }
        if value is NSNull {
            return "null"
        }
        return "s:\(String(describing: value))"
    }

    /// %.15g both sides: JSONSerialization's decimal-to-double conversion
    /// is not correctly-rounded on Apple platforms (1 ULP off vs strtod) and
    /// printer representations differ across engines. 15 significant digits
    /// keep every meaningful algorithmic value distinct.
    static func stableDouble(_ value: Double) -> String {
        String(format: "%.15g", value)
    }

    static func canonicalRows(_ rows: [[String: Any]]) -> [[String: String]] {
        rows.map { row in
            row.mapValues { canonical($0) }
        }
    }

    static func canonical(raw value: (any DatabaseValueConvertible)?) -> String {
        switch value {
        case .some(let v):
            if let i = v as? Int64 { return "i:\(i)" }
            if let d = v as? Double { return "d:" + G15.stableDouble(d) }
            if let s = v as? String { return "s:\(s)" }
            if let b = v as? Data { return "s:\(String(decoding: b, as: UTF8.self))" }
            return "s:\(v)"
        case .none:
            return "null"
        }
    }

    // MARK: - Live dumps

    private static func dumpRows(database: AppDatabase, table: String) async throws -> [[String: String]] {
        try await database.queue.read { db in
            try canonicalRowsFromSQL(db, sql: "SELECT * FROM \(table) ORDER BY id")
        }
    }

    static func canonicalRowsFromSQL(_ db: Database, sql: String) throws -> [[String: String]] {
        var rows: [[String: String]] = []
        for row in try Row.fetchAll(db, sql: sql) {
            var canonicalRow: [String: String] = [:]
            for column in row.columnNames {
                canonicalRow[column] = canonical(raw: row[column])
            }
            rows.append(canonicalRow)
        }
        return rows
    }

    private static func compareMeta(
        at url: URL,
        golden: [String: Any]?,
        key: String,
        into comparison: inout Comparison
    ) async {
        let expected = canonicalRows((golden?["cacheObject"] as? [[String: Any]]) ?? [])
        let meta = await CacheMetaDatabase.open(at: url)
        guard meta.isAvailable, let queue = meta.queue else {
            if !expected.isEmpty {
                comparison.mismatches.append("\(key): meta DB unavailable but golden has \(expected.count) rows")
            }
            return
        }
        do {
            let live = try await queue.read { db in
                try canonicalRowsFromSQL(db, sql: "SELECT * FROM cacheObject ORDER BY _id")
            }
            compare(expected: expected, live: live, table: key, into: &comparison)
        } catch {
            comparison.mismatches.append("\(key): \(error.localizedDescription)")
        }
    }

    // MARK: - Comparison

    private static func compare(
        expected: [[String: String]],
        live: [[String: String]],
        table: String,
        ignoringColumns: Set<String> = [],
        into comparison: inout Comparison
    ) {
        if expected.count != live.count {
            comparison.mismatches.append("\(table): row count \(live.count) != golden \(expected.count)")
            return
        }
        for rowIndex in live.indices {
            let goldenRow = expected[rowIndex]
            let liveRow = live[rowIndex]
            let keys = Set(goldenRow.keys).union(liveRow.keys)
                .subtracting(ignoringColumns)
            for key in keys.sorted() {
                if goldenRow[key] != liveRow[key] {
                    comparison.mismatches.append(
                        "\(table)[\(rowIndex)].\(key): \(liveRow[key] ?? "«missing»") != golden \(goldenRow[key] ?? "«missing»")"
                    )
                }
            }
        }
    }

    // MARK: - JSON loading

    private static func loadGoldenObject(_ url: URL) throws -> [String: Any] {
        let data = try Data(contentsOf: url)
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw CocoaError(.fileReadCorruptFile)
        }
        return object
    }
}
