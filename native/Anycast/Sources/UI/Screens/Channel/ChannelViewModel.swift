import UIKit
import Observation
import AnycastKit

// MARK: - Fold geometry (channel.dart:248-541, pure)

/// Pure interpolation model of the pinned channel header — the exact
/// arithmetic of `ChannelHeaderDelegate.build` as a function of
/// `shrinkOffset`, so the scroll-driven fold stays testable and off the
/// layout engine (07 §2.3: transforms/opacity only, per 08 §11.2).
struct ChannelFoldGeometry: Equatable {

    static let handlerHeight: CGFloat = 6
    static let handlerGap: CGFloat = 16
    static let buttonRowHeight: CGFloat = 40
    static let coverTopGap: CGFloat = 16
    static let expandedCoverSize: CGFloat = 120
    static let collapsedCoverSize: CGFloat = 60
    static let collapsedCoverLeading: CGFloat = 16
    static let coverBottomGap: CGFloat = 12
    static let titleBoxHeight: CGFloat = 58
    static let maxTitleLeadingPadding: CGFloat = 84   // 60 + 24 (channel.dart:425)
    static let headerBottomGap: CGFloat = 10

    /// Top safe-area inset of the sheet's own view — never a fixed status
    /// bar number (07 §4: any window size must survive).
    var safeAreaTop: CGFloat

    /// minExtent = statusBar + 6 + 16 + 40 + 16 + 60 + 10 (channel.dart:258).
    var minExtent: CGFloat {
        safeAreaTop + Self.handlerHeight + Self.handlerGap + Self.buttonRowHeight
            + Self.coverTopGap + Self.collapsedCoverSize + Self.headerBottomGap
    }

    /// maxExtent = statusBar + 460 (channel.dart:262).
    var maxExtent: CGFloat { safeAreaTop + 460 }

    var maxShrink: CGFloat { maxExtent - minExtent }

    /// Cover top edge inside the header — pinned at 78 + safe area for every
    /// shrink value (channel.dart:311).
    var coverTop: CGFloat {
        safeAreaTop + Self.handlerHeight + Self.handlerGap + Self.buttonRowHeight
            + Self.coverTopGap
    }

    func clampedShrink(_ shrink: CGFloat) -> CGFloat {
        min(max(shrink, 0), maxShrink)
    }

    /// Gradient/header height = max(minExtent, maxExtent - shrinkOffset).
    func headerHeight(shrink: CGFloat) -> CGFloat {
        max(minExtent, maxExtent - clampedShrink(shrink))
    }

    /// Cover edge = max(120 - shrinkOffset, 60).
    func coverSize(shrink: CGFloat) -> CGFloat {
        max(Self.expandedCoverSize - clampedShrink(shrink), Self.collapsedCoverSize)
    }

    /// Cover leading (padded-content coordinates) =
    /// max(initLeft - shrinkOffset, 16), initLeft = paddedWidth/2 - 60.
    func coverLeading(shrink: CGFloat, paddedWidth: CGFloat) -> CGFloat {
        let initial = paddedWidth / 2 - Self.expandedCoverSize / 2
        return max(initial - clampedShrink(shrink), Self.collapsedCoverLeading)
    }

    /// Title container leading padding = min(60 + 24, shrinkOffset).
    func titleLeadingPadding(shrink: CGFloat) -> CGFloat {
        min(Self.maxTitleLeadingPadding, clampedShrink(shrink))
    }

    /// Secondary block opacity = max(1 - shrinkOffset / (maxExtent / 4), 0);
    /// fully hidden from maxExtent/4 on (channel.dart:437-440).
    func secondaryOpacity(shrink: CGFloat) -> CGFloat {
        max(1 - clampedShrink(shrink) / (maxExtent / 4), 0)
    }

    /// Vertical rise of the title block (and everything below it) while the
    /// two collapsing spacers above it shrink: min(120, s) + min(12, s).
    func contentRise(shrink: CGFloat) -> CGFloat {
        let s = clampedShrink(shrink)
        return min(s, Self.expandedCoverSize) + min(s, Self.coverBottomGap)
    }

