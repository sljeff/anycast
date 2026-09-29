import UIKit
import Testing
@testable import Anycast

/// Font registration proof: every UIAppFonts entry resolves by its
/// PostScript name, the requested weights are real (the static instances
/// carry the correct OS/2 weight class), and the SF Symbol mapping table
/// resolves on this OS.
@MainActor
struct TypographyTests {

    @Test("Bundled families resolve with the requested weights")
    func familiesResolve() {
        // name → (expects bold traits, expected point size at default)
        let expectations: [(name: String, bold: Bool)] = [
            ("Comfortaa-Regular", false),
            ("Comfortaa-Bold", true),
            ("NotoSans-Regular", false),
            ("NotoSans-Bold", true),
            ("Inter-Regular", false),
            ("RoundedMplus1c-Regular", false),
            ("Roboto-Regular", false),
            ("RobotoMono-Regular", false),
        ]
        for expectation in expectations {
            let font = UIFont(name: expectation.name, size: 16)
            #expect(font != nil, "\(expectation.name) did not register — check UIAppFonts")
            guard let font else { continue }
            let isBold = font.fontDescriptor.symbolicTraits.contains(.traitBold)
            #expect(isBold == expectation.bold, "\(expectation.name) bold traits = \(isBold)")

            // Weight verification: variable fonts that silently register at
            // their default instance would report 400 for the bold cut.
            let traits = font.fontDescriptor.object(forKey: .traits) as? [UIFontDescriptor.TraitKey: Any]
            let weightRaw = traits?[.weight] as? CGFloat ?? UIFont.Weight.regular.rawValue
            #expect(
                expectation.bold ? weightRaw >= UIFont.Weight.bold.rawValue : weightRaw <= UIFont.Weight.regular.rawValue,
                "\(expectation.name) weight resolved as \(weightRaw)"
            )
        }
    }

    @Test("Semantic styles resolve and honor Dynamic Type")
    func semanticStyles() {
        let styles: [Typography.Style] = [
            .mainTitle, .secondaryTitle, .mainText, .cardTitleBold, .defaultTitle,
            .cardTextLight, .defaultText, .cardDescription, .lyricMain, .lyricActive,
            .lyricTranslation, .tabLabel, .loginSmall, .htmlError, .htmlBody,
        ]
        for style in styles {
            let base = style.font()
            #expect(base.pointSize > 0)
            if let scaling = style.scalingTextStyle {
                // Scaling grows the font under an accessibility size...
                let axTraits = UITraitCollection(preferredContentSizeCategory: .accessibilityExtraLarge)
                let axFont = style.font(traits: axTraits)
                #expect(
                    axFont.pointSize > base.pointSize,
                    "\(String(describing: scaling)) scaled \(base.pointSize) → \(axFont.pointSize)"
                )
                // ...and leaves default-size traits untouched.
                let defaultTraits = UITraitCollection(preferredContentSizeCategory: .large)
                #expect(abs(style.font(traits: defaultTraits).pointSize - base.pointSize) < 0.6)
            }
        }
    }

    @Test("mainTitle tracking is 4.4pt at 44pt comfortaa bold")
    func mainTitleAttributes() {
        let attributes = Typography.mainTitle.attributes()
        #expect((attributes[.kern] as? CGFloat) == 4.4)
        let font = attributes[.font] as? UIFont
        #expect(font?.pointSize == 44)
        #expect(font?.fontName == "Comfortaa-Bold")
    }

    @Test("All SF Symbol mappings resolve")
    func symbolMappingsResolve() {
        for name in AppIcons.symbolNames {
            let image = UIImage(systemName: name)
            #expect(image != nil, "SF Symbol \(name) did not resolve")
        }
    }

    @Test("Brand SVG imagesets are present as template images")
    func brandAssetsResolve() {
        for name in ["BrandaiChat", "BrandtablerTopology", "BrandnewDoc", "BrandaiTranscript"] {
            let image = UIImage(named: name)
            #expect(image != nil, "\(name) missing from asset catalog")
            #expect(image?.renderingMode == .alwaysTemplate || image?.renderingMode == .automatic)
        }
    }

    @Test("Color tokens resolve with exact dark values")
    func colorTokensResolve() {
        func assertEqual(_ color: UIColor, red: CGFloat, green: CGFloat, blue: CGFloat, _ label: String) {
            var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            color.getRed(&r, green: &g, blue: &b, alpha: &a)
            #expect(abs(r - red) < 0.004 && abs(g - green) < 0.004 && abs(b - blue) < 0.004, "\(label)")
        }
        assertEqual(Theme.primaryBackgroundDark, red: 0x11 / 255, green: 0x13 / 255, blue: 0x16 / 255, "primaryBackgroundDark")
        assertEqual(Theme.cardBackground, red: 0x23 / 255, green: 0x28 / 255, blue: 0x30 / 255, "cardBackground")
        assertEqual(Theme.tabSelectedGreen, red: 0x6E / 255, green: 0xE7 / 255, blue: 0xB7 / 255, "tabSelectedGreen")
        assertEqual(Theme.brandGreen, red: 0x10 / 255, green: 0xB9 / 255, blue: 0x81 / 255, "brandGreen")
        assertEqual(Theme.secondaryLabelGray, red: 0x6B / 255, green: 0x72 / 255, blue: 0x80 / 255, "secondaryLabelGray")
        assertEqual(Theme.hintGray, red: 0x4B / 255, green: 0x55 / 255, blue: 0x63 / 255, "hintGray")
        assertEqual(Theme.loginCardBackground, red: 0x1E / 255, green: 0x1E / 255, blue: 0x1E / 255, "loginCardBackground")
        assertEqual(Theme.primary, red: 0x34 / 255, green: 0xD3 / 255, blue: 0x99 / 255, "primary")
    }

    @Test("Every named color token resolves from the asset catalog")
    func allNamedColorTokensResolve() {
        // Touching each accessor exercises its force-unwrapped
        // `UIColor(named:)!`; a missing colorset crashes here instead of at
        // first use in the UI.
        let tokens: [String: UIColor?] = [
            "primary": Theme.primary,
            "primaryLightPlus1": Theme.primaryLightPlus1,
            "primaryLightMax": Theme.primaryLightMax,
            "primaryDark": Theme.primaryDark,
            "primaryBackground": Theme.primaryBackground,
            "primaryBackgroundDark": Theme.primaryBackgroundDark,
            "accent": Theme.accent,
            "secondaryText": Theme.secondaryText,
            "cardBackground": Theme.cardBackground,
            "tabSelectedGreen": Theme.tabSelectedGreen,
            "brandGreen": Theme.brandGreen,
            "secondaryLabelGray": Theme.secondaryLabelGray,
            "hintGray": Theme.hintGray,
            "loginCardBackground": Theme.loginCardBackground,
            "cardOutline": Theme.cardOutline,
            "appBarGradientStart": Theme.appBarGradientStart,
            "appBarGradientEnd": Theme.appBarGradientEnd,
        ]
        for (name, token) in tokens {
            #expect(token != nil, "\(name) did not resolve — check the asset catalog")
        }
    }
}
