import UIKit

/// One list update at a time. A render that arrives while a batch update (or
/// a row removal) is animating is parked, newest wins, and runs when the
/// batch ends — its data commit included, so the data source never changes
/// under an animating batch.
@MainActor
final class UpdateGate {

    private(set) var isBusy = false
    private var pending: (() -> Void)?

    func begin() { isBusy = true }

    func end() {
        isBusy = false
        let work = pending
        pending = nil
        work?()
    }

    /// Runs `work` now, or parks it (replacing any parked work) until `end()`.
    func submitOrDefer(_ work: @escaping () -> Void) {
        if isBusy {
            pending = work
        } else {
            work()
        }
    }
}

/// The batch core of the inbox diff. The data mutation (`commit`) runs INSIDE
/// `performBatchUpdates`, right before the deletes and inserts: a layout pass
/// that is already pending when the batch starts then still sees the old
/// counts, and UIKit's item-count consistency check holds.
@MainActor
enum InboxBatchUpdate {

    static func apply(
        to collectionView: UICollectionView,
        section: Int,
        removes: [Int],
        inserts: [Int],
        animated: Bool,
        commit: @escaping () -> Void,
        completion: @escaping () -> Void
    ) {
        let removed = removes.map { IndexPath(item: $0, section: section) }
        let inserted = inserts.map { IndexPath(item: $0, section: section) }
        let updates = {
            collectionView.performBatchUpdates {
                commit()
                collectionView.deleteItems(at: removed)
                collectionView.insertItems(at: inserted)
            } completion: { _ in completion() }
        }
        if animated {
            UIView.animate(withDuration: Motion.emphasized, delay: 0, options: [.allowUserInteraction], animations: updates)
        } else {
            UIView.performWithoutAnimation(updates)
        }
    }
}
