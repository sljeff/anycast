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

extension InboxRefreshTrigger {

    /// Only a user-initiated trigger shows the refresh control and reveals
    /// it. Every automatic trigger (and the subscription-change path) runs
    /// silently: the list a reader is looking at never moves.
    var revealsRefreshControl: Bool {
        switch self {
        case .pull, .tabRetapAtTop: return true
        case .firstAppear, .delayedAuto, .periodicAuto: return false
        }
    }
}

/// The header status line, pure. The line is always one line of the same
/// font (never nil), so the header's height never changes with the state.
enum InboxHeaderStatus {

    /// A silent refresh in flight reads "Updating…"; a finished one that
    /// added `newCount` rows reads "N new · updated {relative}"; everything
    /// else is "updated {relative} · {n} unlistened".
    static func text(
        isUpdating: Bool,
        newCount: Int,
        lastRefresh: Date?,
        episodeCount: Int,
        now: Date = Date()
    ) -> String {
        if isUpdating { return "Updating…" }
        let relative: String
        if let lastRefresh {
            let milliseconds = Int64(lastRefresh.timeIntervalSince1970 * 1000)
            relative = RelativeTimeFormatter.format(milliseconds, now: now)
        } else {
            relative = "—"
        }
        let visibleNew = min(newCount, episodeCount)
        if visibleNew > 0 { return "\(visibleNew) new · updated \(relative)" }
        return "updated \(relative) · \(episodeCount) unlistened"
    }

    /// Rows in `current` whose enclosure URL was not in `known`.
    static func newRowCount(known: Set<String>, current: [FeedEpisodeRow]) -> Int {
        current.reduce(0) { count, row in
            guard let url = row.enclosureUrl, !known.contains(url) else { return count }
            return count + 1
        }
    }
}

/// Plain text for the inbox card descriptions, resolved before the list
/// renders so a card is final on its first layout.
struct InboxResolvedDescription: Equatable, Sendable {
    let html: String
    let plainText: String
}

nonisolated enum InboxDescriptionResolver {

    /// Resolves `rows` against `existing`: rows already resolved with the same
    /// HTML cost nothing, new or changed rows are parsed in parallel off the
    /// main actor, rows that left the list are dropped. Rows without an
    /// enclosure URL have no key and stay on the cell's HTML fallback.
    static func resolve(
        rows: [FeedEpisodeRow],
        existing: [String: InboxResolvedDescription],
        parse: @escaping @Sendable (String) -> String = { DisplayText.singleLine(fromHTML: $0) }
    ) async -> [String: InboxResolvedDescription] {
        var result: [String: InboxResolvedDescription] = [:]
        var pending: [(url: String, html: String)] = []
        for row in rows {
            guard let url = row.enclosureUrl, result[url] == nil else { continue }
            let html = row.description ?? ""
            if let known = existing[url], known.html == html {
                result[url] = known
            } else if html.isEmpty {
                result[url] = InboxResolvedDescription(html: "", plainText: "")
            } else {
                pending.append((url, html))
            }
        }
        guard !pending.isEmpty else { return result }
        await withTaskGroup(of: (String, InboxResolvedDescription).self) { group in
            for item in pending {
                group.addTask {
                    (item.url, InboxResolvedDescription(html: item.html, plainText: parse(item.html)))
                }
            }
            for await (url, resolved) in group {
                result[url] = resolved
            }
        }
        return result
    }

    /// The plain text for `row` when it is resolved against its CURRENT HTML.
    static func plainText(
        for row: FeedEpisodeRow, in resolved: [String: InboxResolvedDescription]
    ) -> String? {
        guard let url = row.enclosureUrl, let entry = resolved[url],
              entry.html == (row.description ?? "")
        else { return nil }
        return entry.plainText
    }
}

