import UIKit

/// Semantic text styles porting `lib/styles.dart` (DarkColor) and the usages
/// enumerated in docs/migration/03 §5.2. Each style knows its bundled
/// PostScript name, size, tracking, color, and the UIFontMetrics text style
/// that governs Dynamic Type scaling (a migration improvement over the Dart
/// baseline, which had no text-scale handling at all — 03 §8).
///
/// Fonts are static instances of the Google variable fonts, instanced with
/// fonttools and registered through UIAppFonts:
///   Comfortaa-Regular/-Bold, NotoSans-Regular/-Bold, Inter-Regular,
///   MPLUSRounded1c-Regular (PS name "RoundedMplus1c-Regular"),
///   Roboto-Regular, RobotoMono-Regular.
nonisolated enum Typography {

    struct Style {
        let postScriptName: String
        let size: CGFloat
        /// Letter tracking in points (`kern`); applied via the attributed
        /// helper, since plain `UILabel.font` cannot carry it.
        let kern: CGFloat
        let color: UIColor
        /// Governs UIFontMetrics scaling; pass `nil` to opt out (fixed-size
        /// display numerals, e.g. the lyric time bar).
        let scalingTextStyle: UIFont.TextStyle?

        /// Renders in the active theme's text face (SF Pro for sand) — the
        /// bundled v1 family only decides weight and monospacing, so legacy
        /// call sites share the v2 typeface.
        func font(traits: UITraitCollection? = nil) -> UIFont {
            let base: UIFont
            if postScriptName.hasPrefix("RobotoMono") {
                base = .monospacedSystemFont(ofSize: size, weight: .regular)
            } else {
                let weight: UIFont.Weight = postScriptName.hasSuffix("-Bold") ? .bold : .regular
                base = ThemeRegistry.current.typography.font(size, weight, .text)
            }
            guard let scalingTextStyle else { return base }
            let metrics = UIFontMetrics(forTextStyle: scalingTextStyle)
            if let traits {
                return metrics.scaledFont(for: base, compatibleWith: traits)
            }
            return metrics.scaledFont(for: base)
        }

        /// Attributed-string attributes covering font, tracking and color.
        func attributes(traits: UITraitCollection? = nil) -> [NSAttributedString.Key: Any] {
            [
                .font: font(traits: traits),
                .kern: kern,
                .foregroundColor: color,
            ]
        }
    }

    // MARK: - styles.dart (DarkColor)

    /// 12pt inter, secondary text (styles.dart defaultText).
    static let defaultText = Style(
        postScriptName: "Inter-Regular", size: 12, kern: 0,
        color: Theme.onSurfaceVariant, scalingTextStyle: .caption1
    )

    // MARK: - Misc pinned sizes

    /// HTML render error text — 12pt roboto mono, red (formatters renderHtml).
    static let htmlError = Style(
        postScriptName: "RobotoMono-Regular", size: 12, kern: 0,
        color: .systemRed, scalingTextStyle: .caption1
    )

    /// All semantic styles, for tests and enumerations.
    static let allStyles: [Style] = [defaultText, htmlError]
}

extension Typography.Style {
    // Member-style access (`style: Typography.Style = .defaultText`); the
    // canonical statics live on Typography itself.
    static let defaultText = Typography.defaultText
    static let htmlError = Typography.htmlError
}

/// Anycast 2.0 text styles (docs/migration/09 §2.4) — the system face (the
/// Figma file's Inter is a stand-in for the platform font; the Flutter port
/// likewise uses `.AppleSystemUIFont`) with the v2 size/weight/line-height
/// scale. Screens consume these; only `defaultText` and `htmlError` remain in
/// the v1 `Style` statics above.
nonisolated enum TypographyV2 {

    struct Style {
        let size: CGFloat
        /// Design line height; applied via the paragraph-style attribute so
        /// multiline labels honor it (single-line labels can ignore it).
        let lineHeight: CGFloat
        let weight: UIFont.Weight
        let color: UIColor
        let scalingTextStyle: UIFont.TextStyle
        /// Which theme face renders this style (`ThemeSpec.Typography`).
        var role: ThemeSpec.FontRole = .text

        func font(traits: UITraitCollection? = nil) -> UIFont {
            let base = ThemeRegistry.current.typography.font(size, weight, role)
            let metrics = UIFontMetrics(forTextStyle: scalingTextStyle)
            if let traits {
                return metrics.scaledFont(for: base, compatibleWith: traits)
            }
            return metrics.scaledFont(for: base)
        }

        /// Attributed-string attributes covering font, line height and color.
        func attributes(traits: UITraitCollection? = nil) -> [NSAttributedString.Key: Any] {
            let paragraph = NSMutableParagraphStyle()
            paragraph.minimumLineHeight = lineHeight
            paragraph.maximumLineHeight = lineHeight
            return [
                .font: font(traits: traits),
                .paragraphStyle: paragraph.copy(),
                .foregroundColor: color,
            ]
        }
    }

    static let displayLarge = Style(size: 48, lineHeight: 48, weight: .black, color: Theme.onSurface, scalingTextStyle: .largeTitle, role: .display)
    static let displayMedium = Style(size: 34, lineHeight: 41, weight: .regular, color: Theme.onSurface, scalingTextStyle: .largeTitle)
    static let displaySmall = Style(size: 28, lineHeight: 34, weight: .regular, color: Theme.onSurface, scalingTextStyle: .title1)
    static let headlineMedium = Style(size: 22, lineHeight: 28, weight: .semibold, color: Theme.onSurface, scalingTextStyle: .title2)

    // The three app-wide text styles (adopted 2026-10-21). Screens use these;
    // the display and headline styles above are the hero exceptions:
    // `displayLarge` is the 48 pt tab title, `displayMedium` / `displaySmall`
    // are the Welcome / Sign Up wordmarks, and `headlineMedium` is the 22 pt
    // Now Playing title.
    /// Titles, row names, button labels and chips.
    static let emphasis = Style(size: 17, lineHeight: 22, weight: .semibold, color: Theme.onSurface, scalingTextStyle: .headline)
    /// Reading text, field input and settings rows.
    static let body = Style(size: 15, lineHeight: 20, weight: .regular, color: Theme.onSurface, scalingTextStyle: .subheadline)
    /// Subtitles, durations, hints and list descriptions.
    static let meta = Style(size: 15, lineHeight: 20, weight: .regular, color: Theme.onSurfaceVariant, scalingTextStyle: .subheadline)

    /// All v2 styles, for tests and enumerations.
    static let allStyles: [Style] = [
        displayLarge, displayMedium, displaySmall, headlineMedium,
        emphasis, body, meta,
    ]
}

extension TypographyV2.Style {
    // Member-style access (`style: TypographyV2.Style = .emphasis`).
    static let displayLarge = TypographyV2.displayLarge
    static let displayMedium = TypographyV2.displayMedium
    static let displaySmall = TypographyV2.displaySmall
    static let headlineMedium = TypographyV2.headlineMedium
    static let emphasis = TypographyV2.emphasis
    static let body = TypographyV2.body
    static let meta = TypographyV2.meta
}

extension UIFont {
    /// Same face with tabular (monospaced) digits, for times and counters
    /// that change in place.
    func monospacedDigits() -> UIFont {
        let descriptor = fontDescriptor.addingAttributes([
            .featureSettings: [[
                UIFontDescriptor.FeatureKey.type: kNumberSpacingType,
                UIFontDescriptor.FeatureKey.selector: kMonospacedNumbersSelector,
            ]],
        ])
        return UIFont(descriptor: descriptor, size: pointSize)
    }
}
