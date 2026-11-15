import Foundation
import Testing

/// Locates the repository root from the test source location (mirrors the
/// AnycastTests RepoAssets helper; that target's files are off-limits here).
enum TestRepoAssets {

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

    static func golden(_ fileName: String) -> URL {
        repoRoot.appendingPathComponent("test/golden/\(fileName)")
    }
}
