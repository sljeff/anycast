import Foundation

/// The audio download cache, porting the semantics of the Flutter fork of
/// flutter_cache_manager_plus (docs/migration/01 §4.1, 05 §2.4/§5.5):
///
/// - Files live at `<Container>/Library/Caches/anycast_episode/` under
///   `UUIDv1 + mime-extension` names; the URL→file mapping lives ONLY in
///   `Library/Application Support/anycast_episode.db` (same schema, same
///   millisecond `touched`/`validTill` calibers — a rolled-back Flutter
///   build must keep recognizing what we write).
/// - LRU by OBJECT COUNT (default 10), not bytes. Cleanup is scheduled after
///   cache reads with a 10 s minimum interval, at most 100 rows per round:
///   ① rows beyond the capacity, oldest-`touched` first, and only when
///   untouched for more than one day; ② rows whose `validTill` has passed.
/// - No pause/resume for downloads (the fork had none); removing an entry
///   cancels an in-flight download, which is strictly no worse.
/// - `validTill` comes from HTTP cache headers (Date + Cache-Control
///   max-age) when present — the observed real-device value follows the
///   origin's `max-age`, not the 30-day default — else from the 30-day
///   stale period.
public actor EpisodeCacheStore {

    public struct Configuration: Sendable {
        public var cacheKey: String = "anycast_episode"
        /// 30 days (fork `_config_io.dart` default stalePeriod).
        public var stalePeriodMilliseconds: Int64 = 30 * 86_400_000
        /// Only capacity-evict rows untouched for more than one day.
        public var touchGraceMilliseconds: Int64 = 86_400_000
        /// Minimum spacing between cleanup rounds (fork cache_store).
        public var cleanupMinimumIntervalMilliseconds: Int64 = 10_000
        /// Rows per cleanup round (fork limit).
        public var cleanupBatchLimit = 100

        public init() {}
    }

    public enum DownloadError: Error, Equatable {
        case httpStatus(Int)
        case storageFailure
    }

    // MARK: - Dependencies

    private let meta: CacheMetaDatabase
    private let directory: URL
    private let sessionConfiguration: URLSessionConfiguration
    private let nowMilliseconds: @Sendable () -> Int64
    private let maxObjects: @Sendable () async -> Int
    private let configuration: Configuration

    private var inFlight: [String: Task<URL, Error>] = [:]
    private var lastCleanupAt: Int64 = 0  // epoch-ms zero: first read always schedules
    private var cleanupTask: Task<Void, Never>?

    public init(
        meta: CacheMetaDatabase,
        directory: URL,
        maxObjects: @escaping @Sendable () async -> Int,
        nowMilliseconds: @escaping @Sendable () -> Int64 = { Int64(Date().timeIntervalSince1970 * 1000) },
        protocolClasses: [AnyClass]? = nil,
        configuration: Configuration = Configuration()
    ) {
        self.meta = meta
        self.directory = directory
        self.maxObjects = maxObjects
        self.nowMilliseconds = nowMilliseconds
        self.configuration = configuration

        let configuration = URLSessionConfiguration.ephemeral
        configuration.waitsForConnectivity = false
        if let protocolClasses {
            configuration.protocolClasses = protocolClasses
        }
        self.sessionConfiguration = configuration
    }

    // MARK: - Read path (play: cache hit → local file)

    /// Cache lookup for playback (autoSet's `getFileFromCache`): on a hit,
    /// `touched` is refreshed (the LRU heartbeat). A missing file is a plain
    /// miss, never an error. The fork scheduled a cleanup round after EVERY
    /// database read, hit or miss (01 §4.1) — same here.
    public func cachedFile(for url: String) async -> URL? {
        defer { scheduleCleanup() }
        guard let row = await meta.entry(forURL: url) else { return nil }
        guard let name = row.relativePath else { return nil }
        let fileURL = directory.appendingPathComponent(name, isDirectory: false)
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }

        if let id = row._id {
            await meta.updateTouched(_id: id, toMilliseconds: nowMilliseconds())
        }
        return fileURL
    }

    /// URLs that currently resolve to a local file (startup state for the
    /// queue cards — CacheController.onInit equivalent). Reads the whole
    /// index, so it schedules a cleanup round like any other read.
    public func cachedURLs() async -> [String] {
        var urls: [String] = []
        for row in await meta.allRows() {
            guard let url = row.url, let name = row.relativePath else { continue }
            if FileManager.default.fileExists(atPath: directory.appendingPathComponent(name).path) {
                urls.append(url)
            }
        }
        scheduleCleanup()
        return urls
    }

    // MARK: - Download path (manual download + play-to-cache)

    /// Starts (or joins) a full-file download, reporting progress as 0…1
    /// (`nil` when the size is unknown). Registering the task lets
    /// `remove(url:)` cancel it — deleting a card mid-download at least
    /// stops the transfer, which the fork could not do.
    @discardableResult
    public func startDownload(
        url: String,
        onProgress: @escaping @Sendable (Double?) -> Void = { _ in }
    ) -> Task<URL, Error> {
        if let existing = inFlight[url] {
            return existing
        }
        let task = Task { [weak self] in
            guard let self else { throw DownloadError.storageFailure }
            do {
                let file = try await self.performDownload(url: url, onProgress: onProgress)
                await self.finished(url: url)
                return file
            } catch {
                await self.finished(url: url)
                throw error
            }
        }
        inFlight[url] = task
        return task
    }

    private func finished(url: String) {
        inFlight[url] = nil
    }

    /// The download itself: a `URLSessionDownloadTask` (streamed to disk by
    /// the system — no whole-file memory footprint), moved into place on
    /// completion, indexed in the meta DB, then cleanup is scheduled.
    private func performDownload(
        url: String,
        onProgress: @escaping @Sendable (Double?) -> Void
    ) async throws -> URL {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let existingRow = await meta.entry(forURL: url)

        guard let requestURL = URL(string: url) else {
            throw DownloadError.storageFailure
        }
        var request = URLRequest(url: requestURL)
        if let eTag = existingRow?.eTag {
            request.setValue(eTag, forHTTPHeaderField: "If-None-Match")
        }

        let outcome = try await Self.runDownload(
            configuration: sessionConfiguration,
            request: request,
            onProgress: onProgress
        )

        // 304: the indexed file is still good — extend its life (fork
        // behavior on http-cache revalidation) and return it.
        if outcome.response.statusCode == 304, let row = existingRow, let name = row.relativePath {
            let fileURL = directory.appendingPathComponent(name, isDirectory: false)
            if FileManager.default.fileExists(atPath: fileURL.path) {
                var updated = row
                updated.touched = nowMilliseconds()
                updated.validTill = Self.validTill(response: outcome.response, now: nowMilliseconds(),
                                                   stalePeriod: configuration.stalePeriodMilliseconds)
                await meta.upsert(row: updated)
                onProgress(1)
                scheduleCleanup()
                return fileURL
            }
        }

        guard (200..<300).contains(outcome.response.statusCode) else {
            throw DownloadError.httpStatus(outcome.response.statusCode)
        }

        let fileName = Self.fileName(
            for: existingRow,
            contentType: outcome.response.value(forHTTPHeaderField: "Content-Type"),
            now: nowMilliseconds()
        )
        let finalURL = directory.appendingPathComponent(fileName, isDirectory: false)

        // A re-download that changed extension gets a fresh UUIDv1 name —
        // the old file goes away (fork `_setDataFromHeaders`).
        if let old = existingRow?.relativePath, old != fileName {
            try? FileManager.default.removeItem(at: directory.appendingPathComponent(old))
        }
        try? FileManager.default.removeItem(at: finalURL)
        do {
            try FileManager.default.moveItem(at: outcome.fileLocation, to: finalURL)
        } catch {
            try? FileManager.default.removeItem(at: outcome.fileLocation)
            throw DownloadError.storageFailure
        }

        let attributes = try? FileManager.default.attributesOfItem(atPath: finalURL.path)
        let length = (attributes?[.size] as? NSNumber)?.int64Value ?? 0
        await meta.upsert(row: CacheMetaDatabase.CacheObjectRow(
            _id: nil,
            url: url,
            key: url,
            relativePath: fileName,
            eTag: outcome.response.value(forHTTPHeaderField: "ETag"),
            validTill: Self.validTill(response: outcome.response, now: nowMilliseconds(),
                                      stalePeriod: configuration.stalePeriodMilliseconds),
            touched: nowMilliseconds(),
            length: length
        ))
        onProgress(1)
        scheduleCleanup()
        return finalURL
    }

    /// One download through the system streaming path. The delegate moves
    /// the system's temporary file somewhere stable before the continuation
    /// resumes (iOS deletes it otherwise).
    private struct DownloadOutcome: Sendable {
        var response: HTTPURLResponse
        var fileLocation: URL
    }

    private static func runDownload(
        configuration: URLSessionConfiguration,
        request: URLRequest,
        onProgress: @escaping @Sendable (Double?) -> Void
    ) async throws -> DownloadOutcome {
        try await withCheckedThrowingContinuation { continuation in
            let delegate = DownloadDelegate(continuation: continuation, onProgress: onProgress)
            // One session per download, invalidated when the delegate is
            // done with it — the injected protocolClasses ride along.
            let session = URLSession(configuration: configuration,
                                     delegate: delegate,
                                     delegateQueue: nil)
            delegate.finish = { [weak session] in session?.finishTasksAndInvalidate() }
            session.downloadTask(with: request).resume()
        }
    }

    private final class DownloadDelegate: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
        let continuation: CheckedContinuation<DownloadOutcome, any Error>
        let onProgress: @Sendable (Double?) -> Void
        var finish: (() -> Void)?

        init(continuation: CheckedContinuation<DownloadOutcome, any Error>,
             onProgress: @escaping @Sendable (Double?) -> Void) {
            self.continuation = continuation
            self.onProgress = onProgress
        }

        private func done(_ resume: () -> Void) {
            resume()
            finish?()
        }

        func urlSession(
            _ session: URLSession,
            downloadTask: URLSessionDownloadTask,
            didWriteData bytesWritten: Int64,
            totalBytesWritten: Int64,
            totalBytesExpectedToWrite: Int64
        ) {
            guard totalBytesExpectedToWrite > 0 else { return }
            onProgress(Double(totalBytesWritten) / Double(totalBytesExpectedToWrite))
        }

        func urlSession(
            _ session: URLSession,
            downloadTask: URLSessionDownloadTask,
            didFinishDownloadingTo location: URL
        ) {
            // Park the file outside the system's cleanup scope.
            let parked = FileManager.default.temporaryDirectory
                .appendingPathComponent("anycast-dl-\(UUID().uuidString)")
            do {
                try? FileManager.default.removeItem(at: parked)
                try FileManager.default.moveItem(at: location, to: parked)
            } catch {
                done { continuation.resume(throwing: DownloadError.storageFailure) }
                return
            }
            guard let response = downloadTask.response as? HTTPURLResponse else {
                try? FileManager.default.removeItem(at: parked)
                done { continuation.resume(throwing: DownloadError.storageFailure) }
                return
            }
            done { continuation.resume(returning: DownloadOutcome(response: response, fileLocation: parked)) }
        }

        func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?) {
            guard let error else { return } // success path resumed in didFinishDownloadingTo
            done { continuation.resume(throwing: error) }
        }
    }

    // MARK: - Removal (K3 cascade: deleting a queue entry deletes its cache)

    /// Cancels any in-flight download for `url`, deletes the file and the
    /// meta row.
    public func remove(url: String) async {
        inFlight[url]?.cancel()
        inFlight[url] = nil
        if let row = await meta.entry(forURL: url), let name = row.relativePath {
            try? FileManager.default.removeItem(at: directory.appendingPathComponent(name))
        }
        await meta.delete(forURL: url)
    }

    // MARK: - LRU cleanup (fork cache_store semantics)

    private func scheduleCleanup() {
        let now = nowMilliseconds()
        guard now - lastCleanupAt >= configuration.cleanupMinimumIntervalMilliseconds else { return }
        lastCleanupAt = now
        cleanupTask = Task { await self.cleanupOnce() }
    }

    /// One cleanup round — public so tests (and a future settings UI) can
    /// force it deterministically.
    public func cleanupOnce() async {
        let now = nowMilliseconds()
        let capacity = await maxObjects()
        var deletedIDs = Set<Int64>()

        // ① Over capacity: drop the OLDEST (count − capacity) rows — in
        //   touched-ASC order that is the list's HEAD. `suffix` here would
        //   evict the newest; that inversion survived the first review.
        let ordered = await meta.rowsOrderedByTouched()
        if ordered.count > capacity {
            let overflowCount = ordered.count - capacity
            let candidates = ordered.prefix(overflowCount)
                .filter { row in
                    guard let touched = row.touched else { return false }
                    return now - touched > configuration.touchGraceMilliseconds
                }
                .prefix(configuration.cleanupBatchLimit)
            for row in candidates {
                await deleteRow(row)
                if let id = row._id { deletedIDs.insert(id) }
            }
        }

        // ② Past validTill (the 30-day stale period, or the origin's own
        //   max-age): the same per-round cap applies.
        let stale = await meta.allRows()
            .filter { row in
                guard let validTill = row.validTill else { return false }
                return validTill < now
            }
            .filter { row in
                row._id.map { !deletedIDs.contains($0) } ?? true
            }
            .prefix(configuration.cleanupBatchLimit)
        for row in stale {
            await deleteRow(row)
        }
    }

    private func deleteRow(_ row: CacheMetaDatabase.CacheObjectRow) async {
        if let name = row.relativePath {
            try? FileManager.default.removeItem(at: directory.appendingPathComponent(name))
        }
        if let id = row._id {
            await meta.delete(_id: id)
        } else if let url = row.url {
            await meta.delete(forURL: url)
        }
    }

    // MARK: - Name / expiry helpers

    /// `<uuidv1><ext>`: a fresh time-based UUID for a new object; an
    /// existing object keeps its name unless the extension changed.
    static func fileName(
        for existingRow: CacheMetaDatabase.CacheObjectRow?,
        contentType: String?,
        now: Int64
    ) -> String {
        let ext = fileExtension(forContentType: contentType)
        if let oldName = existingRow?.relativePath, oldName.hasSuffix(ext) {
            return oldName
        }
        return UUIDv1.generate(nowMilliseconds: now) + ext
    }

    /// `validTill` from HTTP cache headers when the origin states a max-age
    /// (the real-device fixture follows `Cache-Control: max-age=604800`),
    /// else `now + stalePeriod`.
    static func validTill(response: HTTPURLResponse, now: Int64, stalePeriod: Int64) -> Int64 {
        let maxAgeMilliseconds: Int64? = response.value(forHTTPHeaderField: "Cache-Control")?
            .split(separator: ",")
            .compactMap { part -> Int64? in
                let trimmed = part.trimmingCharacters(in: .whitespaces)
                guard trimmed.lowercased().hasPrefix("max-age=") else { return nil }
                return Int64(trimmed.dropFirst("max-age=".count)) .map { $0 * 1000 }
            }
            .first
        guard let maxAge = maxAgeMilliseconds else { return now + stalePeriod }
        if let date = response.value(forHTTPHeaderField: "Date").flatMap({ Self.parseHTTPDate($0) }) {
            return date + maxAge
        }
        return now + maxAge
    }

    static func parseHTTPDate(_ string: String) -> Int64? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "GMT")
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        guard let date = formatter.date(from: string) else { return nil }
        return Int64(date.timeIntervalSince1970 * 1000)
    }

    /// Content-Type → extension (fork mime_converter): known audio types by
    /// table, `application/octet-stream` → `.bin`, anything else falls back
    /// to `.<subtype>` (observed on real data: an `.m4a` URL served as
    /// audio/mp4 is stored as `.mp4`).
    static func fileExtension(forContentType contentType: String?) -> String {
        guard let contentType,
              let mime = contentType.split(separator: ";").first?
                  .trimmingCharacters(in: .whitespaces).lowercased(),
              !mime.isEmpty
        else { return ".bin" }
        let known: [String: String] = [
            "audio/mpeg": ".mp3",
            "audio/mp3": ".mp3",
            "audio/mp4": ".mp4",
            "audio/x-m4a": ".m4a",
            "audio/m4a": ".m4a",
            "audio/aac": ".aac",
            "audio/aacp": ".aac",
            "audio/x-aac": ".aac",
            "audio/ogg": ".ogg",
            "audio/opus": ".opus",
            "audio/wav": ".wav",
            "audio/x-wav": ".wav",
            "audio/x-mpegurl": ".m3u8",
            "video/mp4": ".mp4",
        ]
        if let ext = known[mime] { return ext }
        if mime == "application/octet-stream" { return ".bin" }
        let subType = mime.split(separator: "/").last.map { ".\($0)" } ?? ".bin"
        return subType
    }
}

