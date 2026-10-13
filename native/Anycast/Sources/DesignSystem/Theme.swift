import UIKit

/// Anycast 2.0 color layer (docs/migration/09 §2).
///
/// One asset-catalog colorset per token; dual-appearance sets carry the
/// light value in Any and the dark value in Dark, so every accessor is
/// trait-dynamic with no code-side branching. Values are byte-identical to
/// `lib/design_system/anycast_theme.dart` (the Flutter-side port of the same
/// Figma source of truth). `Theme.x` stays the only sanctioned color access
/// — never `UIColor(red:…)` literals in screens. Token values come from the
/// active `ThemeSpec` (ThemeSpec.swift); restyle there, not here.
///
/// Screen surfaces follow the system appearance. The player keeps its
/// intentionally dark presentation in `installPlayerBase`.
nonisolated enum Theme {

    /// The active theme's palette (`ThemeSpec`); tokens below are its stable names.
    private static let palette = ThemeRegistry.current.palette

    // MARK: - Semantic tokens (anycast_theme.dart `_build(brightness)`)

    /// Page background — sand2 / sandDark2.
    static let background = palette.background
    /// Card / sheet fill — sand1 / sandDark1.
    static let surface = palette.surface
    /// Inset fills, input fields — sand3 / sandDark3.
    static let surfaceContainer = palette.surfaceContainer
    /// Elevated inset fills — sand4 / sandDark4.
    static let surfaceContainerHigh = palette.surfaceContainerHigh
    /// Highest elevation fills — sand6 / sandDark6.
    static let surfaceContainerHighest = palette.surfaceContainerHighest
    /// Strokes / hairlines — sand6 / sandDark6.
    static let outline = palette.outline
    /// Card borders — sandAlpha4 pair.
    static let outlineVariant = palette.outlineVariant
    /// Primary text — sand12 / sandDark12.
    static let onSurface = palette.onSurface
    /// Secondary text — sand11 / sandDark11.
    static let onSurfaceVariant = palette.onSurfaceVariant
    /// Brand accent (gold) — gold9 / goldDark9.
    static let primary = palette.primary
    /// Content on gold — sand1 / sand12.
    static let onPrimary = palette.onPrimary
    /// Gold-tinted container — sandAlpha4 pair.
    static let primaryContainer = palette.primaryContainer
    static let onPrimaryContainer = palette.onPrimaryContainer
    /// Inset group container — sand3 / sandDark3.
    static let secondaryContainer = palette.secondaryContainer
    /// Orange accent — orange10 / FF8B3E.
    static let tertiary = palette.tertiary
    /// Error — BA1A1A / FF8B8B.
    static let error = palette.error
    /// Inverse surfaces (toasts) — onSurface inverted.
    static let inverseSurface = palette.inverseSurface
    static let inversePrimary = palette.inversePrimary

    // MARK: - Player (fixed warm-dark, trait-independent — 09 §2.1)

    static let playerWarm = palette.playerWarm             // 0x867D75
    static let playerBackground = palette.playerBackground // 0x222221
    static let playerText = palette.playerText             // 0xEEEEEC
    static let playerSecondary = palette.playerSecondary   // 0xD2D0CA
    static let playerArtworkScrim = palette.playerArtworkScrim
    static let transcriptSurface = palette.transcriptSurface

    /// Artwork scrim gradient over `playerWarm` (anycast_theme.dart
    /// `playerGradientOverlayColors`, alpha-blended over the warm base).
    static var playerGradientStops: [UIColor] {
        [0.20, 0.25, 0.376, 0.40, 0.50].map { playerWarm.withAlphaComponent($0) }
    }

    /// The palette fallback when a cover yields no dominant color. v2 keys
    /// artwork gradients to the player's warm base.
    static let paletteFallback = playerBackground

    // MARK: - Chrome

    /// Applies the semantic page surface without overriding system appearance.
    @MainActor
    static func installPageBase(on view: UIView) {
        view.backgroundColor = background
        view.overrideUserInterfaceStyle = .unspecified
    }

    /// The full-screen player intentionally uses the warm-dark UI kit palette.
    @MainActor
    static func installPlayerBase(on view: UIView) {
        view.backgroundColor = playerBackground
        view.overrideUserInterfaceStyle = .dark
    }

    // MARK: - Legacy v1 bridge
    //
    // The v1 color aliases are retired; only the gradient wordmark pair
    // remains for `GradientTextLabel` (specimen snapshot only).

    /// AppBar gradient title — the v2 header drops the gradient wordmark;
    /// `GradientTextLabel` retires with the PodcastsTabContainer rework
    /// (V2 phase). Fades gold → transparent for the interim.
    static let appBarGradientStart = primary
    static let appBarGradientEnd = primary.withAlphaComponent(0)
}