    /// Gradient top stop = dominant color at 30% over the page background
    /// (Color.alphaBlend, channel.dart:280-285; dark alpha .30).
    static func gradientTopColor(rgb: UInt32) -> UInt32 {
        let background: UInt32 = 0x11_13_16
        func blend(_ channel: UInt32, _ shift: UInt32) -> UInt32 {
            ((rgb >> shift & 0xFF) * 30 + (background >> shift & 0xFF) * 70) / 100
        }
        return blend(rgb, 16) << 16 | blend(rgb, 8) << 8 | blend(rgb, 0)
    }

    /// UIColor form of the same blend, over the app's page background.
    /// Both colors resolve against explicit dark traits: the channel page
    /// is pinned dark, and `getRed` on a dynamic token otherwise resolves
    /// whatever traits the caller carries — a light-context resolve washed
    /// the pinned header into a pale band with unreadable text (09 §9a).
    static func blendOverBackground(
        _ dominant: UIColor,
        traits: UITraitCollection = UITraitCollection(userInterfaceStyle: .dark)
    ) -> UIColor {
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        dominant.resolvedColor(with: traits).getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        var bgRed: CGFloat = 0, bgGreen: CGFloat = 0, bgBlue: CGFloat = 0, bgAlpha: CGFloat = 0
        Theme.primaryBackgroundDark.resolvedColor(with: traits)
            .getRed(&bgRed, green: &bgGreen, blue: &bgBlue, alpha: &bgAlpha)
        return UIColor(
            red: red * 0.3 + bgRed * 0.7,
            green: green * 0.3 + bgGreen * 0.7,
            blue: blue * 0.3 + bgBlue * 0.7,
            alpha: 1
        )
    }
}

// MARK: - Pure reducers (channel.dart / 05 §11)

/// Subscription capsule tristate (channel.dart:558-592).
enum ChannelSubscriptionDisplay: Equatable {
    case loading
    case subscribe
    case unsubscribe

    /// Loading ONLY while the subscription status itself is unknown (the
    /// local DB exists-check) or the channel title is missing. Deliberate
    /// divergence from Dart, which gates on the full feed `isLoading` —
    /// here the capsule shows the locally-known state immediately instead
    /// of spinning through the network fetch.
    static func display(subscribed: Bool, subscriptionChecked: Bool, hasTitle: Bool) -> ChannelSubscriptionDisplay {
        guard subscriptionChecked, hasTitle else {
            return .loading
        }
        return subscribed ? .unsubscribe : .subscribe
    }
}

/// The Newest/Oldest OrderChooser ↔ isReversed mapping
/// (channel.dart:71-92: Newest = !isReversed).
enum ChannelOrderMapping {
    static func isReversed(selectedIndex: Int) -> Bool { selectedIndex == 1 }
    static func selectedIndex(isReversed: Bool) -> Int { isReversed ? 1 : 0 }
    /// showEpisodes = isReversed ? episodes.reversed() : episodes.
    static func showEpisodes(_ episodes: [FeedEpisodeRow], isReversed: Bool) -> [FeedEpisodeRow] {
        isReversed ? episodes.reversed() : episodes
    }
}

/// In-channel search filter (channel.dart:781-785): case-insensitive
/// `contains` over the title; a nil title contributes "" instead of
/// crashing (K4 family — `e.title!`).
enum ChannelSearchFilter {
    static func apply(_ query: String, to episodes: [FeedEpisodeRow]) -> [FeedEpisodeRow] {
        // Dart `contains("")` is true — an empty needle matches everything.
        let needle = query.lowercased()
        if needle.isEmpty { return episodes }
        return episodes.filter { ($0.title ?? "").lowercased().contains(needle) }
    }
}

/// Channel-page add-to-playlist gate (channel.dart:152-155 / 831-834): the
/// `if (inPlaylist) return` guard exists ONLY on Channel + ChannelSearch
/// (03 §2.6 correction) — the icon shows the check variant and taps no-op.
enum ChannelPlaylistGate {
    enum Action: Equatable { case flyInAndInsert, blocked }
    static func action(inPlaylist: Bool) -> Action {
        inPlaylist ? .blocked : .flyInAndInsert
    }
}

