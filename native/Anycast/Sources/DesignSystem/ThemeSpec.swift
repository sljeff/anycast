import UIKit

/// The swappable visual theme: every semantic color, the font faces and the
/// corner-radius scale come from one `ThemeSpec`. `Theme`, `TypographyV2`
/// and `Radius` read `ThemeRegistry.current`, so screens never change when
/// the visual style does — a restyle is a new `ThemeSpec` value plus one
/// line in `ThemeRegistry.named`.
nonisolated struct ThemeSpec: @unchecked Sendable {

    struct Palette {
        var background: UIColor
        var surface: UIColor
        var surfaceContainer: UIColor
        var surfaceContainerHigh: UIColor
        var surfaceContainerHighest: UIColor
        var outline: UIColor
        var outlineVariant: UIColor
        var onSurface: UIColor
        var onSurfaceVariant: UIColor
        var primary: UIColor
        var onPrimary: UIColor
        var primaryContainer: UIColor
        var onPrimaryContainer: UIColor
        var secondaryContainer: UIColor
        var tertiary: UIColor
        var error: UIColor
        var inverseSurface: UIColor
        var inversePrimary: UIColor

        // Fixed warm-dark player family (trait-independent).
        var playerWarm: UIColor
        var playerBackground: UIColor
        var playerText: UIColor
        var playerSecondary: UIColor
        var playerArtworkScrim: UIColor
        var transcriptSurface: UIColor
    }

    /// Text styles pick a role; the theme decides the face for each role.
    enum FontRole {
        /// Page titles, wordmark, marketing headlines.
        case display
        /// Everything else.
        case text
    }

    struct Typography {
        var font: @Sendable (_ size: CGFloat, _ weight: UIFont.Weight, _ role: FontRole) -> UIFont
    }

    struct Shape {
        var sm: CGFloat
        var md: CGFloat
        var artwork: CGFloat
        var card: CGFloat
        var largeCard: CGFloat
        var modal: CGFloat
    }

    let name: String
    let palette: Palette
    let typography: Typography
    let shape: Shape
}

nonisolated extension ThemeSpec {

    /// Anycast 2.0 sand/gold, SF Pro (display = black expanded, matching the
    /// Anycast 2.0 UI kit's `AnycastFont.display`). Colors come from the
    /// asset-catalog colorsets (light in Any, dark in Dark).
    static let sand = ThemeSpec(
        name: "sand",
        palette: Palette(
            background: named("Background"),
            surface: named("Surface"),
            surfaceContainer: named("SurfaceContainer"),
            surfaceContainerHigh: named("SurfaceContainerHigh"),
            surfaceContainerHighest: named("SurfaceContainerHighest"),
            outline: named("Outline"),
            outlineVariant: named("OutlineVariant"),
            onSurface: named("OnSurface"),
            onSurfaceVariant: named("OnSurfaceVariant"),
            primary: named("Primary"),
            onPrimary: named("OnPrimary"),
            primaryContainer: named("PrimaryContainer"),
            onPrimaryContainer: named("OnPrimaryContainer"),
            secondaryContainer: named("SecondaryContainer"),
            tertiary: named("Tertiary"),
            error: named("Error"),
            inverseSurface: named("InverseSurface"),
            inversePrimary: named("InversePrimary"),
            playerWarm: named("PlayerWarm"),
            playerBackground: named("PlayerBackground"),
            playerText: named("PlayerText"),
            playerSecondary: named("PlayerSecondary"),
            playerArtworkScrim: named("PlayerArtworkScrim"),
            transcriptSurface: named("TranscriptSurface")
        ),
        typography: Typography { size, weight, role in
            switch role {
            case .display: UIFont.systemFont(ofSize: size, weight: weight, width: .expanded)
            case .text: UIFont.systemFont(ofSize: size, weight: weight)
            }
        },
        shape: Shape(sm: 8, md: 16, artwork: 18, card: 24, largeCard: 32, modal: 58)
    )

    private static func named(_ name: String) -> UIColor {
        guard let color = UIColor(named: name) else {
            preconditionFailure("Missing colorset \(name)")
        }
        return color
    }
}

/// The theme in effect for this process. Resolved once at first access, so
/// every static token built from it stays consistent; switching themes
/// takes a relaunch.
nonisolated enum ThemeRegistry {

    /// Change the default here to restyle the app.
    static let defaultTheme = ThemeSpec.sand

    static let current: ThemeSpec = resolve(arguments: ProcessInfo.processInfo.arguments)

    /// Every theme selectable by name.
    static let named: [String: ThemeSpec] = [
        ThemeSpec.sand.name: .sand,
    ]

    /// DEBUG builds accept `-AnycastTheme <name>` to preview another theme;
    /// unknown names and release builds use `defaultTheme`.
    static func resolve(arguments: [String]) -> ThemeSpec {
        #if DEBUG
        if let flag = arguments.firstIndex(of: "-AnycastTheme"),
           arguments.indices.contains(flag + 1),
           let theme = named[arguments[flag + 1]] {
            return theme
        }
        #endif
        return defaultTheme
    }
}
