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

/// One animated expand/collapse pass for a card list (03 §2.11). Two
/// tightly-coupled halves:
///
/// 1. Apply the strip targets to the visible cells WITHOUT animation and
///    WITHOUT settling the cell's layout — constraint constants and
///    visibility only. The owning cell must not lay out in this state: its
///    item frame is still collapsed, and the over-constrained solve
///    (expanded strip inside the collapsed frame) compresses the card body
///    by exactly the strip height — measured 112 pt → 52 pt standalone,
///    137⅔ pt → 77⅔ pt in-list — the one-frame device shrink. With the
///    targets un-settled, no deformed state is ever computed, let alone
///    committed.
/// 2. Animate the item-size re-validation through a TARGETED invalidation
///    of the visible items. The single layout pass inside the animation
///    re-measures each item against the final constraint constants and
///    lays every cell out at its FINAL frame — the only solve the new
///    constraints ever see.
///
/// Both halves are load-bearing, measured on this codebase (iOS 27
/// compositional layout; the strip-reliability toggle walk and the
/// from-measured-height probes in the regression suite):
/// - Constraint change and invalidation INSIDE one animation transaction
///   (with or without a `performBatchUpdates` wrapper, with or without
///   `selfSizingInvalidation = .enabledIncludingConstraints`): the
///   compositional layout never re-measures with the new constants — the
///   item keeps its pre-change size while the strip outran it (stuck
///   collapsed; the batch wrapper additionally swallowed the targeted
///   context, and `.enabledIncludingConstraints` left off-screen items
///   stuck EXPANDED). The constants must land OUTSIDE the transaction; the
///   forced settle the old code used for that was never the necessary
///   part — only the solved intermediate state it committed was harmful.
/// - TARGETED invalidation, not global: a global `invalidateLayout()`
///   inside the animation transaction discarded the compositional
///   layout's measured item sizes, so the animator's before-values fell
///   back to the `.estimated()` heights — a taller tapped card animated
///   estimate → expanded instead of measured → expanded (visibly
///   shrinking first), and taller untouched cards twitched toward the
///   estimate. Scoping the invalidation to the visible items keeps every
///   measured size as its own before-value; items whose strip target did
///   not change re-measure to the identical size and do not animate at
///   all.
///
/// The visible-only scope leaves one theoretical gap — an expanded card
/// scrolled fully off-screen keeps its measured +strip size until its cell
/// recycles — which iOS 27 closes on its own: the item's estimated
/// dimension is re-resolved against the reconfigured (collapsed) cell on
/// reappearance, so the scroll-back settles collapsed (pinned by the
/// regression suite's scroll-back test; no completion-phase invalidation
/// needed).
@MainActor
enum CardExpandAnimator {

    /// 200 ms easeInOut — the Dart AnimatedContainer cadence.
    static func refresh(expandedPath: IndexPath?, in collectionView: UICollectionView) {
        let visiblePaths = collectionView.indexPathsForVisibleItems
        // Phase 1 — strip targets, un-settled: the re-measure below solves
        // the engine fresh and sees the final constants; the cell's
        // internal layout must not run against the stale (collapsed) item
        // frame.
        UIView.performWithoutAnimation {
            for path in visiblePaths {
                guard let cell = collectionView.cellForItem(at: path) as? EpisodeCardCell else { continue }
                cell.setExpanded(expandedPath == path, settleLayout: false)
            }
        }
        // Phase 2 — the animated re-measure: one targeted invalidation,
        // one layout pass.
        UIView.animate(
            withDuration: 0.2,
            delay: 0,
            options: [.curveEaseInOut, .allowUserInteraction]
        ) {
            let context = UICollectionViewLayoutInvalidationContext()
            context.invalidateItems(at: visiblePaths)
            collectionView.collectionViewLayout.invalidateLayout(with: context)
            collectionView.layoutIfNeeded()
        }
    }
}
