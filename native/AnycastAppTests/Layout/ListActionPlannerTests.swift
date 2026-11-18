import UIKit
import Testing
@testable import Anycast

struct ListActionPlannerTests {
    private func card(_ y: CGFloat, _ height: CGFloat) -> CGRect {
        CGRect(x: 16, y: y, width: 358, height: height)
    }

    private func offset(
        card: CGRect?, anchor: ListActionPlanner.Anchor, current: CGFloat,
        contentHeight: CGFloat = 2400, insets: ListActionPlanner.Insets = .init(),
        opening: Bool = false
    ) -> CGFloat {
        ListActionPlanner.targetOffset(
            selectedCardFrame: card, anchor: anchor, currentOffset: current,
            viewportHeight: 800, topSafe: 100, bottomSafe: 600,
            contentHeight: contentHeight, adjustedContentInset: insets, opening: opening
        )
    }

    @Test("Opening near the bottom pushes the page up by max(over, 68)")
    func openingPushesInOneDirection() {
        for frame in [card(650, 100), card(760, 140)] {
            let before: CGFloat = 200
            let over = frame.maxY + 68 - before - 600
            let result = offset(card: frame, anchor: .item(frame.minY - before), current: before, opening: true)
            #expect(result - before == max(over, 68))
            // The inserted gap may move lower cards down by 68 in content
            // coordinates, but none moves DOWN on screen when opening pushes up.
            #expect(68 - (result - before) <= 0)
        }
    }

    @Test("Opening below the top bar moves content down until the title clears it")
    func openingClearsTitle() {
        let frame = card(450, 100)
        let result = offset(card: frame, anchor: .item(50), current: 400, opening: true)
        #expect(result == 350)
        #expect(frame.minY - result == 100)
    }

    @Test("A fully visible group takes priority over an oversized card's title")
    func actionsBeatTitle() {
        let frame = card(100, 700)
        let result = offset(card: frame, anchor: .item(100), current: 0, opening: true)
        #expect(result == 268)
        #expect(frame.maxY + 68 - result == 600)
        #expect(frame.minY - result < 100)
    }

    @Test("A taller filler below preserves the group screen position exactly")
    func tallerFiller() {
        let old = card(500, 120)
        let filler = card(500, 200)
        let before: CGFloat = 300
        let screenY = old.maxY + 12 - before
        let result = offset(card: filler, anchor: .group(screenY), current: before)
        #expect(result - before == filler.height - old.height)
        #expect(filler.maxY + 12 - result - screenY == 0)
    }

    @Test("A shorter filler below preserves the group screen position exactly")
    func shorterFiller() {
        let old = card(500, 120)
        let filler = card(500, 80)
        let before: CGFloat = 300
        let screenY = old.maxY + 12 - before
        let result = offset(card: filler, anchor: .group(screenY), current: before)
        #expect(result - before == -40)
        #expect(filler.maxY + 12 - result - screenY == 0)
    }

    @Test("At the list top a shorter filler moves the group by the unclampable difference")
    func topClampException() {
        let old = card(200, 160)
        let filler = card(200, 80)
        let screenY = old.maxY + 12
        let result = offset(card: filler, anchor: .group(screenY), current: 0)
        #expect(result == 0)
        #expect(filler.maxY + 12 - result - screenY == -80)
    }

    @Test("Filling chooses below, then above for the last item, then closes when empty")
    func fillTargets() {
        #expect(ListActionPlanner.fillTarget(removedIndex: 1, countAfter: 4) == 1)
        #expect(ListActionPlanner.fillTarget(removedIndex: 4, countAfter: 4) == 3)
        #expect(ListActionPlanner.fillTarget(removedIndex: 0, countAfter: 0) == nil)
        #expect(ListActionPlanner.fillTarget(removedIndex: 0, countAfter: 1) == 0)
    }

