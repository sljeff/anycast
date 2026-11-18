import UIKit

/// One engine per list. Owners must:
/// - use ListActionCollectionView for travelling hit routing;
/// - call reapplyGap AFTER configuring every cell, including reconfigures;
/// - supply stable IDs and synchronous apply closures that update their model
///   and diffable snapshot with animatingDifferences: false (no reconfigure of
///   surviving cells just to change the gap);
/// - supply safe screen-y lines relative to the viewport top, reserving the
///   mini player, tab bar and 52 pt toast slot themselves.
///
/// Selection/fill is resolved before apply, so providers see the final identity.
/// Model geometry is committed without animation, then FLIP animates layers;
/// neither cell.transform nor contentView.transform belongs to this engine.
@MainActor
final class ListActionController {
    private(set) var selectedID: String?
    private(set) var isTravelling = false
    private(set) var isAnimating = false
    let groupView = ListActionGroupView()

    /// An owner can defer scroll-driven chrome while true, then reconcile it
    /// once false. Set before any offset/inset writes, including snapshot apply.
    var onMotionStateChange: ((Bool) -> Void)?
    /// Refresh live overlays after configure has installed the selected items.
    var onGroupUpdate: (() -> Void)?
    /// Diagnostic for reviewer validation on each supported layout. We cannot
    /// assume compositional targeted invalidation always remeasures a spacer.
    private(set) var lastRemeasureUsedGlobalInvalidation = false

    private let collectionView: UICollectionView
    private let itemsProvider: (String) -> [ListActionItem]
    private let idAt: (IndexPath) -> String?
    private let indexPathFor: (String) -> IndexPath?
    private let safeArea: () -> (top: CGFloat, bottom: CGFloat)
    private let touchSink = ListActionTouchSink()
    private var contentHeightFloor: CGFloat?
    private(set) var insetExtension: CGFloat = 0
    private let skipsFLIP: (UIView) -> Bool
    private var isLayingOut = false
    private var motionGeneration = 0
    private var travellingID: String?
    private var snapshots: [UIView] = []

    private enum ViewKey: Hashable {
        case item(String)
        case passive(ObjectIdentifier)
        case supplementary(String, IndexPath)
        case group
    }

    init(
        collectionView: UICollectionView,
        itemsProvider: @escaping (String) -> [ListActionItem],
        idAt: @escaping (IndexPath) -> String?,
        indexPathFor: @escaping (String) -> IndexPath?,
        safeArea: @escaping () -> (top: CGFloat, bottom: CGFloat),
        skipsFLIP: @escaping (UIView) -> Bool = { _ in false }
    ) {
        self.collectionView = collectionView
        self.itemsProvider = itemsProvider
        self.idAt = idAt
        self.indexPathFor = indexPathFor
        self.safeArea = safeArea
        self.skipsFLIP = skipsFLIP
        groupView.isHidden = true
        groupView.layer.zPosition = -1
        collectionView.insertSubview(groupView, at: 0)
        collectionView.addSubview(touchSink)
        (collectionView as? ListActionCollectionView)?.actionController = self
        collectionViewDidLayout()
    }

    /// A card tap opens, closes or switches. A tap originates from a visible
    /// gap-hosting cell, whose actual card body supplies the opening anchor.
    func toggle(id: String) {
        if selectedID == id { close(animated: true); return }
        guard let path = indexPathFor(id),
              collectionView.cellForItem(at: path) is any ListActionGapHosting,
              let card = cardFrame(for: id) else { return }
        let itemScreenY = visibleViews()[.item(id)].map(screenY) ?? (card.minY - collectionView.contentOffset.y)
        ghostOut()
        transition(anchor: .item(itemScreenY), anchorID: id, opening: true, growFrom: 0.2) {
            self.selectedID = id
            self.travellingID = nil
            self.isTravelling = false
        }
    }

    func close(animated: Bool = true, completion: (() -> Void)? = nil) {
        guard let id = selectedID else { completion?(); return }
        let top = visibleViews()[.item(id)].map(screenY)
            ?? cardFrame(for: id).map { $0.minY - collectionView.contentOffset.y }
        if animated { ghostOut() }
        transition(
            anchor: top.map(ListActionPlanner.Anchor.item) ?? .none, anchorID: id,
            animated: animated, completion: completion
        ) {
            self.selectedID = nil
            self.travellingID = nil
            self.isTravelling = false
        }
    }

