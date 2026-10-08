import UIKit

/// Anycast 2.0 color layer (docs/migration/09 §2).
///
/// One asset-catalog colorset per token; dual-appearance sets carry the
/// light value in Any and the dark value in Dark, so every accessor is
/// trait-dynamic with no code-side branching. Values are byte-identical to
/// `lib/design_system/anycast_theme.dart` (the Flutter-side port of the same
/// Figma source of truth). `Theme.x` stays the only sanctioned color access
/// — never `UIColor(red:…)` literals in screens.
///
/// The app still force-installs the dark chrome (`installDarkBase`) until
/// the V3 per-screen migration completes; the trait flip is the final V4
/// step, not a drive-by change (09 §10).
nonisolated enum Theme {

    // MARK: - Semantic tokens (anycast_theme.dart `_build(brightness)`)

    /// Page background — sand2 / sandDark2.
    static let background = UIColor(named: "Background")!
    /// Card / sheet fill — sand1 / sandDark1.
    static let surface = UIColor(named: "Surface")!
    /// Inset fills, input fields — sand3 / sandDark3.
    static let surfaceContainer = UIColor(named: "SurfaceContainer")!
    /// Elevated inset fills — sand4 / sandDark4.
    static let surfaceContainerHigh = UIColor(named: "SurfaceContainerHigh")!
    /// Highest elevation fills — sand6 / sandDark6.
    static let surfaceContainerHighest = UIColor(named: "SurfaceContainerHighest")!
    /// Strokes / hairlines — sand6 / sandDark6.
    static let outline = UIColor(named: "Outline")!
    /// Card borders — sandAlpha4 pair.
    static let outlineVariant = UIColor(named: "OutlineVariant")!
    /// Primary text — sand12 / sandDark12.
    static let onSurface = UIColor(named: "OnSurface")!
    /// Secondary text — sand11 / sandDark11.
    static let onSurfaceVariant = UIColor(named: "OnSurfaceVariant")!
    /// Brand accent (gold) — gold9 / goldDark9.
    static let primary = UIColor(named: "Primary")!
    /// Content on gold — sand1 / sand12.
    static let onPrimary = UIColor(named: "OnPrimary")!
    /// Gold-tinted container — sandAlpha4 pair.
    static let primaryContainer = UIColor(named: "PrimaryContainer")!
    static let onPrimaryContainer = UIColor(named: "OnPrimaryContainer")!
    /// Inset group container — sand3 / sandDark3.
    static let secondaryContainer = UIColor(named: "SecondaryContainer")!
    /// Orange accent — orange10 / FF8B3E.
    static let tertiary = UIColor(named: "Tertiary")!
    /// Error — BA1A1A / FF8B8B.
    static let error = UIColor(named: "Error")!
    /// Inverse surfaces (toasts) — onSurface inverted.
    static let inverseSurface = UIColor(named: "InverseSurface")!
    static let inversePrimary = UIColor(named: "InversePrimary")!

    // MARK: - Player (fixed warm-dark, trait-independent — 09 §2.1)

    static let playerWarm = UIColor(named: "PlayerWarm")!             // 0x867D75
    static let playerBackground = UIColor(named: "PlayerBackground")! // 0x222221
    static let playerText = UIColor(named: "PlayerText")!             // 0xEEEEEC
    static let playerSecondary = UIColor(named: "PlayerSecondary")!   // 0xD2D0CA
    static let playerArtworkScrim = UIColor(named: "PlayerArtworkScrim")!
    static let transcriptSurface = UIColor(named: "TranscriptSurface")!

    /// Artwork scrim gradient over `playerWarm` (anycast_theme.dart
    /// `playerGradientOverlayColors`, alpha-blended over the warm base).
    static var playerGradientStops: [UIColor] {
        [0.20, 0.25, 0.376, 0.40, 0.50].map { playerWarm.withAlphaComponent($0) }
    }

    /// The palette fallback when a cover yields no dominant color. v2 keys
    /// artwork gradients to the player's warm base.
    static let paletteFallback = playerBackground

    // MARK: - Chrome

    /// Applies the app-wide dark chrome to a plain container. NOTE: the
    /// `overrideUserInterfaceStyle = .dark` force is a TRANSITIONAL v1
    /// holdover — v2 is dual-theme and this override is removed in V4 once
    /// every screen has been audited for light mode (09 §10 V4).
    static func installDarkBase(on view: UIView) {
        view.backgroundColor = background
        view.overrideUserInterfaceStyle = .dark
    }

    // MARK: - Legacy v1 bridge
    //
    // Transitional v1 accessor names re-pointed at v2 semantics so the
    // not-yet-migrated screens keep compiling and render a plausible v2
    // dark look. Each accessor is deleted together with its last consumer
    // during the V3 per-screen migration (09 §10); do not add new uses.

    /// Was the near-white main text → onSurface.
    static let primaryLightMax = onSurface
    static let primaryLightPlus1 = primary
    static let primaryDark = onSurfaceVariant
    /// Was 0x30444E panels → elevated container.
    static let primaryBackground = surfaceContainerHigh
    /// Was 0x111316 page background → background.
    static let primaryBackgroundDark = background
    /// Was 0xFFBC25 yellow accent → orange tertiary.
    static let accent = tertiary
    /// Was 0x96A7AF secondary text → onSurfaceVariant.
    static let secondaryText = onSurfaceVariant
    /// Was 0x232830 card fill → surface.
    static let cardBackground = surface
    /// Was 0x6EE7B7 tab tint → gold accent.
    static let tabSelectedGreen = primary
    /// Was 0x10B981 brand green → grass.
    static let brandGreen = AnycastColor.grass9
    /// Was 0x6B7280 → onSurfaceVariant.
    static let secondaryLabelGray = onSurfaceVariant
    /// Was 0x4B5563 → sandDark9.
    static let hintGray = AnycastColor.sandDark9
    /// Was 0x1E1E1E login card → container.
    static let loginCardBackground = surfaceContainer
    /// Was 0x424242 card border → outline.
    static let cardOutline = outline

    /// Lyric line colors pinned to the v1 rendering; the transcript screen
    /// owns them and re-baselines in V3 batch 3 (09 §4 S13/S14).
    static let lyricGrey200 = UIColor(red: 0.937, green: 0.961, blue: 0.965, alpha: 1)
    static let lyricGreenAccent = UIColor(red: 0.412, green: 0.941, blue: 0.678, alpha: 1)

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