    @Test("A filler above and insertions above use the same group anchor")
    func reshapesPreserveAnchor() {
        let previousScreenY: CGFloat = 332
        for frame in [card(368, 120), card(720, 120)] {
            let result = offset(card: frame, anchor: .group(previousScreenY), current: 300)
            #expect(frame.maxY + 12 - result == previousScreenY)
        }
    }

    @Test("The height floor prevents bottom clamping across consecutive removals, then releases")
    func heightFloor() {
        let frame = card(1450, 120)
        let floor: CGFloat = 2100
        let before: CGFloat = 1300
        let screenY = frame.maxY + 12 - before
        for contentHeight in [CGFloat(2000), 1800, 1650] {
            let extensionHeight = ListActionPlanner.bottomInsetExtension(contentHeight: contentHeight, floor: floor)
            #expect(contentHeight + extensionHeight == floor)
            let result = offset(
                card: frame, anchor: .group(screenY), current: before, contentHeight: contentHeight,
                insets: .init(top: 44, bottom: 80 + extensionHeight)
            )
            #expect(result == before)
            #expect(frame.maxY + 12 - result == screenY)
        }
        #expect(ListActionPlanner.bottomInsetExtension(contentHeight: 1650, floor: nil) == 0)
        #expect(ListActionPlanner.bottomInsetExtension(contentHeight: 2200, floor: floor) == 0)
        let closed = offset(card: nil, anchor: .none, current: before, contentHeight: 1650, insets: .init(top: 44, bottom: 80))
        #expect(closed == 930)
    }

    @Test("Adjusted insets define both clamp limits, including short content")
    func adjustedInsets() {
        #expect(offset(card: nil, anchor: .none, current: -200, insets: .init(top: 44)) == -44)
        #expect(offset(card: nil, anchor: .none, current: 3000, insets: .init(bottom: 80)) == 1680)
        #expect(offset(card: nil, anchor: .none, current: 0, contentHeight: 100, insets: .init(top: 44)) == -44)
    }

    @Test("Closing can anchor the former card without enforcing the selected-card safe band")
    func closingItemAnchor() {
        let result = ListActionPlanner.targetOffset(
            selectedCardFrame: nil, anchor: .item(200), anchorItemFrame: card(450, 100),
            currentOffset: 300, viewportHeight: 800, topSafe: 100, bottomSafe: 600,
            contentHeight: 2400, opening: false
        )
        #expect(result == 250)
    }
}

@MainActor
struct ListActionGroupViewTests {
    private func group(count: Int = 3, handler: @escaping () -> Void = {}) -> ListActionGroupView {
        let group = ListActionGroupView(items: (0..<count).map {
            ListActionItem(id: "action-\($0)", content: .title("Details"), accessibilityLabel: "Action \($0)", handler: handler)
        })
        group.frame = CGRect(x: 0, y: 0, width: 336, height: 56)
        group.layoutIfNeeded()
        return group
    }

    @Test("Three circles distribute left, center and right with CSS space-around")
    func distribution() {
        let group = self.group()
        #expect(group.circles.map(\.center.x) == [56, 168, 280])
        #expect(group.circles.allSatisfy { $0.frame.size == CGSize(width: 56, height: 56) })
        #expect(group.circles.allSatisfy { $0.center.y == 28 })
        let four = self.group(count: 4)
        #expect(four.circles.map(\.center.x) == [42, 126, 210, 294])
    }

    @Test("A disc paused mid-grow keeps its entire 56 pt button hittable")
    func growingHitTargets() throws {
        var taps = 0
        let group = self.group { taps += 1 }
        group.grow(from: 0.2, reduceMotion: false)
        for circle in group.circles {
            // Added animations are frozen copies: park a mutable copy instead.
            let added = try #require(circle.disc.layer.animation(forKey: "list-action-disc") as? CAAnimationGroup)
            let animation = try #require(added.copy() as? CAAnimationGroup)
            // Park the animation at its midpoint rather than depending on the
            // CI display link being scheduled within the 320 ms interval.
            animation.speed = 0
            animation.beginTime = 0
            animation.timeOffset = 0.16
            circle.disc.layer.add(animation, forKey: "list-action-disc")
            #expect(circle.layer.animationKeys()?.isEmpty ?? true)
            #expect(circle.frame.size == CGSize(width: 56, height: 56))
            #expect(circle.transform == .identity)
            #expect(circle.hitTest(CGPoint(x: 1, y: 28), with: nil) === circle)
            #expect(circle.hitTest(CGPoint(x: 55, y: 28), with: nil) === circle)
            circle.sendActions(for: .touchUpInside)
        }
        #expect(taps == 3)
    }