    /// Flatten only actionable IDs across sections. Resolve the filler BEFORE
    /// mutation; an old IndexPath cannot identify an episode after diffable apply.
    func performLeave(id: String, keepsGroup: Bool = true, apply: () -> Void) {
        let ids = (0..<collectionView.numberOfSections).flatMap { section in
            (0..<collectionView.numberOfItems(inSection: section)).compactMap {
                idAt(IndexPath(item: $0, section: section))
            }
        }
        let anchor = groupAnchor()
        var filler = selectedID
        if selectedID == id, let removed = ids.firstIndex(of: id) {
            var remaining = ids
            remaining.remove(at: removed)
            filler = ListActionPlanner.fillTarget(removedIndex: removed, countAfter: remaining.count)
                .map { remaining[$0] }
        }
        if !keepsGroup { filler = nil }
        let leavingSnapshot = makeLeavingSnapshot(id: id)
        if filler == nil { ghostOut() }
        transition(anchor: anchor, growFrom: selectedID == id && filler != nil ? 0.6 : nil) {
            self.selectedID = filler
            self.travellingID = filler
            self.isTravelling = filler != nil
            apply()
            // An external reload may remove several rows at once. Skip any
            // vanished neighbors, preserving the below-then-above fill rule.
            if let candidate = self.selectedID, self.indexPathFor(candidate) == nil,
               let removed = ids.firstIndex(of: id) {
                self.selectedID = ids.dropFirst(removed + 1).first { self.indexPathFor($0) != nil }
                    ?? ids.prefix(removed).reversed().first { self.indexPathFor($0) != nil }
                self.travellingID = self.selectedID
                self.isTravelling = self.selectedID != nil
            }
        }
        if let leavingSnapshot { fadeLeavingSnapshot(leavingSnapshot) }
    }

    /// Reloads, insertions and external reshapes preserve the group anchor. A
    /// vanished selection closes here; performLeave is the explicit fill path.
    func itemsDidChange(preservingItem id: String? = nil, apply: () -> Void) {
        // Inbox also preserves its first surviving visible card on a silent
        // refresh with no group open. Other owners keep the default behavior.
        if selectedID == nil, let id, let view = visibleViews()[.item(id)] {
            transition(anchor: .item(screenY(view)), anchorID: id, mutation: apply)
        } else {
            transition(anchor: groupAnchor(), mutation: apply)
        }
    }

    func reapplyGap(to cell: any ListActionGapHosting, id: String) {
        cell.setActionGap(id == selectedID ? ListActionMetrics.gap : 0)
    }

    // MARK: - Unanimated layout, followed by additive presentation motion

