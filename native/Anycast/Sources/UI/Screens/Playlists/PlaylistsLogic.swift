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

/// Right-text + progress-backdrop reducer for the playlist card variant.
/// The CURRENT episode reads live position data; every other row reads its
/// stored playedDuration (card.dart:65-81).
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
            return TimeFormats.formatRemainingTime(
                durationMilliseconds: input.liveDurationMilliseconds,
                playedMilliseconds: input.livePositionMilliseconds
            )
        }
        let duration = input.durationMilliseconds ?? 0
        let played = input.playedDurationMilliseconds ?? 0
        if played > 0 {
            return TimeFormats.formatRemainingTime(
                durationMilliseconds: duration,
                playedMilliseconds: played
            )
        }
        // Unplayed rows keep the generic card meta (card.dart:50-51).
        let durationText = TimeFormats.formatDuration(duration)
        let dateText = TimeFormats.formatDatetime(
            input.pubDateMilliseconds ?? 0,
            nowEpochMilliseconds: input.nowEpochMilliseconds
        )
        return "\(durationText) • \(dateText)"
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
/// matched no switch case (icon: default sparkle, tap: no-op) — kept as
/// `.unknown` for exact parity.
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
            return AppIcons.smsFailed
        case .default, .processing, .unknown:
            return AppIcons.aiTranscript ?? UIImage()
        }
    }

    /// Succeeded/failed tint (grass9 dark 0x63C174 — the same green the
    /// download-done check uses — / the dark error red) — the processing
    /// state renders the robot lottie, not a tinted icon.
    var tintColor: UIColor {
        switch self {
        case .succeeded: return UIColor(red: 0x63 / 255, green: 0xC1 / 255, blue: 0x74 / 255, alpha: 1)
        case .failed: return UIColor(red: 0xFF / 255, green: 0x8B / 255, blue: 0x8B / 255, alpha: 1)
        default: return Theme.primaryBackgroundDark
        }
    }
}

/// The AI tap behavior (playlists.dart:154-180): default → request the
/// transcript; failed → drop the stale record then surface the error
/// toast; succeeded/processing → informational toasts. The Dart snackbar
/// title ("Error"/"Success"/"Generating") has no room in the shared
/// single-line toast, so the MESSAGE copy is ported verbatim.
enum AITranscriptAction: Equatable {
    case requestTranscript
    case removeStaleRecord
    case toast(String)
    case none

    static func action(display: AITranscriptDisplay) -> AITranscriptAction {
        switch display {
        case .default:
            return .requestTranscript
        case .failed:
            return .removeStaleRecord
        case .succeeded:
            return .toast("You can check the transcript when playing.")
        case .processing:
            return .toast("Generating transcript may take 2 ~ 5 minutes...")
        case .unknown:
            return .none
        }
    }

    /// The toast shown for the failed branch after the stale record drops
    /// (Dart 'Error' snackbar body).
    static let failedToastMessage = "Transcript generation failed, please try again later."
}
