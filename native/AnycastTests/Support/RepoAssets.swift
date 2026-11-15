import Foundation
import Testing

/// Locates the repository root from the test source location and loads M0
/// assets. Payloads are gitignored by design; `tool/m0/regen_all.sh` (run
/// once on this machine) materializes them (test/fixtures/README.md).
enum RepoAssets {

    static let repoRoot: URL = {
        var directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        for _ in 0..<8 {
            if FileManager.default.fileExists(atPath: directory.appendingPathComponent("pubspec.yaml").path) {
                return directory
            }
            directory.deleteLastPathComponent()
        }
        fatalError("Repository root (pubspec.yaml) not found above \(#filePath)")
    }()

    static func fixture(_ relativePath: String) -> URL {
        repoRoot.appendingPathComponent("test/fixtures/\(relativePath)")
    }

    static func golden(_ fileName: String) -> URL {
        repoRoot.appendingPathComponent("test/golden/\(fileName)")
    }

    /// Copies a DB fixture bucket (or a single file) into an isolated
    /// temporary sandbox so tests can open/mutate it freely.
    static func sandboxedCopy(ofFixtureDirectory relativePath: String) throws -> URL {
        let source = fixture(relativePath)
        let target = FileManager.default.temporaryDirectory
            .appendingPathComponent("anycast-tests-\(UUID().uuidString)")
        try FileManager.default.copyItem(at: source, to: target)
        return target
    }

    static func loadJSON<T: Decodable>(_ url: URL, as type: T.Type = T.self) throws -> T {
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(T.self, from: data)
    }
}
