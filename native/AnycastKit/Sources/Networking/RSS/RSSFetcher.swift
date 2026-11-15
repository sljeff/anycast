import Foundation

/// RSS batch fetching (utils/rss_fetcher.dart + http_client.dart
/// fetchConcurrentWithRetry): 8 URLs per concurrent batch, per-URL
/// fetchWithRetry semantics (10 s timeout, 2 total attempts, only transport
/// failures retried, failure skips the source), pinned browser UA (K20).
/// Parsing is pure (`PodcastFeedParser`) and runs on the concurrent executor
/// (docs/migration/06 §4: multi-megabyte decode never touches MainActor).
public struct RSSFetcher: Sendable {

    public static let batchConcurrent = 8

    public let client: HTTPClient
    public let userAgent: String

    public init(client: HTTPClient, userAgent: String) {
        self.client = client
        self.userAgent = userAgent
    }

    /// - Parameters:
    ///   - onBatch: mirrors TempResult — (batchStartIndex, total, parsed
    ///     results with nil for failed sources).
    public func fetchPodcasts(
        urls: [String],
        onlyFirstEpisode: Bool = true,
        onBatch: (@Sendable (Int, Int, [PodcastImportData?]) -> Void)? = nil
    ) async -> [PodcastImportData] {
        var podcasts: [PodcastImportData] = []

        var index = 0
        while index < urls.count {
            let end = min(index + Self.batchConcurrent, urls.count)
            let chunk = Array(urls[index..<end])

            // The batch's ≤8 requests fly concurrently; results keep the
            // chunk's order (nil = failed source, skipped).
            let results: [PodcastImportData?] = await withTaskGroup(
                of: (Int, PodcastImportData?).self
            ) { group in
                for (offset, url) in chunk.enumerated() {
                    group.addTask {
                        await (offset, self.fetchAndParse(url: url, onlyFirstEpisode: onlyFirstEpisode))
                    }
                }
                var byIndex: [Int: PodcastImportData?] = [:]
                for await (offset, podcast) in group {
                    byIndex[offset] = podcast
                }
                return (0..<chunk.count).map { byIndex[$0] ?? nil }
            }

            for case let podcast? in results {
                podcasts.append(podcast)
            }
            onBatch?(index, urls.count, results)

            index = end
        }

        return podcasts
    }

    @concurrent
    private func fetchAndParse(url: String, onlyFirstEpisode: Bool) async -> PodcastImportData? {
        let request = HTTPClient.Request(
            url: URL(string: url) ?? URL(fileURLWithPath: "/"),
            timeout: 10,
            userAgent: userAgent
        )
        // fetchWithRetry: network failure after retries → nil → source skipped.
        guard let response = try? await client.send(request, maxAttempts: 2),
              response.is2xx
        else { return nil }
        return PodcastFeedParser.parse(
            rssFeedUrl: url,
            xmlData: response.body,
            onlyFirstEpisode: onlyFirstEpisode
        )
    }
}
