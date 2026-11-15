import Foundation
import Testing
import AnycastKit
@testable import Anycast

/// Share-handoff resolution (docs/migration/01 §7 + the vendored extension
/// source): the app reads the App Group `ShareKey` JSON the extension wrote
/// (SharedMediaTypes.swift shape), takes the first file, strips/decodes the
/// `file://` path exactly like `_parseOPML` (states/share.dart:63-74), and
/// parses the OPML. Verified against a synthetic App Group-like directory.
@MainActor
struct ShareHandoffTests {

    private func makeDefaults(suite: String = "t9-share-\(UUID().uuidString)") throws -> (defaults: UserDefaults, suiteName: String) {
        let defaults = try #require(UserDefaults(suiteName: suite))
        return (defaults, suite)
    }

    /// Removes the persistent domain (plist) the suite wrote, so each test
    /// leaves no `t9-share-*` preferences file behind.
    private func cleanupDefaults(_ defaults: UserDefaults, suiteName: String) {
        defaults.removePersistentDomain(forName: suiteName)
    }

    private func writeOPML(_ xml: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("t9-handoff-\(UUID().uuidString).opml")
        try xml.data(using: .utf8)?.write(to: url)
        return url
    }

    private func extensionJSON(path: String) throws -> Data {
        // Exactly what the extension's JSONEncoder emits for one file share
        // (an ARRAY with nil fields absent, type as raw string).
        try JSONSerialization.data(
            withJSONObject: [[
                "path": path,
                "mimeType": "text/xml",
                "type": "file",
            ]]
        )
    }

    // MARK: - Payload decoding

    @Test("Decodes the extension's SharedMediaFile JSON shape")
    func decodesExtensionJSON() throws {
        let data = try extensionJSON(path: "file:///group/my.opml")
        let files = try JSONDecoder().decode([ShareHandoff.SharedMediaFile].self, from: data)
        #expect(files == [ShareHandoff.SharedMediaFile(
            path: "file:///group/my.opml",
            mimeType: "text/xml",
            type: .file
        )])
    }

    @Test("Decodes the full video form (thumbnail/duration/message)")
    func decodesFullForm() throws {
        let json = """
        [{"path":"file:///g/v.mp4","mimeType":"video/mp4","thumbnail":"file:///g/dg.jpg","duration":42000.0,"message":"hi","type":"video"}]
        """
        let files = try JSONDecoder().decode([ShareHandoff.SharedMediaFile].self, from: Data(json.utf8))
        #expect(files.count == 1)
        #expect(files[0].type == .video)
        #expect(files[0].duration == 42000.0)
        #expect(files[0].thumbnail == "file:///g/dg.jpg")
        #expect(files[0].message == "hi")
    }

    @Test("sharedFiles: missing key or garbage data → empty (nothing shared)")
    func missingOrGarbagePayload() throws {
        let (defaults, suiteName) = try makeDefaults()
        defer { cleanupDefaults(defaults, suiteName: suiteName) }
        #expect(ShareHandoff.sharedFiles(in: defaults) == [])
        defaults.set(Data("not json".utf8), forKey: ShareHandoff.userDefaultsKey)
        #expect(ShareHandoff.sharedFiles(in: defaults) == [])
    }

    @Test("First entry only (ShareController.sharedFile)")
    func firstEntryOnly() {
        let files = [
            ShareHandoff.SharedMediaFile(path: "file:///g/one.opml", type: .file),
            ShareHandoff.SharedMediaFile(path: "file:///g/two.opml", type: .file),
        ]
        #expect(ShareHandoff.firstFilePath(from: files) == "file:///g/one.opml")
        #expect(ShareHandoff.firstFilePath(from: []) == nil)
    }

    // MARK: - Path resolution (states/share.dart:67-70)

    @Test("file:// prefix is stripped and percent-decoded once")
    func resolvesFileScheme() {
        let url = ShareHandoff.resolveFileURL(fromPath: "file:///private/var/containers/my%20podcasts.opml")
        #expect(url?.path == "/private/var/containers/my podcasts.opml")
    }

    @Test("A bare path is used verbatim")
    func resolvesBarePath() {
        let url = ShareHandoff.resolveFileURL(fromPath: "/tmp/plain.opml")
        #expect(url?.path == "/tmp/plain.opml")
    }

    @Test("Empty path resolves to nil")
    func emptyPath() {
        #expect(ShareHandoff.resolveFileURL(fromPath: "") == nil)
    }

    // MARK: - End-to-end resolution over a synthetic App Group

    @Test("Handoff: ShareKey JSON → file URL → parsed entries; payload cleared after read")
    func handoffResolution() async throws {
        let (defaults, suiteName) = try makeDefaults()
        defer { cleanupDefaults(defaults, suiteName: suiteName) }
        let fileURL = try writeOPML("""
        <?xml version="1.0" encoding="UTF-8"?>
        <opml version="2.0">
          <body>
            <outline text="d" title="Channel One" type="rss" xmlUrl="https://one.example/f"/>
            <outline text="d" title="Channel Two" type="rss" xmlUrl="https://two.example/f"/>
            <outline text="no url, skipped"/>
          </body>
        </opml>
        """)
        defer { try? FileManager.default.removeItem(at: fileURL) }

        // The extension stores the DECODED absoluteString (spaces literal,
        // percent escapes already resolved once).
        let storedPath = "file://" + fileURL.path
        defaults.set(try extensionJSON(path: storedPath), forKey: ShareHandoff.userDefaultsKey)
        defaults.set("shared message", forKey: ShareHandoff.userDefaultsMessageKey)

        let files = ShareHandoff.sharedFiles(in: defaults)
        #expect(files.count == 1)

        // ReceiveSharingIntent.reset() parity: the stored payload is gone
        // once consumed.
        ShareHandoff.clearStoredPayload(in: defaults)
        #expect(ShareHandoff.sharedFiles(in: defaults) == [])
        #expect(defaults.string(forKey: ShareHandoff.userDefaultsMessageKey) == nil)

        let resolved = try #require(
            ShareHandoff.resolveFileURL(fromPath: ShareHandoff.firstFilePath(from: files) ?? "")
        )
        let entries = try OPMLParser.parse(fileURL: resolved)
        #expect(entries.map(\.title) == ["Channel One", "Channel Two"])
        #expect(entries.map(\.xmlURL) == ["https://one.example/f", "https://two.example/f"])
    }

    @Test("Handoff with no payload resolves to the empty dialog state")
    func handoffEmpty() throws {
        let (defaults, suiteName) = try makeDefaults()
        defer { cleanupDefaults(defaults, suiteName: suiteName) }
        let files = ShareHandoff.sharedFiles(in: defaults)
        let path = ShareHandoff.firstFilePath(from: files)
        #expect(path == nil)
        #expect(ShareHandoff.resolveFileURL(fromPath: path ?? "") == nil)
    }

    // MARK: - Redirect classification (URLRouter, already covered in
    // ShellLogicTests — pinned here for the handoff contract)

    @Test("ShareMedia-<bundleid> scheme classifies as share handoff")
    func routerClassification() throws {
        let router = URLRouter(bundleIdentifier: "com.kindjeff.anycast")
        let url = try #require(URL(string: "ShareMedia-com.kindjeff.anycast:share"))
        #expect(router.classify(url) == .shareHandoff)
        #expect(router.classify(try #require(URL(string: "https://example.com"))) == .unhandled)
    }
}
