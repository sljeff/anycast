import UIKit
import MarqueeLabel

/// The marquee preset for history rows (03 §4): ALWAYS scroll (no width
/// test), start after ~1 s, blank gap 72, leading padding 12. (The player
/// title no longer scrolls — the Anycast 2.0 player wraps it to two lines.)
enum MarqueeLabelFactory {

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