    private func transition(
        anchor: ListActionPlanner.Anchor,
        anchorID: String? = nil,
        opening: Bool = false,
        animated: Bool = true,
        growFrom: CGFloat? = nil,
        completion: (() -> Void)? = nil,
        mutation: () -> Void
    ) {
        let oldViews = visibleViews()
        let before = oldViews.mapValues(screenY)
        var snapshotPositions = snapshots.map { ($0, $0.center.y - collectionView.contentOffset.y) }
        let oldOffset = collectionView.contentOffset.y
        let previousID = selectedID
        motionGeneration += 1
        let generation = motionGeneration
        isAnimating = animated
        onMotionStateChange?(animated)
        isLayingOut = true
        lastRemeasureUsedGlobalInvalidation = false

        UIView.performWithoutAnimation {
            oldViews.values.forEach { $0.layer.removeAnimation(forKey: ListActionMotion.translationKey) }
            if previousID != nil {
                contentHeightFloor = max(contentHeightFloor ?? 0, collectionView.contentSize.height)
                // Reserve before UIKit sees the shorter snapshot. The final
                // extension below is only the missing height, never this reserve.
                setInsetExtension(contentHeightFloor ?? 0)
            }
            mutation()
            if let id = selectedID, indexPathFor(id) == nil {
                if let y = before[.group], animated, let ghost = ghostOut(at: y) {
                    snapshotPositions.append((ghost, ghost.center.y - collectionView.contentOffset.y))
                }
                selectedID = nil
                travellingID = nil
                isTravelling = false
            }
            if selectedID == nil { contentHeightFloor = nil }
            var changed = applyVisibleGaps()
            for id in [previousID, selectedID].compactMap({ $0 }) {
                if let path = indexPathFor(id) { changed.insert(path) }
            }
            remeasure(changed)
            updateHeightFloor()

            // A compensated offset can materialize the adjacent filler. Give
            // its self-sizing cell one settle before recomputing the same anchor.
            for _ in 0..<2 {
                let safe = safeArea()
                let insets = collectionView.adjustedContentInset
                let offset = ListActionPlanner.targetOffset(
                    selectedCardFrame: selectedID.flatMap(cardFrame), anchor: anchor,
                    anchorItemFrame: anchorID.flatMap(cardFrame), currentOffset: oldOffset,
                    viewportHeight: collectionView.bounds.height, topSafe: safe.top, bottomSafe: safe.bottom,
                    contentHeight: collectionView.contentSize.height,
                    adjustedContentInset: .init(top: insets.top, bottom: insets.bottom), opening: opening
                )
                collectionView.setContentOffset(CGPoint(x: collectionView.contentOffset.x, y: offset), animated: false)
                collectionView.layoutIfNeeded()
                let newlyChanged = applyVisibleGaps()
                if !newlyChanged.isEmpty { remeasure(newlyChanged) }
                updateHeightFloor()
            }

            if let id = selectedID {
                groupView.configure(itemsProvider(id))
                onGroupUpdate?()
                groupView.isHidden = false
            } else {
                groupView.isHidden = true
            }
            positionGroup()
            groupView.layoutIfNeeded()
            for (snapshot, y) in snapshotPositions {
                snapshot.center.y = y + collectionView.contentOffset.y
            }
        }
        isLayingOut = false

        if animated {
            var origins = before
            if opening, let id = selectedID, let card = cardFrame(for: id),
               let cardTop = before[.item(id)] {
                // New selection grows beneath ITS card; never translate the
                // real group from the former selection across intervening cards.
                origins[.group] = cardTop + card.height + ListActionMetrics.spacing
            }
            for (key, view) in visibleViews() {
                guard let previousY = origins[key] else { continue }
                // Read the final MODEL frame here. The presentation tree can
                // still contain the pre-layout frame until this turn commits.
                flip(view, from: previousY - (view.frame.minY - collectionView.contentOffset.y))
            }
            if let growFrom, selectedID != nil { groupView.grow(from: growFrom) }
        }
        groupView.circles.forEach { $0.travellingHitOutset = isTravelling ? ListActionMetrics.travellingHitOutset : 0 }
        if animated {
            DispatchQueue.main.asyncAfter(deadline: .now() + ListActionMotion.duration) { [weak self] in
                // A later layout may supersede this animation, but must not
                // discard the user's action waiting for close to finish.
                defer { completion?() }
                guard let self, self.motionGeneration == generation else { return }
                self.finishMotion()
            }
        } else {
            snapshots.forEach { $0.removeFromSuperview() }
            snapshots.removeAll()
            finishMotion()
            completion?()
        }
    }

    private func finishMotion() {
        isTravelling = false
        travellingID = nil
        groupView.circles.forEach { $0.travellingHitOutset = 0 }
        isAnimating = false
        onMotionStateChange?(false)
    }

    private func applyVisibleGaps() -> Set<IndexPath> {
        var changed: Set<IndexPath> = []
        for path in collectionView.indexPathsForVisibleItems {
            guard let cell = collectionView.cellForItem(at: path) as? any ListActionGapHosting else { continue }
            let gap = selectedID != nil && idAt(path) == selectedID ? ListActionMetrics.gap : 0
            if cell.actionGap != gap {
                cell.setActionGap(gap)
                changed.insert(path)
            }
        }
        return changed
    }

