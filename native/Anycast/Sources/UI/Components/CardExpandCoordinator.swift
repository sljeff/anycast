import UIKit

/// Mutual exclusion for the card action strips in one list — the Dart
/// `CardListController` (lib/states/cardlist.dart): a `Card` tap toggles its
/// own strip and collapses any other expanded card in the SAME list (03
/// §2.11). Screens own one coordinator per list; on `onChange` they refresh
/// the affected cells (and animate item heights).
///
/// Contract: the stored `IndexPath` is a POSITION, not an identity. The
/// coordinator never re-resolves it against the data, so callers MUST
/// `close()` before any mutation of the underlying list (insert, delete,
/// move, reorder) — otherwise the shifted index can address the wrong card.
@MainActor
final class CardExpandCoordinator {

    /// The currently expanded index path, nil when all strips are closed.
    private(set) var expandedIndexPath: IndexPath?

    /// Fired after every change with the new expanded path (nil = closed).
    var onChange: ((IndexPath?) -> Void)?

    /// Whole-card tap behavior (card.dart:109-112): toggle this card's
    /// strip, collapsing any other.
    func toggle(at indexPath: IndexPath) {
        expandedIndexPath = (expandedIndexPath == indexPath) ? nil : indexPath
        onChange?(expandedIndexPath)
    }

    /// Expand an exact card (no toggle).
    func expand(at indexPath: IndexPath) {
        guard expandedIndexPath != indexPath else { return }
        expandedIndexPath = indexPath
        onChange?(expandedIndexPath)
    }

    /// Collapse everything (playlist reorder start does this, 03 §3.2).
    func close() {
        guard expandedIndexPath != nil else { return }
        expandedIndexPath = nil
        onChange?(nil)
    }
}

/// One animated expand/collapse pass for a card list (03 §2.11): pushes the
/// strip targets into the visible cells, then animates the item-size
/// re-validation. The height-defining constraint changes must settle BEFORE
/// the animated `invalidateLayout` — applied inside the same transaction the
/// compositional layout re-measured the cell against its pre-change size,
/// leaving the item collapsed while the strip overflowed the un-clipped
/// cell, painting buttons over neighbor cards and eating their taps.
@MainActor
enum CardExpandAnimator {

    /// 200 ms easeInOut — the Dart AnimatedContainer cadence.
    static func refresh(expandedPath: IndexPath?, in collectionView: UICollectionView) {
        // Phase 1 — apply the strip targets WITHOUT animation. Changing a
        // cell's height-defining constraint and re-validating inside the
        // SAME animation transaction makes the compositional layout
        // re-measure the cell against its pre-change size (the item stays
        // collapsed while the strip overflows it); settled first, the
        // re-measure below sees the final constraint values.
        UIView.performWithoutAnimation {
            for path in collectionView.indexPathsForVisibleItems {
                guard let cell = collectionView.cellForItem(at: path) as? EpisodeCardCell else { continue }
                cell.setExpanded(expandedPath == path)
            }
        }
        // Phase 2 — animate the item-height re-validation; the collection's
        // layout pass carries the strip reveal with the item resize.
        UIView.animate(
            withDuration: 0.2,
            delay: 0,
            options: [.curveEaseInOut, .allowUserInteraction]
        ) {
            collectionView.collectionViewLayout.invalidateLayout()
            collectionView.layoutIfNeeded()
        }
    }
}
