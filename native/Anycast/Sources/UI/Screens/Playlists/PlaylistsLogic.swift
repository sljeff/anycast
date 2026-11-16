import UIKit
import AnycastKit

// MARK: - Reorder semantics (states/playlist_episode.dart:93-122, 05 §11 K26)

/// The drag-reorder decision core, extracted pure so the highest-risk
/// gesture of the migration (03 §3.2 / 05 §6.3 P0) is testable without a
/// collection view.
///
/// Coordinate convention: `from`/`to` are FINAL indices — the item's index
/// in the list before the move, and its index in the list after the move
/// (what the diffable reorder transaction reports). Dart's
/// ReorderableListView reports the UNADJUSTED gesture target and adjusts
/// with `if (to > from) { to -= 1 }`; `repositoryIndex` converts back,
/// because `PlaylistRepository.insertOrUpdateByIndex` takes the gesture
/// convention (`PlaylistPositioning.movePosition` re-applies the
/// adjustment itself).
enum PlaylistReorderLogic {

    struct MoveOutcome: Equatable {
        /// Slot in gesture space (list still containing the item at its old
        /// position) — the value to hand to
        /// `PlaylistRepository.insertOrUpdateByIndex`.
        let repositoryIndex: Int
        /// The item's index in the post-move list (where it landed).
        let finalIndex: Int
        /// from==0 or to==0: the drag entered/left the queue head, so the
        /// player must swap its source (playlists.dart §3.2).
        let swapsPlaybackSource: Bool
        /// The POST-reorder list head — what setByEpisode receives (the Dart
        /// closure ran after the synchronous reorder, reading the new top).
        let newHeadEnclosureURL: String?
        /// The reordered URL list (persist order).
        let reorderedURLs: [String]
    }

    /// Dart `move(from, to)`: `from == to` → early return (nil). The `to`
    /// clamp mirrors `PlaylistPositioning.movePosition`'s slot clamp.
    static func moveOutcome(from: Int, to: Int, urls: [String]) -> MoveOutcome? {
        guard from != to, urls.indices.contains(from) else { return nil }
        var list = urls
        let moved = list.remove(at: from)
        let finalIndex = min(max(to, 0), list.count)
        list.insert(moved, at: finalIndex)
        // Final → gesture space: a downward move's gesture target sits one
        // past the final slot (the `to -= 1` adjustment inverted).
        let repositoryIndex = to > from ? to + 1 : to
        return MoveOutcome(
            repositoryIndex: repositoryIndex,
            finalIndex: finalIndex,
            swapsPlaybackSource: from == 0 || to == 0,
            newHeadEnclosureURL: list.first,
            reorderedURLs: list
        )
    }

    /// Recovers (from, to) in FINAL coordinates from the before/after item
    /// lists plus the moved item's identity — the diffable `didReorder`
    /// transaction gives exactly these inputs.
    static func fromTo(movedURL: String, before: [String], after: [String]) -> (from: Int, to: Int)? {
        guard let from = before.firstIndex(of: movedURL),
              let to = after.firstIndex(of: movedURL),
              from != to else { return nil }
        return (from, to)
    }

    /// Applies a reorder to a row array (same math as `moveOutcome`, row
    /// flavored) — keeps the screen's in-memory order in lockstep with the
    /// persisted one.
    static func reorderedRows(_ rows: [PlaylistEpisodeRow], from: Int, to: Int) -> [PlaylistEpisodeRow]? {
        guard from != to, rows.indices.contains(from) else { return nil }
        var list = rows
        let moved = list.remove(at: from)
        let finalIndex = min(max(to, 0), list.count)
        list.insert(moved, at: finalIndex)
        return list
    }

    /// The reorder playback path as an ordered command list. Dart pauses,
    /// sleeps 100 ms, then `setByEpisode(episodes[0])`; the blocking sleep
    /// is cargo cult and NOT ported (08 §11.4 — PlaybackService.setByEpisode
    /// is documented as the reorder-involving-index-0 path), but the ORDER
    /// (pause before source swap, post-reorder head) is pinned here.
    enum PlaybackStep: Equatable {
        case pausePlayback
        case setSource(String)
    }

    static func playbackSteps(swapsPlaybackSource: Bool, newHeadEnclosureURL: String?) -> [PlaybackStep] {
        guard swapsPlaybackSource, let url = newHeadEnclosureURL, !url.isEmpty else { return [] }
        return [.pausePlayback, .setSource(url)]
    }
}