/// Raw Anycast 2.0 scale tokens (`AnycastColor` in anycast_theme.dart) for
/// the few places a screen needs a scale step the semantic layer does not
/// model (e.g. the tab-strip alpha pills, gold hairlines on artwork).
nonisolated enum AnycastColor {
    static let sand1 = UIColor(named: "Sand1")!
    static let sand2 = UIColor(named: "Sand2")!
    static let sand3 = UIColor(named: "Sand3")!
    static let sand4 = UIColor(named: "Sand4")!
    static let sand6 = UIColor(named: "Sand6")!
    static let sand7 = UIColor(named: "Sand7")!
    static let sand9 = UIColor(named: "Sand9")!
    static let sand10 = UIColor(named: "Sand10")!
    static let sand11 = UIColor(named: "Sand11")!
    static let sand12 = UIColor(named: "Sand12")!

    static let sandDark1 = UIColor(named: "SandDark1")!
    static let sandDark2 = UIColor(named: "SandDark2")!
    static let sandDark3 = UIColor(named: "SandDark3")!
    static let sandDark4 = UIColor(named: "SandDark4")!
    static let sandDark6 = UIColor(named: "SandDark6")!
    static let sandDark9 = UIColor(named: "SandDark9")!
    static let sandDark11 = UIColor(named: "SandDark11")!
    static let sandDark12 = UIColor(named: "SandDark12")!

    static let gold9 = UIColor(named: "Gold9")!
    static let gold10 = UIColor(named: "Gold10")!
    static let goldDark9 = UIColor(named: "GoldDark9")!
    static let goldDark10 = UIColor(named: "GoldDark10")!
    static let goldSoft = UIColor(named: "GoldSoft")!
    static let orange10 = UIColor(named: "Orange10")!
    static let grass9 = UIColor(named: "Grass9")!

    static let sandAlpha2 = UIColor(named: "SandAlpha2")!
    static let sandAlpha3 = UIColor(named: "SandAlpha3")!
    static let sandAlpha4 = UIColor(named: "SandAlpha4")!
    static let sandAlpha5 = UIColor(named: "SandAlpha5")!
    static let sandAlpha8 = UIColor(named: "SandAlpha8")!
    static let sandAlpha9 = UIColor(named: "SandAlpha9")!
    static let sandAlpha10 = UIColor(named: "SandAlpha10")!
    static let sandAlpha11 = UIColor(named: "SandAlpha11")!
    static let sandAlpha12 = UIColor(named: "SandAlpha12")!

    static let goldAlpha2 = UIColor(named: "GoldAlpha2")!
    static let goldAlpha3 = UIColor(named: "GoldAlpha3")!
    static let goldAlpha7 = UIColor(named: "GoldAlpha7")!
    static let goldAlpha9 = UIColor(named: "GoldAlpha9")!
    static let goldAlpha10 = UIColor(named: "GoldAlpha10")!
}

extension UIView {
    /// Sets a layer border from a dynamic token and keeps it in step with
    /// appearance changes — `layer.borderColor` is a CGColor, frozen at
    /// assignment (09 §9a). Call once per view, at setup.
    @MainActor
    func setDynamicBorderColor(_ color: UIColor) {
        layer.borderColor = color.resolvedColor(with: traitCollection).cgColor
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (view: UIView, _) in
            view.layer.borderColor = color.resolvedColor(with: view.traitCollection).cgColor
        }
    }
}
