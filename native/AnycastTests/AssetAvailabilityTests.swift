import Testing
import Foundation
@testable import AnycastKit

/// Smoke test: proves the harness can find the M0 payloads before the real
/// suites depend on them.
@Suite("M0 asset availability")
struct AssetAvailabilityTests {

    @Test("Repo root and DB buckets resolve")
    func repoRootResolves() throws {
        #expect(FileManager.default.fileExists(atPath: RepoAssets.repoRoot.appendingPathComponent("pubspec.yaml").path))
        for bucket in ["db_light", "db_heavy", "db_v3", "db_crashed"] {
            #expect(FileManager.default.fileExists(atPath: RepoAssets.fixture("db/\(bucket)/anycast.db").path),
                    "missing fixture bucket \(bucket) — run tool/m0/regen_all.sh")
        }
    }

    @Test("Golden files resolve")
    func goldensResolve() throws {
        for golden in ["G9_settings_codec.json", "G15_db_dump"] {
            #expect(FileManager.default.fileExists(atPath: RepoAssets.golden(golden).path))
        }
    }
}
