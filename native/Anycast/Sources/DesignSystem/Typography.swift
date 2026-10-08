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

        func font(traits: UITraitCollection? = nil) -> UIFont {
            guard let base = UIFont(name: postScriptName, size: size) else {
                assertionFailure("Font \(postScriptName) not registered — check UIAppFonts")
                return UIFont.systemFont(ofSize: size)
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

    /// AppBar/logo display title — 44pt comfortaa w700, tracking 4.4
    /// (styles.dart mainTitle).
    static let mainTitle = Style(
        postScriptName: "Comfortaa-Bold", size: 44, kern: 4.4,
        color: Theme.primaryLightMax, scalingTextStyle: .largeTitle
    )

    /// 24pt comfortaa w700, tracking 2.4 (styles.dart secondaryTitle).
    static let secondaryTitle = Style(
        postScriptName: "Comfortaa-Bold", size: 24, kern: 2.4,
        color: Theme.primaryLightMax, scalingTextStyle: .title1
    )

    /// 14pt comfortaa regular (styles.dart defaultMainText).
    static let mainText = Style(
        postScriptName: "Comfortaa-Regular", size: 14, kern: 0,
        color: Theme.primaryLightMax, scalingTextStyle: .subheadline
    )

    /// 16pt notoSans w700 (styles.dart defaultTitle / cardTitleBold). This
    /// is the DarkColor DIALOG/heading token — NOT the episode-card title:
    /// card.dart renders that with `textTheme.titleLarge`, whose base
    /// applies the system font, so EpisodeCardCell's system-font title is
    /// the parity rendering and must not switch to this style.
    static let cardTitleBold = Style(
        postScriptName: "NotoSans-Bold", size: 16, kern: 0,
        color: Theme.primaryLightMax, scalingTextStyle: .headline
    )
    static let defaultTitle = cardTitleBold

    /// 12pt inter, primary green (styles.dart cardTextLight).
    static let cardTextLight = Style(
        postScriptName: "Inter-Regular", size: 12, kern: 0,
        color: Theme.primary, scalingTextStyle: .caption1
    )

    /// 12pt inter, secondary text (styles.dart defaultText).
    static let defaultText = Style(
        postScriptName: "Inter-Regular", size: 12, kern: 0,
        color: Theme.secondaryText, scalingTextStyle: .caption1
    )

    /// Card description — 12pt inter on 0x6B7280 (03 §2.11).
    static let cardDescription = Style(
        postScriptName: "Inter-Regular", size: 12, kern: 0,
        color: Theme.secondaryLabelGray, scalingTextStyle: .caption1
    )

    // MARK: - Player / lyrics (03 §2.10)

    /// Lyric main line — 14pt M PLUS Rounded 1c on grey[200].
    static let lyricMain = Style(
        postScriptName: "RoundedMplus1c-Regular", size: 14, kern: 0,
        color: Theme.lyricGrey200,
        scalingTextStyle: .subheadline
    )

    /// Lyric active line — 16pt, greenAccent.
    static let lyricActive = Style(
        postScriptName: "RoundedMplus1c-Regular", size: 16, kern: 0,
        color: Theme.lyricGreenAccent,
        scalingTextStyle: .body
    )

    /// Lyric translation — 14pt greenAccent (active translation grey[300]).
    static let lyricTranslation = Style(
        postScriptName: "RoundedMplus1c-Regular", size: 14, kern: 0,
        color: Theme.lyricGreenAccent,
        scalingTextStyle: .subheadline
    )

    // MARK: - Misc pinned sizes

    /// Secondary tab labels — 12pt comfortaa (main.dart TabBar theme).
    static let tabLabel = Style(
        postScriptName: "Comfortaa-Regular", size: 12, kern: 0,
        color: Theme.primaryLightMax, scalingTextStyle: .caption1
    )

    /// Login menu small text — roboto (login.dart:237).
    static let loginSmall = Style(
        postScriptName: "Roboto-Regular", size: 14, kern: 0,
        color: Theme.primaryLightMax, scalingTextStyle: .subheadline
    )

    /// HTML render error text — 12pt roboto mono, red (formatters renderHtml).
    static let htmlError = Style(
        postScriptName: "RobotoMono-Regular", size: 12, kern: 0,
        color: .systemRed, scalingTextStyle: .caption1
    )

    /// HTML show-notes body — white 14pt, line height 1.2 (03 §7). Dart
    /// truth: `renderHtml` styled the body with `textTheme.bodyMedium`
    /// (formatters.dart:164) and the theme's base text theme applies
    /// '.AppleSystemUIFont' — the Dart body rendered in the SYSTEM face.
    /// This style pins Inter-Regular instead; that divergence is baked into
    /// the committed screen baselines, so changing the face is a deliberate
    /// re-baseline decision, not a drive-by fix.
    static let htmlBody = Style(
        postScriptName: "Inter-Regular", size: 14, kern: 0,
        color: Theme.primaryLightMax, scalingTextStyle: .subheadline
    )

    /// All semantic styles, for tests and enumerations.
    static let allStyles: [Style] = [
        mainTitle, secondaryTitle, mainText, cardTitleBold, cardTextLight,
        defaultText, cardDescription, lyricMain, lyricActive, lyricTranslation,
        tabLabel, loginSmall, htmlError, htmlBody,
    ]
}

extension Typography.Style {
    // Member-style access (`style: Typography.Style = .mainTitle`); the
    // canonical statics live on Typography itself.
    static let mainTitle = Typography.mainTitle
    static let secondaryTitle = Typography.secondaryTitle
    static let mainText = Typography.mainText
    static let cardTitleBold = Typography.cardTitleBold
    static let defaultTitle = Typography.defaultTitle
    static let cardTextLight = Typography.cardTextLight
    static let defaultText = Typography.defaultText
    static let cardDescription = Typography.cardDescription
    static let lyricMain = Typography.lyricMain
    static let lyricActive = Typography.lyricActive
    static let lyricTranslation = Typography.lyricTranslation
    static let tabLabel = Typography.tabLabel
    static let loginSmall = Typography.loginSmall
    static let htmlError = Typography.htmlError
    static let htmlBody = Typography.htmlBody
}

/// Anycast 2.0 text styles (docs/migration/09 §2.4) — the system face (the
/// Figma file's Inter is a stand-in for the platform font; the Flutter port
/// likewise uses `.AppleSystemUIFont`) with the v2 size/weight/line-height
/// scale. New v2 screens consume these; the v1 `Style` statics above retire
/// per-screen during the V3 migration.
nonisolated enum TypographyV2 {

    struct Style {
        let size: CGFloat
        /// Design line height; applied via the paragraph-style attribute so
        /// multiline labels honor it (single-line labels can ignore it).
        let lineHeight: CGFloat
        let weight: UIFont.Weight
        let color: UIColor
        let scalingTextStyle: UIFont.TextStyle

        func font(traits: UITraitCollection? = nil) -> UIFont {
            let base = UIFont.systemFont(ofSize: size, weight: weight)
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

    static let displayLarge = Style(size: 48, lineHeight: 48, weight: .black, color: Theme.onSurface, scalingTextStyle: .largeTitle)
    static let displayMedium = Style(size: 34, lineHeight: 41, weight: .regular, color: Theme.onSurface, scalingTextStyle: .largeTitle)
    static let displaySmall = Style(size: 28, lineHeight: 34, weight: .regular, color: Theme.onSurface, scalingTextStyle: .title1)
    static let headlineLarge = Style(size: 28, lineHeight: 34, weight: .semibold, color: Theme.onSurface, scalingTextStyle: .title1)
    static let headlineMedium = Style(size: 22, lineHeight: 28, weight: .semibold, color: Theme.onSurface, scalingTextStyle: .title2)
    static let headlineSmall = Style(size: 17, lineHeight: 22, weight: .semibold, color: Theme.onSurface, scalingTextStyle: .headline)
    static let titleLarge = Style(size: 20, lineHeight: 25, weight: .semibold, color: Theme.onSurface, scalingTextStyle: .title2)
    static let titleMedium = Style(size: 16, lineHeight: 21, weight: .medium, color: Theme.onSurface, scalingTextStyle: .body)
    static let titleSmall = Style(size: 15, lineHeight: 20, weight: .semibold, color: Theme.onSurface, scalingTextStyle: .subheadline)
    static let bodyLarge = Style(size: 17, lineHeight: 22, weight: .regular, color: Theme.onSurface, scalingTextStyle: .body)
    static let bodyMedium = Style(size: 15, lineHeight: 20, weight: .regular, color: Theme.onSurface, scalingTextStyle: .subheadline)
    static let bodySmall = Style(size: 13, lineHeight: 18, weight: .regular, color: Theme.onSurface, scalingTextStyle: .footnote)
    static let labelLarge = Style(size: 17, lineHeight: 22, weight: .semibold, color: Theme.onSurface, scalingTextStyle: .body)
    static let labelMedium = Style(size: 12, lineHeight: 16, weight: .semibold, color: Theme.onSurface, scalingTextStyle: .caption1)
    static let labelSmall = Style(size: 11, lineHeight: 13, weight: .medium, color: Theme.onSurface, scalingTextStyle: .caption2)

    /// All v2 styles, for tests and enumerations.
    static let allStyles: [Style] = [
        displayLarge, displayMedium, displaySmall, headlineLarge, headlineMedium,
        headlineSmall, titleLarge, titleMedium, titleSmall, bodyLarge, bodyMedium,
        bodySmall, labelLarge, labelMedium, labelSmall,
    ]
}

extension TypographyV2.Style {
    // Member-style access (`style: TypographyV2.Style = .headlineSmall`).
    static let displayLarge = TypographyV2.displayLarge
    static let displayMedium = TypographyV2.displayMedium
    static let displaySmall = TypographyV2.displaySmall
    static let headlineLarge = TypographyV2.headlineLarge
    static let headlineMedium = TypographyV2.headlineMedium
    static let headlineSmall = TypographyV2.headlineSmall
    static let titleLarge = TypographyV2.titleLarge
    static let titleMedium = TypographyV2.titleMedium
    static let titleSmall = TypographyV2.titleSmall
    static let bodyLarge = TypographyV2.bodyLarge
    static let bodyMedium = TypographyV2.bodyMedium
    static let bodySmall = TypographyV2.bodySmall
    static let labelLarge = TypographyV2.labelLarge
    static let labelMedium = TypographyV2.labelMedium
    static let labelSmall = TypographyV2.labelSmall
}
