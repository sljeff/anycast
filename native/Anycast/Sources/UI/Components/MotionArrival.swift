import UIKit

/// First arrival of a list that today pops in over one frame. Staggered rise
/// matches `CardEntranceAnimator` when motion is allowed; Reduce Motion, and
/// the skeleton-only path, crossfade.
@MainActor
enum MotionArrival {

    static func reveal(
        in collectionView: UICollectionView,
        cells: [UICollectionViewCell],
        skeleton: SkeletonListView?,
        staggered: Bool
    ) {
        collectionView.layoutIfNeeded()
        let targets = cells.isEmpty ? collectionView.visibleCells : cells
        guard !targets.isEmpty else {
            skeleton?.dismissAnimated()
            return
        }
        let rise = staggered && !Motion.reduceMotion
        if rise {
            skeleton?.dismissAnimated()
            MotionListEntrance.play(cells: targets)
            return
        }
        for cell in targets {
            cell.contentView.alpha = 0
            cell.contentView.transform = .identity
        }
        skeleton?.dismissAnimated()
        UIView.animate(
            withDuration: Motion.quick,
            delay: 0,
            options: [.curveEaseOut, .allowUserInteraction]
        ) {
            for cell in targets {
                cell.contentView.alpha = 1
            }
        }
    }
}

/// Same rise as `CardEntranceAnimator`, for cells that animator does not know
/// (channel rows, podcast cards).
@MainActor
enum MotionListEntrance {

    static func play(cells: [UICollectionViewCell]) {
        let reduce = Motion.reduceMotion
        let ordered = cells.sorted { $0.frame.minY < $1.frame.minY }
        for (index, cell) in ordered.enumerated() {
            let content = cell.contentView
            content.alpha = 0
            content.transform = reduce
                ? .identity
                : CGAffineTransform(translationX: 0, y: Motion.cardEntranceOffset)
            let settle = {
                content.alpha = 1
                content.transform = .identity
            }
            if reduce {
                UIView.animate(
                    withDuration: Motion.emphasized,
                    delay: 0,
                    options: [.curveEaseOut, .allowUserInteraction],
                    animations: settle
                )
            } else {
                UIView.animate(
                    withDuration: Motion.emphasized,
                    delay: Double(min(index, Motion.cardEntranceMaxStaggered)) * Motion.cardEntranceStagger,
                    usingSpringWithDamping: 0.9,
                    initialSpringVelocity: 0,
                    options: [.allowUserInteraction],
                    animations: settle
                )
            }
        }
    }
}

/// Mini player insert. Off, the host's height snaps and whatever sits on
/// `bar.top` jumps. On, the bar slides up from below and that neighbor
/// yields across the same spring. Reduce Motion crossfades the bar.
@MainActor
enum MiniPlayerInsertion {

    static func apply(
        visible: Bool,
        bar: UIView,
        height: NSLayoutConstraint,
        in host: UIView,
        alongside: @escaping () -> Void = {}
    ) {
        let target: CGFloat = visible ? PlayerBarView.barHeight : 0
        let unchanged = (bar.isHidden == !visible) && abs(height.constant - target) < 0.5
        if unchanged {
            alongside()
            return
        }
        let animate = host.window != nil
        guard animate else {
            bar.isHidden = !visible
            bar.alpha = 1
            bar.transform = .identity
            height.constant = target
            alongside()
            return
        }
        yieldOwnHeight(to: height, on: bar)
        if Motion.reduceMotion {
            if visible {
                bar.alpha = 0
                bar.isHidden = false
            }
            height.constant = target
            alongside()
            host.layoutIfNeeded()
            UIView.animate(withDuration: Motion.quick, animations: {
                bar.alpha = visible ? 1 : 0
            }, completion: { _ in
                bar.isHidden = !visible
                bar.alpha = 1
                bar.transform = .identity
            })
            return
        }
        if visible {
            bar.alpha = 1
            bar.isHidden = false
            bar.transform = CGAffineTransform(translationX: 0, y: PlayerBarView.barHeight)
        }
        UIView.animate(
            withDuration: Motion.standard,
            delay: 0,
            usingSpringWithDamping: 0.86,
            initialSpringVelocity: 0.35,
            options: [.allowUserInteraction, .beginFromCurrentState]
        ) {
            height.constant = target
            bar.transform = visible
                ? .identity
                : CGAffineTransform(translationX: 0, y: PlayerBarView.barHeight)
            alongside()
            host.layoutIfNeeded()
        } completion: { _ in
            bar.isHidden = !visible
            bar.alpha = 1
            bar.transform = .identity
        }
    }

    /// The bar also pins its own required height. Drop that just below the
    /// host constraint so the host can animate between 0 and 58.
    private static func yieldOwnHeight(to hostConstraint: NSLayoutConstraint, on bar: UIView) {
        for constraint in bar.constraints where constraint.firstAttribute == .height && constraint !== hostConstraint {
            if constraint.priority == .required {
                constraint.priority = UILayoutPriority(999)
            }
        }
    }
}
