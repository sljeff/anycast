import UIKit

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
