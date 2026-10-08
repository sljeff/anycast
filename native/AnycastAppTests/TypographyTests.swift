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
        // v2 (09 §2): the app still force-installs dark, so the bridged v1
        // accessor names are asserted against their DARK appearance values,
        // resolved explicitly for determinism.
        let dark = UITraitCollection(userInterfaceStyle: .dark)
        func assertEqual(_ color: UIColor, red: CGFloat, green: CGFloat, blue: CGFloat, _ label: String) {
            var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            color.resolvedColor(with: dark).getRed(&r, green: &g, blue: &b, alpha: &a)
            #expect(abs(r - red) < 0.004 && abs(g - green) < 0.004 && abs(b - blue) < 0.004, "\(label)")
        }
        assertEqual(Theme.primaryBackgroundDark, red: 0x19 / 255, green: 0x19 / 255, blue: 0x18 / 255, "primaryBackgroundDark") // Background
        assertEqual(Theme.cardBackground, red: 0x11 / 255, green: 0x11 / 255, blue: 0x10 / 255, "cardBackground")             // Surface
        assertEqual(Theme.tabSelectedGreen, red: 0xCB / 255, green: 0xB9 / 255, blue: 0x9F / 255, "tabSelectedGreen")         // Primary
        assertEqual(Theme.brandGreen, red: 0x63 / 255, green: 0xC1 / 255, blue: 0x74 / 255, "brandGreen")                     // Grass9
        assertEqual(Theme.secondaryLabelGray, red: 0xD2 / 255, green: 0xD0 / 255, blue: 0xCA / 255, "secondaryLabelGray")     // OnSurfaceVariant
        assertEqual(Theme.hintGray, red: 0xB5 / 255, green: 0xB3 / 255, blue: 0xAD / 255, "hintGray")                         // SandDark9
        assertEqual(Theme.loginCardBackground, red: 0x22 / 255, green: 0x22 / 255, blue: 0x21 / 255, "loginCardBackground")   // SurfaceContainer
        assertEqual(Theme.primary, red: 0xCB / 255, green: 0xB9 / 255, blue: 0x9F / 255, "primary")                           // Primary
    }

    @Test("v2 semantic tokens resolve both appearances exactly")
    func v2SemanticTokensResolveDualAppearance() {
        let light = UITraitCollection(userInterfaceStyle: .light)
        let dark = UITraitCollection(userInterfaceStyle: .dark)
        func assertEqual(_ color: UIColor, light lr: (CGFloat, CGFloat, CGFloat), dark dr: (CGFloat, CGFloat, CGFloat), _ label: String) {
            var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            color.resolvedColor(with: light).getRed(&r, green: &g, blue: &b, alpha: &a)
            #expect(abs(r - lr.0) < 0.004 && abs(g - lr.1) < 0.004 && abs(b - lr.2) < 0.004, "\(label) light")
            color.resolvedColor(with: dark).getRed(&r, green: &g, blue: &b, alpha: &a)
            #expect(abs(r - dr.0) < 0.004 && abs(g - dr.1) < 0.004 && abs(b - dr.2) < 0.004, "\(label) dark")
        }
        func f(_ hex: Int) -> (CGFloat, CGFloat, CGFloat) {
            (CGFloat((hex >> 16) & 0xFF) / 255, CGFloat((hex >> 8) & 0xFF) / 255, CGFloat(hex & 0xFF) / 255)
        }
        assertEqual(Theme.background, light: f(0xF9F9F8), dark: f(0x191918), "background")
        assertEqual(Theme.surface, light: f(0xFDFDFC), dark: f(0x111110), "surface")
        assertEqual(Theme.surfaceContainer, light: f(0xF1F0EF), dark: f(0x222221), "surfaceContainer")
        assertEqual(Theme.onSurface, light: f(0x21201C), dark: f(0xEEEEEC), "onSurface")
        assertEqual(Theme.onSurfaceVariant, light: f(0x63635E), dark: f(0xD2D0CA), "onSurfaceVariant")
        assertEqual(Theme.primary, light: f(0x978365), dark: f(0xCBB99F), "primary")
        assertEqual(Theme.outline, light: f(0xDAD9D6), dark: f(0x3B3A37), "outline")
        assertEqual(Theme.tertiary, light: f(0xEF5F00), dark: f(0xFF8B3E), "tertiary")
        assertEqual(Theme.error, light: f(0xBA1A1A), dark: f(0xFF8B8B), "error")
        assertEqual(AnycastColor.grass9, light: f(0x46A758), dark: f(0x63C174), "grass9")
        assertEqual(Theme.playerWarm, light: f(0x867D75), dark: f(0x867D75), "playerWarm (fixed)")
    }

    @Test("v2 type styles scale with Dynamic Type")
    func v2StylesScale() {
        for style in TypographyV2.allStyles {
            let base = style.font()
            #expect(base.pointSize > 0)
            let axTraits = UITraitCollection(preferredContentSizeCategory: .accessibilityExtraLarge)
            let axFont = style.font(traits: axTraits)
            #expect(axFont.pointSize > base.pointSize, "v2 style \(base.pointSize) did not scale")
            let attributes = style.attributes()
            #expect(attributes[.font] is UIFont)
            #expect(attributes[.paragraphStyle] is NSParagraphStyle)
        }
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