    private func remeasure(_ paths: Set<IndexPath>) {
        if !paths.isEmpty {
            let context = UICollectionViewLayoutInvalidationContext()
            context.invalidateItems(at: Array(paths))
            collectionView.collectionViewLayout.invalidateLayout(with: context)
        }
        collectionView.layoutIfNeeded()
        let mismatched = paths.contains { path in
            guard let cell = collectionView.cellForItem(at: path),
                  let host = cell as? any ListActionGapHosting else { return false }
            return abs(cell.bounds.height - host.cardFrameInCell.maxY - host.actionGap) > 1
        }
        if mismatched {
            // Global invalidation occurs BEFORE FLIP. Discarded estimates cannot become animation
            // origins: the origins were captured from actual visible frames.
            lastRemeasureUsedGlobalInvalidation = true
            collectionView.collectionViewLayout.invalidateLayout()
            collectionView.layoutIfNeeded()
        }
        assert(paths.allSatisfy { path in
            guard let cell = collectionView.cellForItem(at: path),
                  let host = cell as? any ListActionGapHosting else { return true }
            return abs(cell.bounds.height - host.cardFrameInCell.maxY - host.actionGap) <= 1
        }, "List action item did not remeasure to card + gap after unanimated invalidation")
    }

    private func setInsetExtension(_ value: CGFloat) {
        var inset = collectionView.contentInset
        inset.bottom += value - insetExtension
        insetExtension = value
        collectionView.contentInset = inset
    }

    private func updateHeightFloor() {
        if selectedID != nil {
            contentHeightFloor = max(contentHeightFloor ?? 0, collectionView.contentSize.height)
        }
        setInsetExtension(ListActionPlanner.bottomInsetExtension(
            contentHeight: collectionView.contentSize.height, floor: contentHeightFloor
        ))
    }

    private func flip(_ view: UIView, from delta: CGFloat) {
        // Reduce Motion: cards land in place; only the circles fade.
        guard abs(delta) > 0.5, !ListActionMotion.reduceMotion else { return }
        let animation = CABasicAnimation(keyPath: "position.y")
        animation.isAdditive = true
        animation.fromValue = delta
        animation.toValue = 0
        animation.duration = ListActionMotion.duration
        animation.timingFunction = ListActionMotion.timingFunction
        view.layer.add(animation, forKey: ListActionMotion.translationKey)
    }

    // MARK: - Geometry and snapshots

    private func screenY(_ view: UIView) -> CGFloat {
        (view.layer.presentation()?.frame.minY ?? view.frame.minY) - collectionView.contentOffset.y
    }

    private func visibleViews() -> [ViewKey: UIView] {
        var result: [ViewKey: UIView] = [:]
        for path in collectionView.indexPathsForVisibleItems {
            guard let cell = collectionView.cellForItem(at: path) else { continue }
            // Inbox shelf/strip cells have no actionable ID, but must move
            // with the content. Object identity survives section index shifts.
            let key = idAt(path).map(ViewKey.item) ?? .passive(ObjectIdentifier(cell))
            result[key] = cell
        }
        // Discover custom supplementary kinds as well as standard headers and
        // footers. They must share the exact same compensation as the cells.
        let attributes = collectionView.collectionViewLayout.layoutAttributesForElements(in: collectionView.bounds) ?? []
        for attribute in attributes where attribute.representedElementCategory == .supplementaryView {
            guard let kind = attribute.representedElementKind,
                  let view = collectionView.supplementaryView(forElementKind: kind, at: attribute.indexPath) else { continue }
            if !skipsFLIP(view) { result[.supplementary(kind, attribute.indexPath)] = view }
        }
        if !groupView.isHidden { result[.group] = groupView }
        return result
    }

    private func cardFrame(for id: String) -> CGRect? {
        guard let path = indexPathFor(id) else { return nil }
        if let cell = collectionView.cellForItem(at: path), let host = cell as? any ListActionGapHosting {
            return host.cardFrameInCell.offsetBy(dx: cell.frame.minX, dy: cell.frame.minY)
        }
        guard var frame = collectionView.layoutAttributesForItem(at: path)?.frame else { return nil }
        if id == selectedID { frame.size.height = max(0, frame.height - ListActionMetrics.gap) }
        return frame
    }

