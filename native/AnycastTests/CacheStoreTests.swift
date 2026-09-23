import Foundation
import Testing
@testable import AnycastKit

/// §5.5 download & cache semantics (docs/migration/05 §5.5, 01 §4.1):
/// fork-LRU by object count (default 10) — not bytes — with the 1-day
/// touch grace, the 30-day stale period (or the origin's max-age), the
/// 10 s cleanup spacing, the 100-row round cap, cascade deletion, and the
/// UUIDv1 + mime-extension naming that a rolled-back Flutter build must
/// still recognize.
@Suite(.serialized)
struct CacheStoreTests {

    // MARK: - Header-capable URLProtocol

    final class ServingProtocol: URLProtocol {
        struct Stub {
            var status = 200
            var headers: [String: String] = [:]
            var body: Data
        }

        static let lock = NSLock()
        nonisolated(unsafe) static var routes: [String: Stub] = [:]
        nonisolated(unsafe) static var recorded: [URLRequest] = []

        static func reset(_ routes: [String: Stub]) {
            lock.lock()
            self.routes = routes
            recorded = []
            lock.unlock()
        }

        static func requests() -> [URLRequest] {
            lock.lock(); defer { lock.unlock() }
            return recorded
        }

        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

        override func startLoading() {
            Self.lock.lock()
            Self.recorded.append(request)
            let stub = Self.routes[request.url?.absoluteString ?? ""] ?? Stub(body: Data("x".utf8))
            Self.lock.unlock()

            let response = HTTPURLResponse(
                url: request.url!, statusCode: stub.status,
                httpVersion: "HTTP/1.1", headerFields: stub.headers
            )!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: stub.body)
            client?.urlProtocolDidFinishLoading(self)
        }

