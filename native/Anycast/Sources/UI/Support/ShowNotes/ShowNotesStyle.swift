import UIKit

/// Visual definition for the show-notes rich-text pipeline — deliberately
/// ONE tier. Machine-generated show notes get no typographic hierarchy
/// beyond a single heading step: the app's `body` style for everything,
/// `emphasis` (semibold) for every heading level, system mono at the surrounding size.
/// The v1 WebKit pipeline reached the same place by post-hoc normalization
/// (`HTMLContentRenderer.rebasedFont`); this style states it up front.
///
/// Every metric ShowNotesBuilder consumes lives here so tests pin exact
/// values, and a future retheme is one struct away. Values resolve from
/// the design-system tokens (`TypographyV2`, `Theme`, `Spacing`,
/// `Radius`); do not bypass them with literals.
struct ShowNotesStyle {

    // MARK: Type

    /// Body text — the app-wide `body` text style (reading text).
    var body: TypographyV2.Style = .body

    /// THE heading tier — the app-wide `emphasis` style (semibold). h1–h6 all
    /// collapse here; there is intentionally no second heading size.
    var heading: TypographyV2.Style = .emphasis

    // MARK: Color

    /// Links, wherever they occur (a link inside a heading keeps the
    /// heading font; only the color changes).
    var linkColor: UIColor = Theme.primary
    /// Quote body text.
    var quoteColor: UIColor = Theme.onSurfaceVariant
    /// Divider dots and other secondary furniture.
    var secondaryColor: UIColor = Theme.onSurfaceVariant
    /// Code block fill (`.backgroundColor` on the block's runs; inline
    /// code gets NO background).
    var codeBackgroundColor: UIColor = Theme.surfaceContainer
    /// Code block text.
    var codeTextColor: UIColor = Theme.onSurface

    // MARK: Spacing (v2 tokens)

    /// Line-height multiple carried over from the v1 pipeline (03 §7).
    var lineHeightMultiple: CGFloat = 1.2

    /// Space around plain paragraph blocks — `Spacing.md`. Inter-block
    /// gaps resolve as max(previous after, next before), so md paragraphs
    /// sit Spacing.md apart while a heading's larger spacing wins on
    /// either side of it.
    var paragraphSpacing: CGFloat = Spacing.md

    /// Space before and after every heading block — `Spacing.gap +
    /// Spacing.md`.
    var headingSpacing: CGFloat = Spacing.gap + Spacing.md

    /// Extra air ABOVE a heading (TextKit adds this to the previous
    /// block's after-gap); the after-gap is `headingSpacing`.
    var headingSpacingBefore: CGFloat = Spacing.gap

    /// Space between sibling list items — `Spacing.xs`.
    var listItemSpacing: CGFloat = Spacing.xs

    /// Left indent per quote nesting level — `Spacing.pageHeader`.
    var quoteIndent: CGFloat = Spacing.pageHeader

    /// Code block inner padding — `Spacing.gap`, materialized as space
    /// columns and blank padded lines inside the code text (the only way
    /// a flat `.backgroundColor` run gets breathing room).
    var codePadding: CGFloat = Spacing.gap

    /// Code block corner radius — `Radius.sm`. A plain `.backgroundColor`
    /// cannot round corners; the token is carried here for the future
    /// background-drawing layer, and tests pin it so the visual spec is
    /// not lost meanwhile.
    var codeCornerRadius: CGFloat = Radius.sm

    // MARK: List geometry

    /// Column reserved for the list marker ("1.", "•") — `Spacing.cardInner`.
    /// The text tab stop and the wrapped-line `headIndent` sit one column
    /// past the first line's indent, so marker and wrapped text align.
    var listMarkerColumn: CGFloat = Spacing.cardInner

    /// Extra indent per list `depth` level — `Spacing.gap`.
    var listDepthStep: CGFloat = Spacing.gap

    // MARK: Fonts

    func bodyFont(traits: UITraitCollection?) -> UIFont {
        body.font(traits: traits)
    }

    func headingFont(traits: UITraitCollection?) -> UIFont {
        heading.font(traits: traits)
    }

    /// Inline/block mono keeps the surrounding size — system monospaced,
    /// never a bundled face, so code optically matches its context.
    func monoFont(ofSize size: CGFloat, weight: UIFont.Weight) -> UIFont {
        .monospacedSystemFont(ofSize: size, weight: weight)
    }

    // MARK: Cache signature

    /// Signature of everything that changes the built text's metrics:
    /// Dynamic Type category (font sizes), display scale, and light/dark.
    /// Combined with the document key it forms ShowNotesStore's text-layer
    /// cache key — change any input, get a fresh build.
    static func metricSignature(traitCollection: UITraitCollection) -> String {
        // Unspecified maps to light; it resolves that way at render time.
        let appearance = traitCollection.userInterfaceStyle == .dark ? "dark" : "light"
        return [
            "cat:\(traitCollection.preferredContentSizeCategory.rawValue)",
            "scale:\(traitCollection.displayScale)",
            "ui:\(appearance)",
        ].joined(separator: "|")
    }

    /// Instance convenience over the static signature.
    func metricSignature(traitCollection: UITraitCollection) -> String {
        Self.metricSignature(traitCollection: traitCollection)
    }
}