// MARK: - UUID v1

/// Time-based UUID generation matching the fork's file-name convention
/// (`Uuid().v1()`). The values themselves are opaque — everything resolves
/// through the meta DB — but the shape stays v1 (version nibble 1,
/// RFC-4122 variant) so natively-written names are indistinguishable from
/// the shipped app's.
enum UUIDv1 {
    /// 100-ns intervals between 1582-10-15 (Gregorian start) and 1970-01-01.
    private static let gregorianOffset: Int64 = 0x01B2_1DD2_1381_4000

    static func generate(nowMilliseconds: Int64, node: UInt64? = nil) -> String {
        let ticks = nowMilliseconds * 10_000 + gregorianOffset
        let timeLow = UInt32(truncatingIfNeeded: ticks & 0xFFFF_FFFF)
        let timeMid = UInt16(truncatingIfNeeded: (ticks >> 32) & 0xFFFF)
        let timeHi = UInt16(truncatingIfNeeded: (ticks >> 48) & 0x0FFF) | (1 << 12)
        let clockSequence: UInt16
        var nodeValue: UInt64
        if let node {
            clockSequence = UInt16(truncatingIfNeeded: node >> 48)
            nodeValue = node & 0xFFFF_FFFF_FFFF
        } else {
            clockSequence = UInt16.random(in: 0...0x3FFF)
            nodeValue = UInt64.random(in: 0...0xFFFF_FFFF_FFFF) | (UInt64(1) << 40) // multicast bit
        }
        let variant = (clockSequence & 0x3FFF) | 0x8000

        func hex(_ value: some FixedWidthInteger, _ width: Int) -> String {
            let digits = String(value, radix: 16, uppercase: false)
            return String(repeating: "0", count: max(0, width - digits.count)) + digits
        }
        return "\(hex(timeLow, 8))-\(hex(timeMid, 4))-\(hex(timeHi, 4))"
            + "-\(hex(variant, 4))-\(hex(nodeValue, 12))"
    }
}