    private func groupAnchor() -> ListActionPlanner.Anchor {
        groupView.isHidden ? .none : .group(screenY(groupView))
    }

    func collectionViewDidLayout() {
        guard !isLayingOut else { return }
        // Background/empty views belong behind the group; every ordinary cell
        // retains UIKit's zPosition 0, above both group (-1) and leave ghost (-.5).
        collectionView.backgroundView?.layer.zPosition = -2
        touchSink.frame = collectionView.bounds
        positionGroup()
    }

    private func positionGroup() {
        guard let id = selectedID, let card = cardFrame(for: id) else { return }
        groupView.frame = CGRect(
            x: ListActionMetrics.itemInset, y: card.maxY + ListActionMetrics.spacing,
            width: max(0, collectionView.bounds.width - 2 * ListActionMetrics.itemInset),
            height: ListActionMetrics.circle
        )
    }

    @discardableResult
    private func ghostOut(at previousScreenY: CGFloat? = nil) -> UIView? {
        guard !groupView.isHidden else { return nil }
        let ghost = groupView.makeGhost()
        ghost.frame.origin.y = (previousScreenY ?? screenY(groupView)) + collectionView.contentOffset.y
        ghost.layer.zPosition = -1
        collectionView.insertSubview(ghost, at: 0)
        snapshots.append(ghost)
        ghost.shrink { [weak self, weak ghost] in
            guard let ghost else { return }
            ghost.removeFromSuperview()
            self?.snapshots.removeAll { $0 === ghost }
        }
        return ghost
    }

    private func makeLeavingSnapshot(id: String) -> UIView? {
        guard let path = indexPathFor(id), let cell = collectionView.cellForItem(at: path),
              let host = cell as? any ListActionGapHosting,
              let snapshot = cell.resizableSnapshotView(
                from: host.cardFrameInCell, afterScreenUpdates: false, withCapInsets: .zero
              ) else { return nil }
        snapshot.frame = host.cardFrameInCell.offsetBy(
            dx: cell.frame.minX, dy: screenY(cell) + collectionView.contentOffset.y
        )
        snapshot.layer.zPosition = -0.5
        snapshot.isUserInteractionEnabled = false
        snapshot.accessibilityElementsHidden = true
        collectionView.addSubview(snapshot)
        snapshots.append(snapshot)
        return snapshot
    }

    private func fadeLeavingSnapshot(_ snapshot: UIView) {
        UIView.animate(
            withDuration: ListActionMotion.reduceMotion ? ListActionMotion.fadeOut : ListActionMotion.leaveDuration,
            delay: 0, options: [.curveEaseOut, .allowUserInteraction]
        ) {
            snapshot.alpha = 0
            if !ListActionMotion.reduceMotion { snapshot.transform = CGAffineTransform(scaleX: 0.97, y: 0.97) }
        } completion: { [weak self, weak snapshot] _ in
            guard let snapshot else { return }
            snapshot.removeFromSuperview()
            self?.snapshots.removeAll { $0 === snapshot }
        }
    }

    // MARK: - Presentation-aware hit routing

    func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard isTravelling, !groupView.isHidden else { return nil }
        let groupFrame = groupView.layer.presentation()?.frame ?? groupView.frame
        let band = groupFrame.insetBy(dx: 0, dy: -ListActionMetrics.travellingHitOutset)
        if band.contains(point) {
            let localX = point.x - groupFrame.minX
            if let circle = groupView.circles.first(where: { localX >= $0.frame.minX && localX <= $0.frame.maxX }) {
                return circle
            }
            return touchSink
        }
        if let id = travellingID, let path = indexPathFor(id),
           let cell = collectionView.cellForItem(at: path), let host = cell as? any ListActionGapHosting {
            let body = host.cardFrameInCell
            let presented = cell.layer.presentation()?.frame ?? cell.frame
            if body.offsetBy(dx: presented.minX, dy: presented.minY).contains(point)
                || body.offsetBy(dx: cell.frame.minX, dy: cell.frame.minY).contains(point) {
                return touchSink
            }
        }
        return nil
    }
}