    @Test("Grow staggers center first; shrink staggers outside first")
    func staggerAndReduceMotion() throws {
        let group = self.group()
        group.grow(from: 0.6, reduceMotion: false)
        let opening = try group.circles.map {
            try #require($0.disc.layer.animation(forKey: "list-action-disc") as? CAAnimationGroup)
        }
        #expect(opening.allSatisfy { $0.duration == 0.32 })
        #expect(opening[0].beginTime > opening[1].beginTime)
        #expect(opening[2].beginTime > opening[1].beginTime)
        group.shrink(reduceMotion: false) {}
        let closing = try group.circles.map {
            try #require($0.disc.layer.animation(forKey: "list-action-disc") as? CAAnimationGroup)
        }
        #expect(closing.allSatisfy { $0.duration == 0.26 })
        #expect(closing[1].beginTime > closing[0].beginTime)
        #expect(closing[1].beginTime > closing[2].beginTime)
        group.grow(from: 0.2, reduceMotion: true)
        for circle in group.circles {
            let animation = try #require(circle.disc.layer.animation(forKey: "list-action-disc") as? CAAnimationGroup)
            #expect(animation.duration == 0.15)
            #expect(animation.animations?.count == 1)
            #expect((animation.animations?.first as? CABasicAnimation)?.keyPath == "opacity")
            #expect(CATransform3DIsIdentity(circle.disc.layer.transform))
        }
        group.shrink(reduceMotion: true) {}
        #expect(group.circles.first?.disc.layer.animation(forKey: "list-action-disc")?.duration == 0.12)
    }

    @Test("Replacing handlers preserves live hosts and action accessibility")
    func liveContentAndIdentity() throws {
        let group = self.group()
        let original = try #require(group.button(for: "action-0"))
        let overlay = UIView()
        original.contentHost.addSubview(overlay)
        var replacementTaps = 0
        group.configure((0..<3).map {
            ListActionItem(id: "action-\($0)", content: .title("Details"), accessibilityLabel: "New action \($0)") {
                replacementTaps += 1
            }
        })
        #expect(group.button(for: "action-0") === original)
        #expect(overlay.superview === original.contentHost)
        #expect(!original.contentHost.clipsToBounds && !original.disc.clipsToBounds)
        #expect(original.accessibilityLabel == "New action 0")
        original.sendActions(for: .touchUpInside)
        #expect(replacementTaps == 1)
    }

    @Test("The cell spacer is transparent to hits and reset on configure and reuse")
    func cellGapLifecycle() {
        let cell = EpisodeCardCell(frame: CGRect(x: 0, y: 0, width: 358, height: 162))
        cell.setActionGap(68)
        cell.layoutIfNeeded()
        #expect(cell.cardFrameInCell.height == 94)
        #expect(cell.point(inside: CGPoint(x: 100, y: 40), with: nil))
        #expect(!cell.point(inside: CGPoint(x: 100, y: 110), with: nil))
        cell.configure(EpisodeCardContent(
            title: "Episode", channelTitle: "Show", rightText: "20m", descriptionHTML: nil, imageURL: nil
        ), actions: [])
        #expect(cell.actionGap == 0)
        cell.setActionGap(68)
        cell.prepareForReuse()
        #expect(cell.actionGap == 0)
    }

