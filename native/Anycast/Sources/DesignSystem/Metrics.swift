import QuartzCore
import UIKit

/// Anycast 2.0 spacing scale — a strict 4-point grid with named steps
/// (`AnycastSpacing` in anycast_theme.dart, docs/migration/09 §2.3).
/// Migrated screens must use these instead of per-view literal constants.
nonisolated enum Spacing {
    static let hairline: CGFloat = 1

    static let xxs: CGFloat = 2
    static let xs: CGFloat = 4
    static let sm: CGFloat = 6
    static let md: CGFloat = 8
    static let row: CGFloat = 10
    static let gap: CGFloat = 12
    static let chip: CGFloat = 14
    static let pageH: CGFloat = 16
    static let cardInner: CGFloat = 20
    static let pageHeader: CGFloat = 24
    static let sectionGap: CGFloat = 28
    static let large: CGFloat = 32
    static let pageSection: CGFloat = 36
    static let xl: CGFloat = 40
    static let xxl: CGFloat = 48

    // Derived constants pinned by the design (anycast_theme.dart).
    static let compactProgress = xs
    static let playerProgress = sm
    /// Floating surface outset over page content (pageHeader − pageH).
    static let floatingOutset: CGFloat = 8
    static let sheetTitleH: CGFloat = 64
    static let rowH: CGFloat = 70
    static let pageBottomSafe: CGFloat = 88
}

/// Anycast 2.0 corner radii (`AnycastRadius`).
nonisolated enum Radius {
    static let sm: CGFloat = 8
    static let md: CGFloat = 16
    static let artwork: CGFloat = 18
    static let card: CGFloat = 24
    static let largeCard: CGFloat = 32
    static let modal: CGFloat = 58
    /// Capsules; clamp at draw time, this just exceeds any frame.
    static let pill: CGFloat = 999
}

/// Anycast 2.0 motion durations and curves (`AnycastMotion`).
nonisolated enum Motion {
    static let quick: TimeInterval = 0.18
    static let standard: TimeInterval = 0.28
    static let emphasized: TimeInterval = 0.42

    /// `Curves.easeOutCubic` — cubic-bezier(0.215, 0.61, 0.355, 1).
    /// Computed: CAMediaTimingFunction is not Sendable, so it cannot be a
    /// shared static in a nonisolated context.
    static var standardCurve: CAMediaTimingFunction {
        CAMediaTimingFunction(controlPoints: 0.215, 0.61, 0.355, 1)
    }

    /// `UIView.animate` convenience with the standard v2 curve/duration.
    @MainActor
    static func animate(_ duration: TimeInterval = Motion.standard, _ animations: @escaping () -> Void, completion: (() -> Void)? = nil) {
        UIView.animate(
            withDuration: duration,
            delay: 0,
            options: [.curveEaseOut, .allowUserInteraction],
            animations: animations
        ) { _ in
            completion?()
        }
    }
}