/// How the inbox card list moves from one render to the next, pure. A list
/// whose rows only appeared or left (everything else in the same order) is
/// applied as inserts and removes so unchanged cards stay put; anything else
/// falls back to a plain `reloadData`.
nonisolated enum InboxListDiff {

    enum Plan: Equatable {
        /// Same rows in the same order: nothing to apply.
        case unchanged
        /// Rebuild the whole list.
        case reload
        /// Indices in the OLD list to remove and in the NEW list to insert.
        case batch(removes: [Int], inserts: [Int])
    }

    static func plan(old: [String?], new: [String?], sectionsUnchanged: Bool) -> Plan {
        guard sectionsUnchanged, !old.isEmpty, !new.isEmpty else { return .reload }
        let oldURLs = old.compactMap { $0 }
        let newURLs = new.compactMap { $0 }
        // A nil URL has no identity, a duplicate has an ambiguous one.
        guard oldURLs.count == old.count, newURLs.count == new.count,
              Set(oldURLs).count == oldURLs.count, Set(newURLs).count == newURLs.count
        else { return .reload }
        if oldURLs == newURLs { return .unchanged }
        let oldSet = Set(oldURLs), newSet = Set(newURLs)
        // Rows that stayed must keep their relative order, else a row moved.
        guard oldURLs.filter(newSet.contains) == newURLs.filter(oldSet.contains) else { return .reload }
        let removes = oldURLs.indices.filter { !newSet.contains(oldURLs[$0]) }
        let inserts = newURLs.indices.filter { !oldSet.contains(newURLs[$0]) }
        return .batch(removes: removes, inserts: inserts)
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
    /// AnimatedPlaylistIndicator flies to the playlist tab. Native ordering
    /// note: the step runs AFTER the row has already left the inbox — the
    /// row animates away first, then the ball flies (the row "becomes a
    /// ball and jumps into the playlist"); the Dart flow flew first while
    /// the row lingered through the whole animation.
    case flyInAnimation
    /// insertOrUpdateByIndex at the resolved slot (addToTop uses 0). In the
    /// add flow this precedes the inbox removal: a process kill inside the
    /// removal/fly animation window must leave the episode safely in the
    /// playlist, not lost from both tables.
    case insertIntoPlaylist(Int)
    /// addToPlaylist no-op branch: this exact episode is currently playing
    /// (feed_episode.dart:88-91).
    case skipInsertCurrentlyPlaying
    /// removeByEnclosureUrls — every action ends with the episode leaving
    /// the inbox (single-row removals animate the row away).
    case removeFromInbox
    /// playByEpisode (play action only). Runs BEFORE the animated inbox
    /// removal so playback never waits out the deletion animation.
    case playInsertedEpisode
    /// The playback queue observes the default playlist (native equivalent
    /// of the Dart Obx reactivity over the playlist controller).
    case reloadPlaybackQueue
}

enum InboxActionPlanner {

    /// Side-effect order for one action, given the playback context that
    /// `addToPlaylist` consults (feed_episode.dart:80-108). The add flow
    /// commits the playlist insert FIRST (database-only; queue observers
    /// fire only at `reloadPlaybackQueue`), then animates the row out of
    /// the inbox, then runs the fly-in — the insert is durable before the
    /// visual sequence starts, so a kill mid-animation leaves the episode
    /// in the playlist instead of in neither table.
    static func steps(
        for action: InboxEpisodeAction,
        currentPlaylistId: Int64?,
        currentEnclosureURL: String?,
        episodeEnclosureURL: String?
    ) -> [InboxActionStep] {
        switch action {
        case .play:
            // addToTop(1, ep) → playByEpisode → removeByEnclosureUrls:
            // playback starts before the row animates away.
            return [.insertIntoPlaylist(0), .playInsertedEpisode, .removeFromInbox]

        case .addToPlaylist:
            var steps: [InboxActionStep] = []
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
            // The visual sequence: the row animates away FIRST, then the
            // ball flies (the insert above has already committed).
            steps.append(.removeFromInbox)
            steps.append(.flyInAnimation)
            return steps

        case .remove:
            return [.removeFromInbox]
        }
    }
}
