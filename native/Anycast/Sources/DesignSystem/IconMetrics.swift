import UIKit

/// Dynamic Type metrics for icons (Anycast 2.0, icon proposal P1).
///
/// Design point sizes are the size at the default content size. Values never
/// shrink below that design size; larger content sizes scale with the same
/// `UIFontMetrics` text style TypographyV2 uses for the neighboring text.
/// Interactive diameters also stay at least the HIG 44 pt minimum.
nonisolated enum IconMetrics {

    /// HIG minimum hit target.
    static let minimumHit: CGFloat = 44

    /// Strip / menu glyphs (proposal: 16 pt, TypographyV2 body metrics).
    static let stripPointSize: CGFloat = 16

    static func scaled(
        _ base: CGFloat,
        textStyle: UIFont.TextStyle,
        compatibleWith traits: UITraitCollection
    ) -> CGFloat {
        UIFontMetrics(forTextStyle: textStyle).scaledValue(for: base, compatibleWith: traits)
    }

    /// `base` at the default content size, larger when `textStyle` scales up.
    static func scaledUp(
        _ base: CGFloat,
        textStyle: UIFont.TextStyle,
        compatibleWith traits: UITraitCollection
    ) -> CGFloat {
        max(base, scaled(base, textStyle: textStyle, compatibleWith: traits))
    }

    static func scaledUp(
        _ base: CGFloat,
        style: TypographyV2.Style,
        compatibleWith traits: UITraitCollection
    ) -> CGFloat {
        scaledUp(base, textStyle: style.scalingTextStyle, compatibleWith: traits)
    }

    /// Hit-target diameter: the design size at the default content size,
    /// never below 44, and larger when Dynamic Type scales `textStyle` up.
    static func diameter(
        _ design: CGFloat,
        textStyle: UIFont.TextStyle,
        compatibleWith traits: UITraitCollection
    ) -> CGFloat {
        max(design, minimumHit, scaled(design, textStyle: textStyle, compatibleWith: traits))
    }

    static func diameter(
        _ design: CGFloat,
        style: TypographyV2.Style,
        compatibleWith traits: UITraitCollection
    ) -> CGFloat {
        diameter(design, textStyle: style.scalingTextStyle, compatibleWith: traits)
    }

    static func symbolConfiguration(
        pointSize: CGFloat,
        weight: UIImage.SymbolWeight,
        textStyle: UIFont.TextStyle,
        compatibleWith traits: UITraitCollection
    ) -> UIImage.SymbolConfiguration {
        UIImage.SymbolConfiguration(
            pointSize: scaledUp(pointSize, textStyle: textStyle, compatibleWith: traits),
            weight: weight
        )
    }

    static func symbolConfiguration(
        pointSize: CGFloat,
        weight: UIImage.SymbolWeight,
        style: TypographyV2.Style,
        compatibleWith traits: UITraitCollection
    ) -> UIImage.SymbolConfiguration {
        symbolConfiguration(
            pointSize: pointSize,
            weight: weight,
            textStyle: style.scalingTextStyle,
            compatibleWith: traits
        )
    }

    /// Settings disclosure. Footnote is 13 pt semibold at the default size
    /// and tracks Dynamic Type when assigned as `preferredSymbolConfiguration`.
    static func disclosureConfiguration() -> UIImage.SymbolConfiguration {
        UIImage.SymbolConfiguration(textStyle: .footnote)
            .applying(UIImage.SymbolConfiguration(weight: .semibold))
    }

    /// Settings avatar glyph. Title2 is 22 pt at the default size.
    static func avatarGlyphConfiguration() -> UIImage.SymbolConfiguration {
        UIImage.SymbolConfiguration(textStyle: .title2)
    }

    static func stripSymbolConfiguration(compatibleWith traits: UITraitCollection) -> UIImage.SymbolConfiguration {
        symbolConfiguration(
            pointSize: stripPointSize,
            weight: .medium,
            style: TypographyV2.body,
            compatibleWith: traits
        )
    }
}

/// Expands a control's hit area to at least `minimumHitSize` without
/// changing the frame Auto Layout gave it.
final class MinimumHitAreaView: UIView {

    var minimumHitSize = CGSize(width: IconMetrics.minimumHit, height: IconMetrics.minimumHit)

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        let dx = max(minimumHitSize.width - bounds.width, 0) / 2
        let dy = max(minimumHitSize.height - bounds.height, 0) / 2
        return bounds.insetBy(dx: -dx, dy: -dy).contains(point)
    }
}

extension UIImage {

    /// Symbol images take `pointSize` / `weight`. Brand imagesets ignore
    /// `SymbolConfiguration`, so they are redrawn into a `pointSize` box
    /// (template) and tinted by the host. Empty images pass through.
    func withIconMetrics(
        pointSize: CGFloat,
        weight: UIImage.SymbolWeight,
        compatibleWith traits: UITraitCollection
    ) -> UIImage {
        guard pointSize > 0 else { return self }
        if isSymbolImage {
            let configuration = UIImage.SymbolConfiguration(pointSize: pointSize, weight: weight)
            return applyingSymbolConfiguration(configuration) ?? self
        }
        guard size.width > 0, size.height > 0 else { return self }
        let format = UIGraphicsImageRendererFormat(for: traits)
        let renderer = UIGraphicsImageRenderer(
            size: CGSize(width: pointSize, height: pointSize),
            format: format
        )
        let rendered = renderer.image { _ in
            withTintColor(.black, renderingMode: .alwaysOriginal)
                .draw(in: CGRect(x: 0, y: 0, width: pointSize, height: pointSize))
        }
        return rendered.withRenderingMode(.alwaysTemplate)
    }

    /// Strip glyph: symbols stay symbols (the button's symbol configuration
    /// sizes them); brand imagesets are drawn at the scaled 16 pt box.
    func preparedStripIcon(compatibleWith traits: UITraitCollection) -> UIImage {
        if isSymbolImage || size == .zero { return self }
        let point = IconMetrics.scaledUp(
            IconMetrics.stripPointSize,
            style: TypographyV2.body,
            compatibleWith: traits
        )
        return withIconMetrics(pointSize: point, weight: .medium, compatibleWith: traits)
    }
}

extension UIButton {

    /// Icon-only controls get a Large Content Viewer whose title is the
    /// existing accessibility label (proposal P1).
    func enableIconLargeContentViewer(image: UIImage? = nil) {
        showsLargeContentViewer = true
        largeContentTitle = accessibilityLabel
        largeContentImage = image ?? configuration?.image ?? imageView?.image
        scalesLargeContentImage = true
        if interactions.contains(where: { $0 is UILargeContentViewerInteraction }) == false {
            addInteraction(UILargeContentViewerInteraction())
        }
    }
}

extension UIView {

    /// Same viewer for icon controls that are not `UIButton`s (download).
    func enableIconLargeContentViewer(title: String?, image: UIImage?) {
        showsLargeContentViewer = true
        largeContentTitle = title
        largeContentImage = image
        scalesLargeContentImage = true
        if interactions.contains(where: { $0 is UILargeContentViewerInteraction }) == false {
            addInteraction(UILargeContentViewerInteraction())
        }
    }
}