enum ChannelPlaylistLogic {
    static let defaultPlaylistID: Int64 = 1

    /// feed2playlist (states/feed_episode.dart:59-77).
    static func playlistRow(from episode: FeedEpisodeRow, playlistId: Int64) -> PlaylistEpisodeRow {
        PlaylistEpisodeRow(
            title: episode.title,
            description: episode.description,
            duration: episode.duration,
            enclosureUrl: episode.enclosureUrl,
            pubDate: episode.pubDate,
            imageUrl: episode.imageUrl,
            channelTitle: episode.channelTitle,
            rssFeedUrl: episode.rssFeedUrl,
            playlistId: playlistId,
            // feed2playlist explicitly maps 'playedDuration': 0
            // (states/feed_episode.dart:74) — a fresh queue row stores a
            // non-NULL zero, not NULL.
            playedDuration: 0
        )
    }

    /// addToPlaylist insertion slot (states/feed_episode.dart:87-100):
    /// target list is the current playlist and the episode IS the current
    /// episode → nil (no-op, keep the existing row); current playlist but a
    /// different episode → 1 (below the queue head); otherwise → 0 (top).
    static func addToPlaylistIndex(
        currentPlaylistId: Int64?,
        targetPlaylistId: Int64,
        currentEnclosureURL: String?,
        episodeEnclosureURL: String?
    ) -> Int? {
        guard currentPlaylistId == targetPlaylistId else { return 0 }
        if let current = currentEnclosureURL, !current.isEmpty,
           current == episodeEnclosureURL {
            return nil
        }
        return 1
    }
}

// MARK: - View model (lib/states/channel.dart)

/// Channel page state. Same-session reuse WITHOUT refetch is the K34 ruling
/// (05 §11: the Dart channel view model is cached by URL and retained across
/// sheet closes — replicate that exactly) — instances live in
/// `ChannelSessionStore` and survive sheet close for the whole session; only
/// a cache miss constructs and prepares one.
@MainActor
@Observable
final class ChannelViewModel {

    let rssFeedURL: String

    /// The seed subscription (PodcastCard / Detail reference); replaced
    /// wholesale by the fetched feed's subscription while the seed has no
    /// image URL (states/channel.dart:49-51).
    private(set) var channel: SubscriptionRow
    private(set) var episodes: [FeedEpisodeRow] = []
    private(set) var isLoading = true
    private(set) var subscribed = false
    /// Whether the local DB exists-check has settled — the subscription
    /// capsule can render before the network fetch finishes (it used to
    /// spin through the whole feed load).
    private(set) var subscriptionChecked = false
    var isReversed = false

    /// Header gradient dominant color; starts at playerWarm (0xFF867D75).
    private(set) var dominantColor = ChannelViewModel.playerWarmColor

    static let playerWarmColor = UIColor(
        red: 0x86 / 255, green: 0x7D / 255, blue: 0x75 / 255, alpha: 1
    )

    private let fetcher: RSSFetcher
    private let subscriptions: SubscriptionRepository
    private let feeds: FeedRepository
    private let palette: PaletteService

    init(
        rssFeedURL: String,
        seed: SubscriptionRow,
        fetcher: RSSFetcher,
        subscriptions: SubscriptionRepository,
        feeds: FeedRepository,
        palette: PaletteService
    ) {
        self.rssFeedURL = rssFeedURL
        self.channel = seed
        self.fetcher = fetcher
        self.subscriptions = subscriptions
        self.feeds = feeds
        self.palette = palette
    }

    var showEpisodes: [FeedEpisodeRow] {
        ChannelOrderMapping.showEpisodes(episodes, isReversed: isReversed)
    }

    var hasTitle: Bool { channel.title != nil }