// MARK: - Per-playlist paging (playlists.dart:43-55, 03 §10.1)

/// The playlist page model: one page per playlist, swipe-only switching —
/// the Dart page deliberately renders a TabBarView with NO TabBar
/// (03 §10.1: "multiple playlists switch by horizontal swipe only").
/// Usually a single default list.
struct PlaylistPageModel: Equatable {

    var playlistIDs: [Int64]
    var currentIndex: Int

    init(playlistIDs: [Int64], currentIndex: Int = 0) {
        self.playlistIDs = playlistIDs
        self.currentIndex = currentIndex
    }

    var currentPlaylistID: Int64? {
        playlistIDs.indices.contains(currentIndex) ? playlistIDs[currentIndex] : nil
    }

    func page(after index: Int) -> Int? {
        index + 1 < playlistIDs.count ? index + 1 : nil
    }

    func page(before index: Int) -> Int? {
        index > 0 ? index - 1 : nil
    }

    /// The model rebuilds wholesale when the playlist table changes; the
    /// visible page is preserved by id when possible (DefaultTabController
    /// keyed pages by playlist id, playlists.dart:52).
    func replacingPlaylistIDs(_ ids: [Int64]) -> PlaylistPageModel {
        if let current = currentPlaylistID, let index = ids.firstIndex(of: current) {
            return PlaylistPageModel(playlistIDs: ids, currentIndex: index)
        }
        return PlaylistPageModel(playlistIDs: ids, currentIndex: 0)
    }
}

// MARK: - Playlist card display (card.dart:50-82 / 232-275)

/// Time-text + progress reducer for the playlist card variant. The CURRENT
/// episode reads live position data; every other row reads its stored
/// playedDuration (card.dart:65-81). The card shows the time left once
/// playback has started ("32m left", beside the meter) and the bare
/// duration before that ("42m").
enum PlaylistCardDisplay {

    struct Input {
        var isCurrentEpisode: Bool
        var livePositionMilliseconds: Int64
        var liveDurationMilliseconds: Int64
        var playedDurationMilliseconds: Int64?
        var durationMilliseconds: Int64?
        var pubDateMilliseconds: Int64?
        var nowEpochMilliseconds: Int64
    }

    static func rightText(_ input: Input) -> String {
        if input.isCurrentEpisode {
            return timeLeft(
                durationMilliseconds: input.liveDurationMilliseconds,
                playedMilliseconds: input.livePositionMilliseconds
            )
        }
        return timeLeft(
            durationMilliseconds: input.durationMilliseconds ?? 0,
            playedMilliseconds: input.playedDurationMilliseconds ?? 0
        )
    }

    /// `TimeFormats.formatRemainingTime` (the golden-pinned minute math)
    /// with the card's wording: "… left" instead of "… remaining"; an
    /// unplayed episode reads as its bare duration.
    static func timeLeft(durationMilliseconds: Int64, playedMilliseconds: Int64) -> String {
        let text = TimeFormats.formatRemainingTime(
            durationMilliseconds: durationMilliseconds,
            playedMilliseconds: playedMilliseconds
        )
        let remaining = " remaining"
        guard text.hasSuffix(remaining) else { return text }
        return String(text.dropLast(remaining.count)) + " left"
    }

    /// playbackProgress (formatters.dart:80-87): clamped 0…1, 0 for a
    /// non-positive duration.
    static func progressFraction(_ input: Input) -> Double {
        let position: Int64
        let duration: Int64
        if input.isCurrentEpisode {
            position = input.livePositionMilliseconds
            duration = input.liveDurationMilliseconds
        } else {
            position = input.playedDurationMilliseconds ?? 0
            duration = input.durationMilliseconds ?? 0
        }
        guard duration > 0 else { return 0 }
        let fraction = Double(position) / Double(duration)
        return min(max(fraction, 0), 1)
    }
}

/// Download indicator mapping (card.dart:232-275): the old CacheController
/// exposed null (not downloaded) / progress 0…1 / FileInfo (complete, the
/// `progress >= 1` check). The native inputs are the live
/// `PlaybackService.cacheStates` map (play-driven downloads), the screen's
/// own manual-download progress, and the cold-start disk check
/// (`CacheController.onInit` populated from disk).
enum PlaylistDownloadDisplay {

