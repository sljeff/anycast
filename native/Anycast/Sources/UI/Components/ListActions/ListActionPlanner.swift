import Foundation

/// Geometry only. Screen coordinates are relative to the viewport's top edge,
/// not its scrolling bounds origin. The owner supplies the already-laid-out card.
nonisolated enum ListActionPlanner {
    enum Anchor {
        case group(CGFloat)
        case item(CGFloat)
        case none
    }

    struct Insets {
        var top: CGFloat = 0
        var bottom: CGFloat = 0
    }

    /// `anchorItemFrame` lets a closing group preserve its former card's top,
    /// even though there is no longer a selected card to keep in the safe band.
    static func targetOffset(
        selectedCardFrame: CGRect?,
        anchor: Anchor,
        anchorItemFrame: CGRect? = nil,
        currentOffset: CGFloat,
        viewportHeight: CGFloat,
        topSafe: CGFloat,
        bottomSafe: CGFloat,
        contentHeight: CGFloat,
        adjustedContentInset: Insets = Insets(),
        opening: Bool
    ) -> CGFloat {
        var target = currentOffset
        switch anchor {
        case let .group(previousScreenY):
            if let card = selectedCardFrame {
                target = card.maxY + ListActionMetrics.spacing - previousScreenY
            }
        case let .item(previousScreenY):
            if let card = anchorItemFrame ?? selectedCardFrame {
                target = card.minY - previousScreenY
            }
        case .none:
            break
        }

        if let card = selectedCardFrame {
            let bottom = card.maxY + ListActionMetrics.gap - bottomSafe
            let titleTop = card.minY - topSafe
            if target < bottom {
                target = bottom
                if opening {
                    target = max(target, currentOffset + ListActionMetrics.gap)
                }
            }
            if target > titleTop {
                // An oversized card cannot satisfy both: the actions win.
                target = max(titleTop, bottom)
            }
        }

        let minimum = -adjustedContentInset.top
        let maximum = max(minimum, contentHeight - viewportHeight + adjustedContentInset.bottom)
        return min(maximum, max(minimum, target))
    }

    static func fillTarget(removedIndex: Int, countAfter: Int) -> Int? {
        guard countAfter > 0 else { return nil }
        return min(removedIndex, countAfter - 1)
    }

    /// Add to the owner's bottom inset, not to contentSize (which belongs to
    /// the layout). Remove this extension when closing, in the same FLIP pass.
    static func bottomInsetExtension(contentHeight: CGFloat, floor: CGFloat?) -> CGFloat {
        guard let floor else { return 0 }
        return max(0, floor - contentHeight)
    }
}