    /// onInit → load(): exists-check, then the full single-URL RSS fetch
    /// (`listAllEpisodes`, onlyFirstEpisode: false — the P1 "always newest"
    /// behavior, 08 §11.2), then palette extraction.
    func prepare() async {
        do {
            subscribed = try await subscriptions.get(byRSSFeedURL: rssFeedURL) != nil
            subscriptionChecked = true
        } catch {
            // A failed exists-check keeps the previous/unknown state: the
            // Dart constructor reads the in-memory SubscriptionController
            // (states/channel.dart:31-32 — no failure path), so a transient
            // read error must not render as "not subscribed".
        }
        let podcasts = await fetcher.fetchPodcasts(urls: [rssFeedURL], onlyFirstEpisode: false)
        if let podcast = podcasts.first {
            episodes = podcast.feedEpisodes
            if (channel.imageUrl ?? "").isEmpty {
                channel = podcast.subscription
            }
        }
        isLoading = false
        await updatePalette()
    }

    /// _updateColor (states/channel.dart:37-43): no URL → keep current color.
    private func updatePalette() async {
        guard let urlString = channel.imageUrl, !urlString.isEmpty else { return }
        dominantColor = await palette.dominantColor(from: urlString)
    }

    /// subscribe() (states/channel.dart:55-63): newest episode enters the
    /// inbox, lastUpdated tracks it, then the subscription row is written.
    func subscribe() async {
        subscribed = true
        if let newest = episodes.first {
            try? await feeds.insertMany([newest])
            channel.lastUpdated = newest.pubDate
        }
        try? await subscriptions.addMany([channel])
    }

    func unsubscribe() async {
        subscribed = false
        try? await subscriptions.remove(channel)
    }
}

// MARK: - Session store (K34)

/// rssFeedURL-keyed cache of channel view models, kept across sheet closes
/// for the whole session — the native form of the Dart `Get.lazyPut(tag)`
/// reuse quirk (K34: replicate, 05 §11 / 08 §12.2). The factory is injectable
/// so the K34 hit/miss/invalidation behavior is testable.
@MainActor
final class ChannelSessionStore {

    static let shared = ChannelSessionStore()

    private var cache: [String: ChannelViewModel] = [:]
    private let injectedFactory: (@MainActor (String, SubscriptionRow?) -> ChannelViewModel)?

    init(factory: (@MainActor (String, SubscriptionRow?) -> ChannelViewModel)? = nil) {
        self.injectedFactory = factory
    }

    /// Production entry: returns the cached model (isNew = false, NO
    /// prepare — no refetch on same-session reopen) or constructs the live
    /// one through the injected context (isNew = true — the caller drives
    /// `prepare()`).
    func entry(
        context: UIContext,
        rssFeedURL: String,
        seed: SubscriptionRow? = nil
    ) -> (model: ChannelViewModel, isNew: Bool) {
        if let cached = cache[rssFeedURL] {
            return (cached, false)
        }
        let model: ChannelViewModel
        if let injectedFactory {
            model = injectedFactory(rssFeedURL, seed)
        } else {
            model = ChannelViewModel(
                rssFeedURL: rssFeedURL,
                seed: seed ?? SubscriptionRow(rssFeedUrl: rssFeedURL),
                fetcher: RSSFetcher(client: HTTPClient(), userAgent: AppConfiguration.rssUserAgent),
                subscriptions: context.database.subscriptionRepository(),
                feeds: context.database.feedRepository(),
                palette: context.palette
            )
        }
        cache[rssFeedURL] = model
        return (model, true)
    }

    /// Context-free variant for injected-factory stores (unit tests).
    func entry(
        rssFeedURL: String,
        seed: SubscriptionRow? = nil
    ) -> (model: ChannelViewModel, isNew: Bool) {
        guard let injectedFactory else {
            preconditionFailure("context-free entry requires an injected factory")
        }
        if let cached = cache[rssFeedURL] {
            return (cached, false)
        }
        let model = injectedFactory(rssFeedURL, seed)
        cache[rssFeedURL] = model
        return (model, true)
    }

    /// Test/future invalidation point; production never removes (K34).
    func remove(rssFeedURL: String) {
        cache[rssFeedURL] = nil
    }

    func removeAll() {
        cache.removeAll()
    }
}
