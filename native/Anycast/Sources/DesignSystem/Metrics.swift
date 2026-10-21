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
    /// Content inset inside sheets: 54 − 28 = 26, the radius of a 52 pt capsule, so bottom controls sit concentric with the floating sheet corner.
    static let sheetContent: CGFloat = 28
}

/// Anycast 2.0 corner radii (`AnycastRadius`).
/// Values come from the active theme (`ThemeSpec.Shape`).
nonisolated enum Radius {
    static let sm = ThemeRegistry.current.shape.sm
    static let md = ThemeRegistry.current.shape.md
    static let artwork = ThemeRegistry.current.shape.artwork
    static let card = ThemeRegistry.current.shape.card
    static let largeCard = ThemeRegistry.current.shape.largeCard
    static let modal = ThemeRegistry.current.shape.modal
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

    // Press feedback (Anycast 2.0 UI kit interaction-physics spec): scale
    // down on touch, spring back on release.
    static let pressScale: CGFloat = 0.92
    /// Cards and rows move less than buttons.
    static let pressScaleSubtle: CGFloat = 0.97
    /// The player's transport controls press deeper.
    static let pressScaleStrong: CGFloat = 0.88
    static let pressIn: TimeInterval = 0.12
    static let pressRelease: TimeInterval = 0.3
    static let pressReleaseDamping: CGFloat = 0.5

    // Scrubber physics (UI kit): a held track also widens past its ends by
    // `scrubberFocusOutset` per side; a drag past either end stretches it
    // like a rubber band, capped at `rubberBandLimit`.
    static let scrubberFocusOutset: CGFloat = 10
    static let rubberBandLimit: CGFloat = 34
    static let rubberBandResistance: CGFloat = 0.55

    /// Rubber-band offset for an `overscroll` past an end (sign preserved).
    static func rubberBand(_ overscroll: CGFloat) -> CGFloat {
        let magnitude = abs(overscroll)
        let stretched = (1 - 1 / (magnitude * rubberBandResistance / rubberBandLimit + 1)) * rubberBandLimit
        return overscroll < 0 ? -stretched : stretched
    }

    // Card list motion: a first list rises in staggered, and an expanding
    // card's action strip slides down out of the card (the card itself
    // never moves).
    /// Cards rise this far from below as they fade in.
    static let cardEntranceOffset: CGFloat = 12
    /// Per-card delay of the entrance stagger.
    static let cardEntranceStagger: TimeInterval = 0.04
    /// Cards beyond this index share the last stagger delay.
    static let cardEntranceMaxStaggered = 8
    /// The action strip slides down from the card by this much as it appears.
    static let stripRevealOffset: CGFloat = 8
    /// The action strip fades out this long before its height closes.
    static let stripFadeOut: TimeInterval = 0.12

    static var reduceMotion: Bool { UIAccessibility.isReduceMotionEnabled }

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

extension UICollectionView {
    /// Background views of a collection view do not inherit the safe area —
    /// UIKit folds it into `adjustedContentInset` — so empty and error
    /// states hosted there would sit under the header or the floating
    /// mini player. Call from `viewDidLayoutSubviews` to feed the inset in
    /// as layout margins.
    @MainActor
    func alignBackgroundViewMargins() {
        guard let backgroundView else { return }
        backgroundView.insetsLayoutMarginsFromSafeArea = false
        let inset = adjustedContentInset
        let margins = NSDirectionalEdgeInsets(
            top: inset.top + Spacing.pageH,
            leading: Spacing.pageH,
            bottom: inset.bottom + Spacing.pageH,
            trailing: Spacing.pageH
        )
        if backgroundView.directionalLayoutMargins != margins {
            backgroundView.directionalLayoutMargins = margins
        }
    }
}

extension UIControl {
    /// The shared press feedback: scale to `scale` on touch-down, spring
    /// back on release; Reduce Motion keeps the haptic but skips the scale.
    /// Callers must not add another scale effect on the same view.
    @MainActor
    func addPressFeedback(scale: CGFloat = Motion.pressScale, haptic: Bool = true) {
        addAction(UIAction { [weak self] _ in
            if haptic { Haptics.tap() }
            guard !Motion.reduceMotion else { return }
            UIView.animate(withDuration: Motion.pressIn, delay: 0, options: [.allowUserInteraction, .beginFromCurrentState]) {
                self?.transform = CGAffineTransform(scaleX: scale, y: scale)
            }
        }, for: .touchDown)
        addAction(UIAction { [weak self] _ in
            guard let self, self.transform != .identity else { return }
            UIView.animate(
                withDuration: Motion.pressRelease, delay: 0,
                usingSpringWithDamping: Motion.pressReleaseDamping, initialSpringVelocity: 0,
                options: [.allowUserInteraction, .beginFromCurrentState]
            ) { self.transform = .identity }
        }, for: [.touchUpInside, .touchUpOutside, .touchCancel, .touchDragExit])
    }
}
