import UIKit

/// Mutual exclusion for the card action strips in one list — the Dart
/// `CardListController` (lib/states/cardlist.dart): a `Card` tap toggles its
/// own strip and collapses any other expanded card in the SAME list (03
/// §2.11). Screens own one coordinator per list and, after each toggle,
/// refresh the affected cells and animate item heights
/// (`CardExpandAnimator.refresh`); `onChange` is optional.
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
///
/// Motion: only the strip moves. An opening strip slides down out of its
/// card while the item height grows; a closing strip fades out first and
/// the height closes after. The card's own content never moves.
@MainActor
enum CardExpandAnimator {

    /// Bumped by every pass so a closing fade that outlives a newer toggle
    /// drops its (stale) deferred height pass.
    private static let passes = NSMapTable<UICollectionView, NSNumber>(
        keyOptions: .weakMemory, valueOptions: .strongMemory
    )

    /// Cells whose strip state differs from the target for `expandedPath`.
    private static func cells(
        in collectionView: UICollectionView, expandedPath: IndexPath?, expanding: Bool
    ) -> [EpisodeCardCell] {
        collectionView.indexPathsForVisibleItems.compactMap { path in
            guard let cell = collectionView.cellForItem(at: path) as? EpisodeCardCell,
                  cell.isStripExpanded != (expandedPath == path),
                  (expandedPath == path) == expanding
            else { return nil }
            return cell
        }
    }

    static func refresh(expandedPath: IndexPath?, in collectionView: UICollectionView) {
        let pass = (passes.object(forKey: collectionView)?.intValue ?? 0) + 1
        passes.setObject(NSNumber(value: pass), forKey: collectionView)

        // A strip re-targeted open mid-fade returns to full opacity.
        for path in collectionView.indexPathsForVisibleItems where path == expandedPath {
            (collectionView.cellForItem(at: path) as? EpisodeCardCell)?.cancelStripFade()
        }
        let closing = cells(in: collectionView, expandedPath: expandedPath, expanding: false)
        guard !closing.isEmpty else {
            apply(expandedPath: expandedPath, in: collectionView)
            return
        }
        // Closing strips fade first (`Motion.stripFadeOut`); the height
        // pass — including any strip opening in the same toggle — follows.
        var pending = closing.count
        for cell in closing {
            cell.fadeOutStrip {
                pending -= 1
                guard pending == 0,
                      passes.object(forKey: collectionView)?.intValue == pass
                else { return }
                apply(expandedPath: expandedPath, in: collectionView)
            }
        }
    }

    /// 200 ms easeInOut — the Dart AnimatedContainer cadence.
    private static func apply(expandedPath: IndexPath?, in collectionView: UICollectionView) {
        // Cells whose strip actually opens get the reveal; settled cells
        // (already open or closed) must not animate.
        let opening = cells(in: collectionView, expandedPath: expandedPath, expanding: true)
        // Phase 1 — apply the strip targets WITHOUT animation. Changing a
        // cell's height-defining constraint and re-validating inside the
        // SAME animation transaction makes the compositional layout
        // re-measure the cell against its pre-change size (the item stays
        // collapsed while the strip overflows it); settled first, the
        // re-measure below sees the final constraint values.
        UIView.performWithoutAnimation {
            for path in collectionView.indexPathsForVisibleItems {
                guard let cell = collectionView.cellForItem(at: path) as? EpisodeCardCell,
                      cell.isStripExpanded != (expandedPath == path)
                else { continue }
                cell.setExpanded(expandedPath == path)
                if opening.contains(cell) { cell.prepareStripReveal() }
            }
        }
        // Phase 2 — animate the item-height re-validation; the collection's
        // layout pass carries the item resize, the cells' own reveal the strip.
        UIView.animate(
            withDuration: 0.2,
            delay: 0,
            options: [.curveEaseInOut, .allowUserInteraction]
        ) {
            collectionView.collectionViewLayout.invalidateLayout()
            collectionView.layoutIfNeeded()
        }
        for cell in opening { cell.revealStrip() }
    }
}

/// The first appearance of a card list: the visible cards fade in while
/// rising `Motion.cardEntranceOffset`, one after another. The motion lives
/// on each cell's `contentView` — the layout owns the cell frame.
///
/// Call it synchronously right after the data was applied, in the same
/// run-loop turn: the cards are parked at the start pose before anything is
/// drawn, so there is never a frame at the final position. The model values
/// are final the moment the animation is registered, so a cell that is
/// reused, reconfigured or interrupted mid-flight is already at rest.
@MainActor
enum CardEntranceAnimator {

    static func play(
        in collectionView: UICollectionView,
        reduceMotion: Bool = Motion.reduceMotion
    ) {
        collectionView.layoutIfNeeded()
        let cards = collectionView.visibleCells
            .filter { $0 is EpisodeCardCell || $0 is InboxEpisodeCardCell }
            .sorted { $0.frame.minY < $1.frame.minY }
        for (index, cell) in cards.enumerated() {
            let content = cell.contentView
            content.alpha = 0
            content.transform = reduceMotion
                ? .identity
                : CGAffineTransform(translationX: 0, y: Motion.cardEntranceOffset)
            let settle = {
                content.alpha = 1
                content.transform = .identity
            }
            if reduceMotion {
                UIView.animate(
                    withDuration: Motion.emphasized, delay: 0,
                    options: [.curveEaseOut, .allowUserInteraction], animations: settle
                )
            } else {
                UIView.animate(
                    withDuration: Motion.emphasized,
                    delay: Double(min(index, Motion.cardEntranceMaxStaggered)) * Motion.cardEntranceStagger,
                    usingSpringWithDamping: 0.9, initialSpringVelocity: 0,
                    options: [.allowUserInteraction], animations: settle
                )
            }
        }
    }
}
