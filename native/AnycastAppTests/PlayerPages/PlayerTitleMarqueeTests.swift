import UIKit
import Testing
import AnycastKit
@testable import Anycast

/// K33: the player title marquee triggers on MEASURED width overflow
/// (MarqueeLabelFactory.titleNeedsMarquee), never on character counts —
/// plus the channel-name palette fallback rule (PlayerPaletteRules).
struct PlayerTitleMarqueeTests {

    private let font = UIFont.systemFont(ofSize: 24, weight: .semibold)

    @Test("Short titles do not scroll")
    func shortTitlesDoNotScroll() {
        #expect(!MarqueeLabelFactory.titleNeedsMarquee("Hi", font: font, availableWidth: 300))
        #expect(!MarqueeLabelFactory.titleNeedsMarquee("Episode 12", font: font, availableWidth: 200))
    }

    @Test("Titles whose measured width exceeds the space do scroll")
    func longTitlesScroll() {
        let longTitle = String(repeating: "A very long episode title ", count: 3)
        #expect(MarqueeLabelFactory.titleNeedsMarquee(longTitle, font: font, availableWidth: 200))
        // Even FEW characters when they are wide (the Dart char-count
        // heuristic missed exactly this case).
        #expect(MarqueeLabelFactory.titleNeedsMarquee("WWWWWWWWWW", font: font, availableWidth: 60))
    }

    @Test("Mixed CJK/latin measures the real glyphs, not character counts")
    func measuredNotCounted() {
        // 10 CJK glyphs at 24 pt are wider than 10 'i's; both must be
        // judged by measurement alone.
        let cjk = "界面快讯每日播客早报"
        let latin = "iiiiiiiii"
        let width = CGFloat(180)
        #expect(MarqueeLabelFactory.titleNeedsMarquee(cjk, font: font, availableWidth: width)
                != MarqueeLabelFactory.titleNeedsMarquee(latin, font: font, availableWidth: width))
        #expect(MarqueeLabelFactory.titleNeedsMarquee(cjk, font: font, availableWidth: 200))
        #expect(!MarqueeLabelFactory.titleNeedsMarquee(latin, font: font, availableWidth: 200))
    }

    @Test("Exact fit is not overflow (ceil boundary)")
    func exactFitDoesNotScroll() {
        let size = ("Exact" as NSString).size(withAttributes: [.font: font])
        let width = ceil(size.width)
        #expect(!MarqueeLabelFactory.titleNeedsMarquee("Exact", font: font, availableWidth: width))
        #expect(MarqueeLabelFactory.titleNeedsMarquee("Exact", font: font, availableWidth: width - 1))
    }

    @Test("Channel-name color folds dark dominants to the fallback green")
    func channelNamePaletteRule() {
        func rgbString(_ color: UIColor) -> String {
            var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
            color.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
            return String(format: "%02X%02X%02X", Int(red * 255), Int(green * 255), Int(blue * 255))
        }

        // Too dark (luminance < 0.2) → 0x10B981 (TextSafeColor.fallback).
        #expect(rgbString(PlayerPaletteRules.channelNameColor(dominantRGB: 0x11_13_16)) == "10B981")
        #expect(rgbString(PlayerPaletteRules.channelNameColor(dominantRGB: 0)) == "10B981")
        // A bright dominant passes through unchanged.
        #expect(rgbString(PlayerPaletteRules.channelNameColor(dominantRGB: 0xD8_C8_AE)) == "D8C8AE")
        #expect(rgbString(PlayerPaletteRules.channelNameColor(dominantRGB: 0x63_C1_74)) == "63C174")
    }
}
