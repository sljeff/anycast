import UIKit
import Testing
@testable import Anycast

/// The theme layer: the sand theme reproduces the asset-catalog tokens in
/// both appearances, `Theme`/`TypographyV2`/`Radius` read the active theme,
/// and launch-argument selection only accepts known themes.
@MainActor
struct ThemeSpecTests {

    private let light = UITraitCollection(userInterfaceStyle: .light)
    private let dark = UITraitCollection(userInterfaceStyle: .dark)

    @Test("Sand palette matches its colorsets in light and dark")
    func sandPaletteMatchesColorsets() {
        let palette = ThemeSpec.sand.palette
        let tokens: [(String, UIColor)] = [
            ("Background", palette.background),
            ("Surface", palette.surface),
            ("SurfaceContainer", palette.surfaceContainer),
            ("SurfaceContainerHigh", palette.surfaceContainerHigh),
            ("SurfaceContainerHighest", palette.surfaceContainerHighest),
            ("Outline", palette.outline),
            ("OutlineVariant", palette.outlineVariant),
            ("OnSurface", palette.onSurface),
            ("OnSurfaceVariant", palette.onSurfaceVariant),
            ("Primary", palette.primary),
            ("OnPrimary", palette.onPrimary),
            ("PrimaryContainer", palette.primaryContainer),
            ("OnPrimaryContainer", palette.onPrimaryContainer),
            ("SecondaryContainer", palette.secondaryContainer),
            ("Tertiary", palette.tertiary),
            ("Error", palette.error),
            ("InverseSurface", palette.inverseSurface),
            ("InversePrimary", palette.inversePrimary),
            ("PlayerWarm", palette.playerWarm),
            ("PlayerBackground", palette.playerBackground),
            ("PlayerText", palette.playerText),
            ("PlayerSecondary", palette.playerSecondary),
            ("PlayerArtworkScrim", palette.playerArtworkScrim),
            ("TranscriptSurface", palette.transcriptSurface),
        ]
        for (name, color) in tokens {
            let asset = UIColor(named: name)!
            for traits in [light, dark] {
                #expect(
                    color.resolvedColor(with: traits) == asset.resolvedColor(with: traits),
                    "\(name) differs from its colorset (\(traits.userInterfaceStyle.rawValue))"
                )
            }
        }
    }

    @Test("Theme, TypographyV2 and Radius read the active theme")
    func accessorsReadActiveTheme() {
        let active = ThemeRegistry.current
        #expect(Theme.background.resolvedColor(with: dark) == active.palette.background.resolvedColor(with: dark))
        #expect(Theme.primary.resolvedColor(with: light) == active.palette.primary.resolvedColor(with: light))
        #expect(Radius.card == active.shape.card)

        let display = TypographyV2.displayLarge.font(traits: UITraitCollection(preferredContentSizeCategory: .large))
        let expected = active.typography.font(48, .black, .display)
        #expect(display.fontName == expected.fontName)
        #expect(TypographyV2.body.role == .text)
    }

    @Test("Launch-argument theme selection accepts only known names")
    func launchArgumentSelection() {
        #expect(ThemeRegistry.resolve(arguments: []).name == ThemeRegistry.defaultTheme.name)
        #expect(ThemeRegistry.resolve(arguments: ["-AnycastTheme", "sand"]).name == "sand")
        #expect(ThemeRegistry.resolve(arguments: ["-AnycastTheme", "unknown"]).name == ThemeRegistry.defaultTheme.name)
        #expect(ThemeRegistry.resolve(arguments: ["-AnycastTheme"]).name == ThemeRegistry.defaultTheme.name)
    }
}