    static func display(
        cacheState: Double?,
        manualProgress: Double?,
        diskCached: Bool
    ) -> DownloadDisplay {
        let live = cacheState ?? manualProgress
        if let progress = live {
            return progress >= 1 ? .downloaded : .downloading(max(0, min(progress, 1)))
        }
        return diskCached ? .downloaded : .notDownloaded
    }
}

// MARK: - AI transcribe icon (play_icon.dart AIIcon, playlists.dart:154-180)

    /// Four-state AI transcribe display. The Dart `subtitleUrls` map carried
    /// nil / "processing" / "succeeded" / "failed"; any other server string
    /// matched no switch case (icon: default transcript mark, tap: no-op) —
    /// kept as `.unknown` for exact parity. Success stays a filled check
    /// (fill = success). Failure is the outline triangle.
enum AITranscriptDisplay: Equatable {
    case `default`
    case processing
    case succeeded
    case failed
    case unknown

    static func display(status: String?) -> AITranscriptDisplay {
        switch status {
        case .none: return .default
        case "processing": return .processing
        case "succeeded": return .succeeded
        case "failed": return .failed
        default: return .unknown
        }
    }

    var icon: UIImage {
        switch self {
        case .succeeded:
            return AppIcons.checkCircle
        case .failed:
            return AppIcons.transcriptFailed
        case .default, .processing, .unknown:
            return AppIcons.aiTranscript
        }
    }

    /// Succeeded tints in ink, failed in the error role — the processing
    /// state renders the robot lottie, not a tinted icon.
    var tintColor: UIColor {
        switch self {
        case .succeeded: return Theme.onSurface
        case .failed: return Theme.error
        default: return Theme.onSurface
        }
    }
}

/// The AI tap behavior (playlists.dart:154-180): default and failed →
/// request the transcript; succeeded/processing → informational toasts.
/// The Dart snackbar title ("Error"/"Success"/"Generating") has no room in
/// the shared single-line toast, so the MESSAGE copy is ported verbatim.
enum AITranscriptAction: Equatable {
    case requestTranscript
    case toast(String)
    case none

    static func action(display: AITranscriptDisplay) -> AITranscriptAction {
        switch display {
        case .default, .failed:
            // Failed retries in place, the same as the detail row and the
            // transcript page.
            return .requestTranscript
        case .succeeded:
            return .toast("You can check the transcript when playing.")
        case .processing:
            return .toast("Generating transcript may take 2 ~ 5 minutes...")
        case .unknown:
            return .none
        }
    }
}

// MARK: - Remove with Undo

/// The decisions and writes behind "Removed from Playlist · Undo". A removal
/// is either DEFERRED (the row only leaves the displayed list; the delete
/// runs when the Undo window ends) or EAGER (the row is deleted at once and
/// Undo re-inserts it): the in-memory playback queue still holds every row
/// it loaded, so a row the player may reach before the window ends cannot be
/// left stored.
enum PlaylistRemovalLogic {

    /// Eager when the row is playing, or is the NEXT item of this playlist's
    /// in-memory queue (a head completion would advance straight into it).
    static func isEager(
        url: String,
        wasCurrent: Bool,
        playlistId: Int64,
        playingPlaylistId: Int64?,
        queueURLs: [String]
    ) -> Bool {
        if wasCurrent { return true }
        guard playingPlaylistId == playlistId, let index = queueURLs.firstIndex(of: url) else { return false }
        return index <= 1
    }

    /// The list a screen renders: the stored rows without the one pending.
    static func displayed(_ rows: [PlaylistEpisodeRow], excluding pendingURL: String?) -> [PlaylistEpisodeRow] {
        guard let pendingURL else { return rows }
        return rows.filter { $0.enclosureUrl != pendingURL }
    }

    /// A deferred removal waits only while the playing episode is the one it
    /// was started under; any change commits it.
    static func shouldCommitOnTrackChange(
        pendingURL: String?, currentURLAtRemoval: String?, currentURL: String?
    ) -> Bool {
        pendingURL != nil && currentURL != currentURLAtRemoval
    }