        override func stopLoading() {}
    }

    // MARK: - Helpers

    final class FakeClock: @unchecked Sendable {
        var value: Int64 = 1_700_000_000_000
        func advance(_ ms: Int64) { value += ms }
        var now: Int64 { value }
    }

    private func makeStore(
        capacity: Int = 10,
        clock: FakeClock = FakeClock(),
        directory: URL? = nil
    ) async -> (EpisodeCacheStore, URL, CacheMetaDatabase, FakeClock) {
        let directory = directory ?? FileManager.default.temporaryDirectory
            .appendingPathComponent("cache-tests-\(UUID().uuidString)", isDirectory: true)
        let metaURL = directory.appendingPathComponent("anycast_episode.db")
        let meta = try! await CacheMetaDatabase.openWritable(at: metaURL)
        let store = EpisodeCacheStore(
            meta: meta,
            directory: directory.appendingPathComponent("anycast_episode", isDirectory: true),
            maxObjects: { capacity },
            nowMilliseconds: { clock.now },
            protocolClasses: [ServingProtocol.self]
        )
        return (store, directory, meta, clock)
    }

    private let mp3Bytes = Data(repeating: 0xFF, count: 2_048)

    private func stubAudio(contentType: String, cacheControl: String? = nil,
                           etag: String? = nil) -> ServingProtocol.Stub {
        var headers = ["Content-Type": contentType]
        if let cacheControl { headers["Cache-Control"] = cacheControl }
        if let etag { headers["ETag"] = etag }
        headers["Date"] = "Wed, 23 Sep 2026 00:00:00 GMT"
        return ServingProtocol.Stub(headers: headers, body: mp3Bytes)
    }

    // MARK: - Naming / row semantics

    @Test("download stores a UUIDv1-named file with the mime extension and indexes it (key = url)")
    func downloadStoresRow() async throws {
        let (store, directory, meta, clock) = await makeStore()
        let url = "https://cdn.example.com/episode.m4a"
        ServingProtocol.reset([url: stubAudio(contentType: "audio/mpeg", cacheControl: "max-age=604800")])

        let progresses = L2ContractTests.Locked<[Double?]>([])
        let task = await store.startDownload(url: url) { progress in
            progresses.with { $0.append(progress) }
        }
        let file = try await task.value

        // UUIDv1 shape: version nibble 1, RFC variant — plus the observed
        // audio/mpeg → .mp3 mapping.
        let name = file.lastPathComponent
        #expect(name.hasSuffix(".mp3"))
        let hex = name.dropLast(4).replacingOccurrences(of: "-", with: "")
        #expect(hex.count == 32)
        #expect(String(hex.dropFirst(12).prefix(1)) == "1", "UUID version 1")
        #expect(["8", "9", "a", "b"].contains(String(hex.dropFirst(16).prefix(1))), "RFC 4122 variant")
        #expect(FileManager.default.fileExists(atPath: file.path))

        let row = await meta.entry(forURL: url)
        #expect(row?.relativePath == name)
        #expect(row?.key == url, "the key column holds the resource URL (real-device semantics)")
        #expect(row?.length == Int64(mp3Bytes.count))
        #expect(row?.touched == clock.now)

        // validTill follows the origin's max-age: the stub's Date header
        // (Wed, 23 Sep 2026 00:00:00 GMT = epoch 1_790_121_600) + 604800 s,
        // in MILLISECONDS.
        let dateMs: Int64 = 1_790_121_600 * 1000
        #expect(row?.validTill == dateMs + 604_800 * 1000)

        #expect(progresses.with { $0.last } == 1, "progress completes at 1")
    }

    @Test("validTill falls back to the 30-day stale period without cache headers")
    func validTillDefault() async throws {
        let (store, _, meta, clock) = await makeStore()
        let url = "https://cdn.example.com/noheaders.mp3"
        ServingProtocol.reset([url: stubAudio(contentType: "audio/mpeg")])

        let task = await store.startDownload(url: url)
        _ = try await task.value

        let row = await meta.entry(forURL: url)
        #expect(row?.validTill == clock.now + 30 * 86_400_000)
    }

    @Test("cache hit refreshes touched and returns the file; missing file is a plain miss")
    func cacheHitTouches() async throws {
        let (store, _, meta, clock) = await makeStore()
        let url = "https://cdn.example.com/ep.mp3"
        ServingProtocol.reset([url: stubAudio(contentType: "audio/mpeg")])
        _ = try await(await store.startDownload(url: url)).value

        clock.advance(60_000)
        let hit = await store.cachedFile(for: url)
        #expect(hit != nil)
        let row = await meta.entry(forURL: url)
        #expect(row?.touched == clock.now, "the LRU heartbeat updates on access")

        // Row present but file deleted (system cleaned the directory) →
        // tolerated miss, never an error (05 §2.1).
        try FileManager.default.removeItem(at: hit!)
        #expect(await store.cachedFile(for: url) == nil)
        #expect(await store.cachedFile(for: "https://cdn.example.com/never.mp3") == nil)
    }

    @Test("304 revalidation keeps the file and extends its life")
    func revalidation304() async throws {
        let (store, directory, meta, clock) = await makeStore()
        let url = "https://cdn.example.com/ep.mp3"
        ServingProtocol.reset([url: stubAudio(contentType: "audio/mpeg", etag: "\"v1\"")])
        let first = try await(await store.startDownload(url: url)).value
        let originalName = first.lastPathComponent

        clock.advance(86_400_000)
        var stub = stubAudio(contentType: "audio/mpeg", etag: "\"v1\"")
        stub.status = 304
        stub.body = Data()
        ServingProtocol.reset([url: stub])
        let second = try await(await store.startDownload(url: url)).value

        #expect(second.lastPathComponent == originalName, "304 reuses the indexed file")
        #expect(second == first)
        let row = await meta.entry(forURL: url)
        #expect(row?.touched == clock.now)

        // The If-None-Match carried the stored ETag.
        let request = ServingProtocol.requests().last
        #expect(request?.value(forHTTPHeaderField: "If-None-Match") == "\"v1\"")
        _ = directory
    }

    // MARK: - LRU (fork cache_store semantics)

    @Test("over capacity: oldest-touched beyond the limit die, but only after a full untouched day")
    func lruOverCapacity() async throws {
        let clock = FakeClock()
        let (store, _, meta, _) = await makeStore(capacity: 3, clock: clock)

        // Five downloads, one "day" apart: capacities 3 → rows 1,2 are
        // beyond the limit and untouched >1 day.
        var urls: [String] = []
        for index in 0..<5 {
            let url = "https://cdn.example.com/lru\(index).mp3"
            urls.append(url)
            ServingProtocol.reset([url: stubAudio(contentType: "audio/mpeg")])
            _ = try await(await store.startDownload(url: url)).value
            clock.advance(86_400_000) // a day passes between downloads
        }

        await store.cleanupOnce()

        // Newest 3 survive; the two oldest were untouched for days → gone.
        for (index, url) in urls.enumerated() {
            let row = await meta.entry(forURL: url)
            if index < 2 {
                #expect(row == nil, "oldest beyond capacity evicted (lru\(index))")
            } else {
                #expect(row != nil, "recent within capacity kept (lru\(index))")
            }
        }
    }

    @Test("over capacity but recently touched: kept until the grace day passes")
    func lruGrace() async throws {
        let clock = FakeClock()
        let (store, _, meta, _) = await makeStore(capacity: 2, clock: clock)

        // Three downloads minutes apart: g0 is beyond capacity but only
        // minutes untouched → survives this round (the 1-day grace).
        for index in 0..<3 {
            let url = "https://cdn.example.com/g\(index).mp3"
            ServingProtocol.reset([url: stubAudio(contentType: "audio/mpeg")])
            _ = try await(await store.startDownload(url: url)).value
            clock.advance(60_000)
        }

        await store.cleanupOnce()
        #expect(await meta.entry(forURL: "https://cdn.example.com/g0.mp3") != nil,
                "not yet untouched for a day — the fork keeps it")

        clock.advance(86_400_000)
        await store.cleanupOnce()
        #expect(await meta.entry(forURL: "https://cdn.example.com/g0.mp3") == nil,
                "after the grace day it goes")
    }

    @Test("stale rows (past validTill) are removed regardless of capacity")
    func staleCleanup() async throws {
        let clock = FakeClock()
        let (store, _, meta, _) = await makeStore(capacity: 10, clock: clock)
        let url = "https://cdn.example.com/stale.mp3"
        ServingProtocol.reset([url: stubAudio(contentType: "audio/mpeg")])
        _ = try await(await store.startDownload(url: url)).value

        // 31 days later the row is past its 30-day validity.
        clock.advance(31 * 86_400_000)
        await store.cleanupOnce()
        #expect(await meta.entry(forURL: url) == nil)
    }

    @Test("remove deletes file + row (the K3 cascade's cache half)")
    func removeCascade() async throws {
        let (store, _, meta, _) = await makeStore()
        let url = "https://cdn.example.com/gone.mp3"
        ServingProtocol.reset([url: stubAudio(contentType: "audio/mpeg")])
        let file = try await(await store.startDownload(url: url)).value

        await store.remove(url: url)
        #expect(!FileManager.default.fileExists(atPath: file.path))
        #expect(await meta.entry(forURL: url) == nil)
        #expect(await store.cachedFile(for: url) == nil)
    }

    // MARK: - Real-device fixture (db_device)

    @Test("real device meta DB maps URLs to Library/Caches files (write-back caliber)")
    func realDeviceMapping() async throws {
        let fixture = try RepoAssets.sandboxedCopy(ofFixtureDirectory: "db/db_device")
        let metaURL = fixture.appendingPathComponent("Library/Application Support/anycast_episode.db")
        let meta = await CacheMetaDatabase.open(at: metaURL)
        #expect(meta.isAvailable)

        let rows = await meta.allRows()
        #expect(!rows.isEmpty)
        for row in rows {
            #expect(row.key == row.url, "every real row carries the URL as its key")
        }
        guard let row = rows.first, let url = row.url, let name = row.relativePath else {
            Issue.record("fixture lost its cache rows")
            return
        }
        let file = fixture.appendingPathComponent("Library/Caches/anycast_episode/\(name)")
        #expect(FileManager.default.fileExists(atPath: file.path),
                "the real cache files live under Library/Caches/anycast_episode (01 §4.1 correction)")
        #expect(await meta.entry(forURL: url)?.relativePath == name)
    }

    @Test("extension table: audio/mp4 → .mp4 even for .m4a URLs (observed on device)")
    func mimeTable() {
        #expect(EpisodeCacheStore.fileExtension(forContentType: "audio/mpeg") == ".mp3")
        #expect(EpisodeCacheStore.fileExtension(forContentType: "audio/mp4; charset=binary") == ".mp4")
        #expect(EpisodeCacheStore.fileExtension(forContentType: "application/octet-stream") == ".bin")
        #expect(EpisodeCacheStore.fileExtension(forContentType: "audio/x-weird") == ".x-weird")
        #expect(EpisodeCacheStore.fileExtension(forContentType: nil) == ".bin")
    }
}
