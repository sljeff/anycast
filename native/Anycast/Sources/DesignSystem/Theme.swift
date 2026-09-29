import UIKit

/// Color accessors over the Asset Catalog colorsets — one colorset per token
/// in docs/migration/03 §5.1 (`lib/styles.dart` DarkColor plus the
/// high-frequency hardcoded values). The app is dark-only, so every colorset
/// carries a single Any-appearance value; these accessors are the only way
/// UI code should reach a color (never `UIColor(red:…)` literals).
nonisolated enum Theme {

    // DarkColor tokens (03 §5.1)
    static let primary = UIColor(named: "PrimaryColor")!                    // 0x34D399
    static let primaryLightPlus1 = UIColor(named: "PrimaryLightPlus1")!     // 0xA7F3D0
    static let primaryLightMax = UIColor(named: "PrimaryLightMax")!         // 0xECFDF5 (main text white)
    static let primaryDark = UIColor(named: "PrimaryDark")!                 // 0x079669
    static let primaryBackground = UIColor(named: "PrimaryBackground")!     // 0x30444E
    static let primaryBackgroundDark = UIColor(named: "PrimaryBackgroundDark")! // 0x111316 page/sheet bg
    static let accent = UIColor(named: "AccentColor")!                      // 0xFFBC25
    static let secondaryText = UIColor(named: "SecondaryColor")!            // 0x96A7AF

    // High-frequency hardcoded values (03 §5.1)
    static let cardBackground = UIColor(named: "CardBackground")!           // 0x232830
    static let tabSelectedGreen = UIColor(named: "TabSelectedGreen")!       // 0x6EE7B7
    static let brandGreen = UIColor(named: "BrandGreen")!                   // 0x10B981
    static let secondaryLabelGray = UIColor(named: "SecondaryTextGray")!    // 0x6B7280
    static let hintGray = UIColor(named: "HintGray")!                       // 0x4B5563
    static let loginCardBackground = UIColor(named: "LoginCardBackground")! // 0x1E1E1E

    /// Card/list border — Material `grey[800]` in the Dart baseline (03 §2.11).
    static let cardOutline = UIColor(named: "CardOutline")!                 // 0x424242

    // Lyrics (03 §2.10) — no separate colorset; literal-value tokens keep
    // Typography off raw `UIColor(red:)` literals with pixel-identical
    // values to the inline colors they replace.
    /// Lyric main line — Flutter `Colors.grey[200]`.
    static let lyricGrey200 = UIColor(red: 0.937, green: 0.961, blue: 0.965, alpha: 1)
    /// Lyric active/translation line — Flutter `Colors.greenAccent`.
    static let lyricGreenAccent = UIColor(red: 0.412, green: 0.941, blue: 0.678, alpha: 1)

    // AppBar gradient title stops (03 §5.1): 0xFF059669 → same hue, alpha 0.
    static let appBarGradientStart = UIColor(named: "AppBarGradientStart")!
    static let appBarGradientEnd = UIColor(named: "AppBarGradientEnd")!

    /// The palette fallback when a cover yields no dominant color
    /// (03 §5.4: `updatePaletteGenerator` default 0xFF111316).
    static let paletteFallback = primaryBackgroundDark

    /// Applies the app-wide dark chrome to a plain container: page background
    /// + dark status bar. Views that need glass (07 §4) use GlassContainerView
    /// instead of painting their own surface.
    static func installDarkBase(on view: UIView) {
        view.backgroundColor = primaryBackgroundDark
        view.overrideUserInterfaceStyle = .dark
    }
}
