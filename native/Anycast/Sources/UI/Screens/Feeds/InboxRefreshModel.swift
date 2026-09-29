import Foundation
import AnycastKit

/// The complete inbox refresh trigger set, extracted pure (feeds.dart +
/// states/feed_episode.dart, 03 §2.3):
/// - `firstAppear` — EasyRefresh `refreshOnStart: true` fires once when the
///   page is first built.
/// - `delayedAuto` — `Future.delayed(2 s)` → `autoFetch()` (feed_episode.dart:34-37).
/// - `periodicAuto` — `Timer.periodic(autoRefreshInterval)` → `autoFetch()`
///   (feed_episode.dart:121-132; interval read live from settings, DB
///   default 300 s, K36 restart-on-change).
/// - `pull` — the refresh header / UIRefreshControl (feeds.dart:33-37).
/// - `tabRetapAtTop` — Tab0 re-tap while at top calls `callRefresh()`
///   directly (bottom_nav_bar.dart:272).
enum InboxRefreshTrigger: Equatable {
    case firstAppear
    case delayedAuto
    case periodicAuto
    case pull
    case tabRetapAtTop

    /// Only the `autoFetch` paths pass through the 1-minute throttle
    /// (feed_episode.dart:110-119); pull / retap / refreshOnStart call the
    /// refresh flow directly.
    var passesAutoThrottle: Bool {
        switch self {
        case .delayedAuto, .periodicAuto: return true
        case .firstAppear, .pull, .tabRetapAtTop: return false
        }
    }
}

/// `lastRefresh` bookkeeping for the inbox (states/feed_episode.dart).
/// `autoFetch` skips when the last refresh is under a minute old;
/// `fetchNewEpisodes` stamps `lastRefresh = DateTime.now()` at its start —
/// every actual fetch, whatever triggered it, refreshes the stamp.
@MainActor
final class InboxRefreshGate {

    /// `const Duration(minutes: 1)` in autoFetch.
    static let autoThrottleSeconds: TimeInterval = 60

    private(set) var lastRefresh: Date?
    private let now: @MainActor () -> Date

    init(now: @escaping @MainActor () -> Date = { Date() }) {
        self.now = now
    }

    /// Whether `trigger` may start a refresh now. Permitted triggers stamp
    /// `lastRefresh` immediately (autoFetch stamps before `callRefresh`;
    /// every other path is stamped again by the fetch itself).
    func permits(_ trigger: InboxRefreshTrigger) -> Bool {
        if trigger.passesAutoThrottle,
           let last = lastRefresh,
           now().timeIntervalSince(last) < Self.autoThrottleSeconds {
            return false
        }
        markRefreshStarted()
        return true
    }

    /// fetchNewEpisodes' opening `lastRefresh = DateTime.now()` — the page
    /// calls this at the start of every actual fetch.
    func markRefreshStarted() {
        lastRefresh = now()
    }
}

/// Timer cadences of the inbox (states/feed_episode.dart + player.dart:451-453).
enum InboxRefreshSchedule {

    /// `Future.delayed(const Duration(seconds: 2))` after creation.
    static let delayedAutoSeconds: TimeInterval = 2

    /// The inbox/history trim tick (`Timer.periodic(minutes: 1)`).
    static let trimIntervalSeconds: TimeInterval = 60

    /// The auto-refresh interval, seconds. DB default 300 is the canonical
    /// caliber (01 §2 ruling); the settings box is loaded before any UIContext
    /// exists, so no timer is ever scheduled before settings load.
    static func autoRefreshInterval(from settings: AppSettings) -> TimeInterval {
        TimeInterval(settings.autoRefreshInterval)
    }
}

/// The 60-second overage trim decision (states/feed_episode.dart:134-147
/// `removeOld` + states/history.dart:54-67): rows arrive newest-first, keep
/// the first `max`, drop the overage. Boundary: `count == max` removes
/// nothing.
enum InboxTrimPlanner {

    struct Plan: Equatable {
        /// Indices of the overage rows in the newest-first list; empty when
        /// nothing needs removal.
        let removedIndices: Range<Int>

        var removesAnything: Bool { !removedIndices.isEmpty }
        var removedCount: Int { removedIndices.count }
    }

    static func plan(count: Int, keeping max: Int64) -> Plan {
        let limit = Swift.max(Int(max), 0)
        guard count > limit else { return Plan(removedIndices: 0..<0) }
        return Plan(removedIndices: limit..<count)
    }
}

/// The three inbox card actions (feeds.dart:84-131) and the exact order of
/// their side effects. The page executes these step lists verbatim; the
/// ordering is what the regression plan pins (05 §6.3, the Inbox
/// three-button row).
enum InboxEpisodeAction: Equatable {
    case play
    case addToPlaylist
    case remove
}

enum InboxActionStep: Equatable {
    /// AnimatedPlaylistIndicator flies FIRST; the insert happens in its
    /// completion (feeds.dart:104-128).
    case flyInAnimation
    /// insertOrUpdateByIndex at the resolved slot (addToTop uses 0).
    case insertIntoPlaylist(Int)
    /// addToPlaylist no-op branch: this exact episode is currently playing
    /// (feed_episode.dart:88-91).
    case skipInsertCurrentlyPlaying
    /// removeByEnclosureUrls — every action ends with the episode leaving
    /// the inbox.
    case removeFromInbox
    /// playByEpisode (play action only).
    case playInsertedEpisode
    /// The playback queue observes the default playlist (native equivalent
    /// of the Dart Obx reactivity over the playlist controller).
    case reloadPlaybackQueue
}

enum InboxActionPlanner {

    /// Side-effect order for one action, given the playback context that
    /// `addToPlaylist` consults (feed_episode.dart:80-108).
    static func steps(
        for action: InboxEpisodeAction,
        currentPlaylistId: Int64?,
        currentEnclosureURL: String?,
        episodeEnclosureURL: String?
    ) -> [InboxActionStep] {
        switch action {
        case .play:
            // addToTop(1, ep) → removeByEnclosureUrls → playByEpisode.
            return [.insertIntoPlaylist(0), .removeFromInbox, .playInsertedEpisode]

        case .addToPlaylist:
            var steps: [InboxActionStep] = [.flyInAnimation]
            let index = ChannelPlaylistLogic.addToPlaylistIndex(
                currentPlaylistId: currentPlaylistId,
                targetPlaylistId: ChannelPlaylistLogic.defaultPlaylistID,
                currentEnclosureURL: currentEnclosureURL,
                episodeEnclosureURL: episodeEnclosureURL
            )
            if let index {
                steps.append(.insertIntoPlaylist(index))
                if currentPlaylistId == ChannelPlaylistLogic.defaultPlaylistID {
                    steps.append(.reloadPlaybackQueue)
                }
            } else {
                steps.append(.skipInsertCurrentlyPlaying)
            }
            // addToPlaylist(...).then((_) => removeByEnclosureUrls(...)).
            steps.append(.removeFromInbox)
            return steps

        case .remove:
            return [.removeFromInbox]
        }
    }
}