    /// The stored row and its index, captured right before an eager delete.
    static func snapshot(
        url: String, playlistId: Int64, repository: PlaylistRepository
    ) async -> (row: PlaylistEpisodeRow, index: Int)? {
        let rows = (try? await repository.listEpisodes(playlistId: playlistId)) ?? []
        guard let index = rows.firstIndex(where: { $0.enclosureUrl == url }) else { return nil }
        return (rows[index], index)
    }

    /// Re-inserts an eagerly removed row at its original index; every column
    /// (playedDuration included) comes from the captured row.
    static func reinsert(
        _ row: PlaylistEpisodeRow, at index: Int, playlistId: Int64, repository: PlaylistRepository
    ) async {
        try? await repository.insertOrUpdateByIndex(row, playlistId: playlistId, index: index)
    }
}

// MARK: - Queue summary (list-end footer)

/// The line that closes the Playlist list: how much is left to hear and when
/// the queue would end at the current speed. Pure, so it can be recomputed
/// on list and speed changes only and tested without a list.
enum PlaylistQueueSummary {

    /// One queued episode: its duration and how much of it has been played.
    /// Unknown (nil) values contribute nothing.
    struct Row: Equatable {
        var durationMilliseconds: Int64?
        var playedMilliseconds: Int64?
    }

    /// The footer copy in two runs: the emphasised amount and the rest.
    struct Text: Equatable {
        /// "2 h 14 m" / "42 m" (ink, semibold).
        var emphasis: String
        /// " left · done around 9:41 PM at 1.5×" (sand).
        var rest: String
        var plain: String { emphasis + rest }
    }

    /// Σ max(0, duration − played) over the queue.
    static func remainingMilliseconds(rows: [Row]) -> Int64 {
        rows.reduce(0) { total, row in
            total + max(0, (row.durationMilliseconds ?? 0) - (row.playedMilliseconds ?? 0))
        }
    }

    /// Whole minutes (rounded, at least 1): "42 m", "2 h 14 m".
    static func amountText(milliseconds: Int64) -> String {
        let minutes = max(1, Int((Double(milliseconds) / 60_000).rounded()))
        guard minutes >= 60 else { return "\(minutes) m" }
        return "\(minutes / 60) h \(minutes % 60) m"
    }

    /// The device's short time style ("9:41 PM" / "21:41").
    static func makeTimeFormatter() -> DateFormatter {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }

    /// nil when nothing is left to say: an empty queue, or one whose
    /// durations are unknown or fully played.
    static func text(
        rows: [Row],
        speed: Double,
        now: Date,
        timeFormatter: DateFormatter = makeTimeFormatter()
    ) -> Text? {
        let remaining = remainingMilliseconds(rows: rows)
        guard !rows.isEmpty, remaining > 0 else { return nil }
        let effectiveSpeed = speed.isFinite && speed > 0 ? speed : 1
        let finish = now.addingTimeInterval(Double(remaining) / 1000 / effectiveSpeed)
        return Text(
            emphasis: amountText(milliseconds: remaining),
            rest: " left · done around \(timeFormatter.string(from: finish)) at \(PlayerSliderMath.speedText(effectiveSpeed))"
        )
    }
}

// MARK: - Pull-up to History (list end)

/// Pull-up-past-the-end math. The distance is measured against the REAL
/// maximum offset, which already contains `contentInset.bottom` extensions
/// (the action group adds one while it is open): callers pass the adjusted
/// insets, never a fixed constant.
enum PlaylistHistoryPull {

    /// Overscroll at which the orb is full and a release opens History.
    static let fullDistance: CGFloat = 72

    /// Points dragged past the maximum offset (0 inside the content).
    static func overscroll(
        offsetY: CGFloat,
        contentHeight: CGFloat,
        viewportHeight: CGFloat,
        adjustedInsetTop: CGFloat,
        adjustedInsetBottom: CGFloat
    ) -> CGFloat {
        let minimum = -adjustedInsetTop
        // A list shorter than the viewport rests at its minimum offset.
        let maximum = max(minimum, contentHeight - viewportHeight + adjustedInsetBottom)
        return max(0, offsetY - maximum)
    }

    /// 0…1 over `fullDistance`.
    static func progress(overscroll: CGFloat) -> CGFloat {
        guard overscroll.isFinite else { return 0 }
        return min(max(overscroll / fullDistance, 0), 1)
    }

    /// Releasing at full pull opens History; anything less springs back.
    static func opensOnRelease(progress: CGFloat) -> Bool {
        progress >= 1
    }
}
