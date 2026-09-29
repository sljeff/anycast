import UIKit
import MarqueeLabel

/// Presets for the two marquee usage sites (03 §4), kept apart on purpose —
/// their trigger conditions differ and must not cross-pollute (08 §11.6):
///
/// - player title: scrolls only when the title's MEASURED width exceeds the
///   available width (K33 micro-enhancement over the Dart character-count
///   estimate), pause 1 s after each round, blank gap 40;
/// - history rows: ALWAYS scroll (no width test), start after ~1 s,
///   blank gap 72, leading padding 12.
enum MarqueeLabelFactory {

    /// Player title marquee (player.dart:351-356).
    static func makePlayerTitle(font: UIFont, textColor: UIColor) -> MarqueeLabel {
        make(
            font: font,
            textColor: textColor,
            leadingBuffer: 40,
            trailingBuffer: 40,
            animationDelay: 1.0,
            fadeLength: 0
        )
    }

    /// History row marquee (playlists.dart:342-355).
    static func makeHistoryTitle(font: UIFont, textColor: UIColor) -> MarqueeLabel {
        make(
            font: font,
            textColor: textColor,
            leadingBuffer: 12,
            trailingBuffer: 72,
            animationDelay: 1.0,
            fadeLength: 0
        )
    }

    /// Width gate for the player title (the Dart `title.length * 24 > width`
    /// heuristic replaced by an actual measurement — K33).
    static func titleNeedsMarquee(_ title: String, font: UIFont, availableWidth: CGFloat) -> Bool {
        let size = (title as NSString).size(
            withAttributes: [.font: font]
        )
        return ceil(size.width) > availableWidth
    }

    private static func make(
        font: UIFont,
        textColor: UIColor,
        leadingBuffer: CGFloat,
        trailingBuffer: CGFloat,
        animationDelay: Double,
        fadeLength: CGFloat
    ) -> MarqueeLabel {
        let label = MarqueeLabel()
        label.font = font
        label.textColor = textColor
        label.type = .continuous
        label.speed = .duration(12)
        label.leadingBuffer = leadingBuffer
        label.trailingBuffer = trailingBuffer
        label.animationDelay = animationDelay
        label.fadeLength = fadeLength
        label.numberOfLines = 1
        return label
    }
}