    @Test("Compositional cells remeasure, draw above the group and route travelling taps")
    func collectionIntegration() throws {
        let size = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1), heightDimension: .estimated(94))
        let item = NSCollectionLayoutItem(layoutSize: size)
        item.contentInsets = .init(top: 0, leading: 16, bottom: 0, trailing: 16)
        let section = NSCollectionLayoutSection(group: .vertical(layoutSize: size, subitems: [item]))
        section.interGroupSpacing = 12
        section.contentInsets = .init(top: 12, leading: 0, bottom: 64, trailing: 0)
        let collection = ListActionCollectionView(
            frame: CGRect(x: 0, y: 0, width: 390, height: 800),
            collectionViewLayout: UICollectionViewCompositionalLayout(section: section)
        )
        collection.contentInsetAdjustmentBehavior = .never
        collection.register(EpisodeCardCell.self, forCellWithReuseIdentifier: EpisodeCardCell.reuseIdentifier)
        var controller: ListActionController?
        let dataSource = UICollectionViewDiffableDataSource<Int, String>(collectionView: collection) { collection, path, id in
            let cell = collection.dequeueReusableCell(withReuseIdentifier: EpisodeCardCell.reuseIdentifier, for: path) as! EpisodeCardCell
            cell.configure(EpisodeCardContent(
                title: id, channelTitle: "Show", rightText: "20m", descriptionHTML: nil, imageURL: nil
            ), actions: [])
            controller?.reapplyGap(to: cell, id: id)
            return cell
        }
        let engine = ListActionController(
            collectionView: collection,
            itemsProvider: { id in
                [ListActionItem(id: "remove", content: .title("Remove"), accessibilityLabel: "Remove \(id)", handler: {})]
            },
            idAt: { dataSource.itemIdentifier(for: $0) },
            indexPathFor: { dataSource.indexPath(for: $0) },
            safeArea: { (top: 100, bottom: 600) }
        )
        controller = engine
        // Break the provider's reference back to the engine after each test.
        defer { controller = nil }
        var snapshot = NSDiffableDataSourceSnapshot<Int, String>()
        snapshot.appendSections([0])
        snapshot.appendItems((0..<10).map { "row-\($0)" })
        dataSource.apply(snapshot, animatingDifferences: false)
        collection.layoutIfNeeded()
        engine.toggle(id: "row-2")
        let selectedPath = try #require(dataSource.indexPath(for: "row-2"))
        let cell = try #require(collection.cellForItem(at: selectedPath) as? EpisodeCardCell)
        #expect(cell.actionGap == 68)
        #expect(abs(cell.bounds.height - cell.cardFrameInCell.height - 68) < 1)
        #expect(cell.layer.zPosition > engine.groupView.layer.zPosition)
        #expect(engine.groupView.frame.width == 358)
        let button = try #require(engine.groupView.button(for: "remove"))
        let tap = engine.groupView.convert(button.center, to: collection)
        #expect(collection.hitTest(tap, with: nil) === button)
        let groupScreenY = engine.groupView.frame.minY - collection.contentOffset.y

        engine.performLeave(id: "row-2") {
            snapshot.deleteItems(["row-2"])
            dataSource.apply(snapshot, animatingDifferences: false)
        }
        #expect(engine.selectedID == "row-3")
        #expect(engine.isTravelling)
        #expect(engine.groupView.frame.minY - collection.contentOffset.y == groupScreenY)
        #expect(collection.hitTest(tap, with: nil) === button)
        let fillerPath = try #require(dataSource.indexPath(for: "row-3"))
        let filler = try #require(collection.cellForItem(at: fillerPath) as? EpisodeCardCell)
        let coverTap = CGPoint(x: filler.frame.minX + 40, y: filler.frame.minY + 40)
        #expect(collection.hitTest(coverTap, with: nil) is ListActionTouchSink)
        engine.close(animated: false)
        #expect(engine.selectedID == nil)
        #expect(!engine.isTravelling)
        #expect(filler.actionGap == 0)
    }
}
