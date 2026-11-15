import Foundation

/// Position allocation for `playlistEpisode.position` (REAL ordering key).
///
/// Two entry points (docs/migration/05 §1.5 G1/G2 + K26):
/// - **Insert** (episode not yet in the playlist): a byte-identical port of
///   the Dart neighbor math from `insertOrUpdateByIndex`
///   (models/playlist_episode.dart:90-125), evaluated against the
///   pre-insert ordered list. Golden-pinned by G1/G2.
/// - **Move** (episode already in the playlist): the K26 fix — neighbors are
///   taken from the list *after* the item moves to its target slot. The old
///   algorithm kept reading neighbors from the pre-move DB list, so a
///   downward move computed a midpoint that landed back at the old position
///   and the reorder safety net never fired (survived only until restart).
public enum PlaylistPositioning {

    /// playlist_episode.dart:26
    public static let minPositionGap: Double = 0.0005

    public struct Result: Equatable {
        public let position: Double
        /// Neighbors sandwiching the target slot closer than
        /// `minPositionGap`: the whole playlist must be renumbered 0…n-1.
        public let needsReorder: Bool
    }

    /// Insert semantics. `orderedPositions` mirror the FULL ordered list
    /// (ORDER BY position ASC — SQLite puts NULLs first), index-aligned:
    /// element i is row i's position, nil for a NULL-position row. Dart
    /// reads `episodes[i].position` off the full list and a nil neighbor
    /// means "no neighbor on that side" (models/playlist_episode.dart:
    /// 96-99) — dropping the nils (compactMap) would shift every lookup.
    public static func insertPosition(at index: Int, orderedPositions: [Double?]) -> Result {
        let left = index > 0 ? orderedPositions[index - 1] : nil
        let right = index < orderedPositions.count ? orderedPositions[index] : nil
        return neighborMath(left: left, right: right)
    }

    /// Move semantics (K26-fixed). `from` is the item's current index in
    /// `orderedPositions`; `to` is the caller's target index in the
    /// post-move list **including** the item at its old slot — i.e. exactly
    /// the `from`/`to` the drag gesture reports, matching the Dart
    /// controller's `if (to > from) { to -= 1 }` adjustment.
    public static func movePosition(from: Int, to: Int, orderedPositions: [Double?]) -> Result {
        guard orderedPositions.indices.contains(from) else {
            return Result(position: 0, needsReorder: false)
        }
        var slots = orderedPositions
        slots.remove(at: from)
        let target = (to > from) ? to - 1 : to
        let clamped = min(max(target, 0), slots.count)
        return insertPosition(at: clamped, orderedPositions: slots)
    }

    /// The shared neighbor math (playlist_episode.dart:100-113):
    /// both neighbors → midpoint (too close triggers renumbering); only
    /// left → left + 3·gap; only right → right − 3·gap; empty list → 0.
    private static func neighborMath(left: Double?, right: Double?) -> Result {
        if let left, let right {
            return Result(
                position: (left + right) / 2,
                needsReorder: (right - left) < minPositionGap
            )
        }
        if let left {
            return Result(position: left + minPositionGap * 3, needsReorder: false)
        }
        if let right {
            return Result(position: right - minPositionGap * 3, needsReorder: false)
        }
        return Result(position: 0, needsReorder: false)
    }

    /// `_reorder` (playlist_episode.dart:127-135): renumber the ordered list
    /// to 0…n-1.
    public static func renumberedPositions(count: Int) -> [Double] {
        (0..<count).map(Double.init)
    }
}
