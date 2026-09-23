import Foundation

/// computeNewEpisodes (pages/feeds.dart) — the pure merge decision of an
/// inbox refresh (G8). Local-wins semantics: a subscription is only updated
/// when its stored lastUpdated is nil (first import) or strictly OLDER than
/// the fetched channel's newest pubDate.
public enum SaveNewEpisodes {

    public struct Result: Equatable, Sendable {
        public var subscriptions: [SubscriptionRow]
        public var feedEpisodes: [FeedEpisodeRow]
        public init(subscriptions: [SubscriptionRow], feedEpisodes: [FeedEpisodeRow]) {
            self.subscriptions = subscriptions
            self.feedEpisodes = feedEpisodes
        }
    }

    /// Port of computeNewEpisodes over value types. `fetched` mirrors the
    /// batch of parseFeedResponse outputs (nil = failed feed, skipped).
    /// K4/K5 tolerance: an episode without pubDate is skipped where Dart
    /// force-unwrapped and crashed.
    public static func compute(
        fetched: [PodcastImportData?],
        local subscriptions: [SubscriptionRow]
    ) -> Result {
        var fetchedByURL: [String: PodcastImportData] = [:]
        for entry in fetched {
            guard let entry, let url = entry.subscription.rssFeedUrl else { continue }
            fetchedByURL[url] = entry
        }

        var updatedSubscriptions: [SubscriptionRow] = []
        var updatedEpisodes: [FeedEpisodeRow] = []

        for subscription in subscriptions {
            guard let rssFeedUrl = subscription.rssFeedUrl,
                  let fetched = fetchedByURL[rssFeedUrl]
            else { continue }

            if let localLastUpdated = subscription.lastUpdated {
                // Dart dereferences `fetched.subscription!.lastUpdated!` here
                // and crashes when the fetched value is nil (a first episode
                // without pubDate); skipping the subscription is the port's
                // K4/K5 tolerance for that crash.
                guard let fetchedLastUpdated = fetched.subscription.lastUpdated else { continue }
                if localLastUpdated >= fetchedLastUpdated {
                    continue // local wins
                }
            }

            updatedSubscriptions.append(fetched.subscription)

            if subscription.lastUpdated == nil {
                // First import — or a stored NULL, which Dart treats the
                // same way: only the first (newest) episode is added.
                if let newest = fetched.feedEpisodes.first {
                    updatedEpisodes.append(newest)
                }
                continue
            }
            for episode in fetched.feedEpisodes {
                guard let pubDate = episode.pubDate,
                      pubDate > subscription.lastUpdated!
                else { continue }
                updatedEpisodes.append(episode)
            }
        }

        return Result(subscriptions: updatedSubscriptions, feedEpisodes: updatedEpisodes)
    }
}

/// parseFeedResponse (utils/rss_fetcher.dart:76-129) — the pure RSS body →
/// (subscription, episodes) mapping, G7. Byte-parity notes:
/// - channel description goes through htmlToText + trim; title is trimmed.
/// - imageUrl = <image><url> else itunes:image@href else "".
/// - categories = channel <category> texts joined with ",".
/// - items sorted by pubDate DESC; a nil pubDate sorts LAST (the Dart sort
///   crashed on nil — K5 fix, recorded in G7's note).
/// - onlyFirstEpisode: bound = 1 (or 0 when empty); an item without an
///   `<enclosure>` ELEMENT is SKIPPED but does NOT extend the bound — a feed
///   whose newest item lacks an enclosure imports zero episodes (shipped
///   quirk). An enclosure whose `url` attribute is missing still keeps the
///   episode with enclosureUrl = nil (Dart: RssEnclosure exists whenever the
///   element does; only `enclosure == null` skips).
/// - empty result → lastUpdated = import time (`now` injected for tests);
///   otherwise the FIRST episode's pubDate, even when nil — Dart stores NULL
///   (rss_fetcher.dart:123-127), and compute then keeps re-entering the
///   first-import branch until a dated episode arrives. Swallowing the NULL
///   into `now` would freeze the subscription forever (`now >= pubDate`).
public struct PodcastImportData: Equatable, Sendable {
    public var subscription: SubscriptionRow
    public var feedEpisodes: [FeedEpisodeRow]

    public init(subscription: SubscriptionRow, feedEpisodes: [FeedEpisodeRow]) {
        self.subscription = subscription
        self.feedEpisodes = feedEpisodes
    }
}

public enum PodcastFeedParser {

    public static func parse(
        rssFeedUrl: String,
        xmlData: Data,
        onlyFirstEpisode: Bool = true,
        nowEpochMilliseconds: Int64 = { Int64(Date().timeIntervalSince1970 * 1000) }()
    ) -> PodcastImportData? {
        guard let feed = RSSXMLParser.parse(data: xmlData) else { return nil }

        var subscription = SubscriptionRow()
        subscription.rssFeedUrl = rssFeedUrl
        subscription.title = feed.title?.dartTrimmed()
        subscription.description = HtmlText.htmlToText(feed.description).dartTrimmed()
        subscription.imageUrl = feed.imageURL ?? feed.iTunesImageHref ?? ""
        subscription.link = feed.link
        subscription.categories = feed.categories.joined(separator: ",")
        subscription.author = feed.iTunesAuthor
        subscription.email = feed.iTunesOwnerEmail

        // pubDate DESC via Dart's own (unstable, dual-pivot) sort — the
        // golden locks the exact order of equal-pubDate items. Missing
        // pubDates sort last (K5 tolerance; the Dart sort crashed on nil).
        let items = DartSort.sorted(feed.items) { lhs, rhs in
            switch (lhs.pubDateEpochMilliseconds, rhs.pubDateEpochMilliseconds) {
            case let (l?, r?): return r > l ? 1 : (r < l ? -1 : 0) // DESC
            case (nil, _?): return 1
            case (_?, nil): return -1
            default: return 0
            }
        }

        var feedEpisodes: [FeedEpisodeRow] = []
        var length = onlyFirstEpisode ? 1 : items.count
        if items.isEmpty { length = 0 }

        for index in 0..<length {
            let item = items[index]
            guard item.hasEnclosure else { continue }

            var episode = FeedEpisodeRow()
            episode.title = item.title?.dartTrimmed()
            episode.description = item.iTunesSummary?.dartTrimmed()
                ?? item.description?.dartTrimmed()
            episode.duration = item.iTunesDurationMilliseconds
            episode.enclosureUrl = item.enclosureURL
            episode.pubDate = item.pubDateEpochMilliseconds
            episode.imageUrl = item.iTunesImageHref ?? subscription.imageUrl
            episode.channelTitle = subscription.title
            episode.rssFeedUrl = subscription.rssFeedUrl
            feedEpisodes.append(episode)
        }

        subscription.lastUpdated = feedEpisodes.isEmpty
            ? nowEpochMilliseconds
            : feedEpisodes[0].pubDate
        return PodcastImportData(subscription: subscription, feedEpisodes: feedEpisodes)
    }
}
