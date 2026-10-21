import UIKit
import Testing
import AnycastKit
@testable import Anycast

/// ShowNotesBuilder — document → NSAttributedString compilation: exact
/// text, single-tier typography, list geometry via tab stops, quote
/// nesting, link/attachment/super-subscript attributes, and the no-empty-
/// trailing-paragraph rule. Fixed trait collection so font metrics are
/// deterministic (`.large` is the 1.0 Dynamic Type baseline).
@MainActor
struct ShowNotesBuilderTests {

    private let traits = UITraitCollection(mutations: {
        $0.preferredContentSizeCategory = .large
        $0.displayScale = 3.0
        $0.userInterfaceStyle = .dark
    })

    private let linkURL = URL(string: "https://example.com/docs")!

    private let style = ShowNotesStyle()

    // MARK: Fixtures

    private func fixtureDocument() -> ShowNotesDocument {
        ShowNotesDocument(blocks: [
            .heading(level: 1, runs: [.text("Title "), .link(url: linkURL, runs: [.text("link")])]),
            .paragraph(runs: [
                .text("Body "),
                .emphasis(runs: [.text("bold")], strong: true, italic: false, mono: false, strike: false),
                .text(" and "),
                .emphasis(runs: [.text("code")], strong: false, italic: false, mono: true, strike: false),
                .text("."),
            ]),
            .listItem(ordered: true, number: 2, depth: 0, runs: [.text("Second")]),
            .listItem(ordered: true, number: nil, depth: 0, runs: [.text("Third")]),
            .listItem(ordered: false, number: nil, depth: 1, runs: [.text("Nested")]),
            .quote(blocks: [.paragraph(runs: [.text("Quoted")])]),
            .codeBlock(text: "let x = 1"),
            .divider,
            .paragraph(runs: [.text("End")]),
        ])
    }

    private func build(_ document: ShowNotesDocument, provider: ShowNotesAttachmentProviding = ShowNotesPlaceholderAttachmentProvider()) -> NSAttributedString {
        ShowNotesBuilder(attachmentProvider: provider).attributedString(
            from: document,
            style: style,
            traits: traits
        )
    }

    private func range(of target: String, in text: NSAttributedString) -> NSRange {
        (text.string as NSString).range(of: target)
    }

    private func font(at target: String, in text: NSAttributedString) -> UIFont? {
        let target = range(of: target, in: text)
        guard target.location != NSNotFound else { return nil }
        return text.attribute(.font, at: target.location, effectiveRange: nil) as? UIFont
    }

    private func paragraphStyle(at target: String, in text: NSAttributedString) -> NSParagraphStyle? {
        let target = range(of: target, in: text)
        guard target.location != NSNotFound else { return nil }
        return text.attribute(.paragraphStyle, at: target.location, effectiveRange: nil) as? NSParagraphStyle
    }

    /// Mirrors the descriptor weight read-back used by the builder's mono
    /// branch; tolerant of the two bridging shapes of the traits key.
    private func descriptorWeight(of font: UIFont) -> UIFont.Weight? {
        guard let traits = font.fontDescriptor.fontAttributes[.traits] as? [AnyHashable: Any] else {
            return nil
        }
        for key: AnyHashable in [UIFontDescriptor.TraitKey.weight, UIFontDescriptor.TraitKey.weight.rawValue] {
            if let number = traits[key] as? NSNumber {
                return UIFont.Weight(rawValue: CGFloat(number.doubleValue))
            }
        }
        return nil
    }

    // MARK: Text

    @Test("Exact compiled text: markers, numbering continuation, divider, no trailing paragraph")
    func exactText() {
        let result = build(fixtureDocument())
        let text = result.string

        #expect(text.hasPrefix("Title link\nBody bold and code.\n2.\tSecond\n3.\tThird\n•\tNested\nQuoted\n"))
        // The nil number continues the running sequence: 2 → 3.
        #expect(text.contains("3.\tThird"))
        // Code block keeps its lines, padded with spaces inside the fill.
        let codeLine = text.components(separatedBy: "\n").first { $0.contains("let x = 1") }
        #expect(codeLine != nil)
        #expect(codeLine?.hasPrefix(" ") == true)
        #expect(codeLine?.hasSuffix(" ") == true)
        #expect(text.contains("· · ·"))
        #expect(text.hasSuffix("· · ·\nEnd"))
        #expect(!text.hasSuffix("\n"))
    }

    @Test("Empty documents compile to an empty string")
    func emptyDocument() {
        let result = build(ShowNotesDocument(blocks: []))
        #expect(result.length == 0)
    }

    // MARK: Typography

    @Test("Typography: one body, one heading tier, mono matches body size, strong is semibold")
    func typography() {
        let document = ShowNotesDocument(blocks: [
            .heading(level: 1, runs: [.text("H one")]),
            .heading(level: 4, runs: [.text("H four")]),
            .paragraph(runs: [
                .text("plain "),
                .emphasis(runs: [.text("bold")], strong: true, italic: false, mono: false, strike: false),
                .emphasis(runs: [.text("mono1")], strong: false, italic: false, mono: true, strike: false),
                .emphasis(runs: [.text("ital")], strong: false, italic: true, mono: false, strike: false),
                .emphasis(runs: [.text("gone")], strong: false, italic: false, mono: false, strike: true),
            ]),
        ])
        let result = build(document)
        let body = style.bodyFont(traits: traits)
        let heading = style.headingFont(traits: traits)

        // The style pins the spec tiers.
        #expect(style.body.size == TypographyV2.bodyLarge.size)
        #expect(style.heading.size == TypographyV2.headlineMedium.size)
        #expect(style.heading.weight == .semibold)

        // Every heading level renders the identical tier, distinct from body.
        let h1 = font(at: "H one", in: result)
        let h4 = font(at: "H four", in: result)
        #expect(h1?.pointSize == heading.pointSize)
        #expect(h4?.pointSize == heading.pointSize)
        #expect(h1?.fontName == h4?.fontName)
        #expect(h1?.pointSize != body.pointSize)

        // Body size and the mono run (same size, monospaced face).
        #expect(font(at: "plain", in: result)?.pointSize == body.pointSize)
        let mono = font(at: "mono1", in: result)
        #expect(mono?.fontDescriptor.symbolicTraits.contains(.traitMonoSpace) == true)
        #expect(mono?.pointSize == body.pointSize)

        // Strong emphasis applies a weight change at the same size — never
        // the untouched body font. The exact semibold read-back is asserted
        // when the active theme face reports descriptor weights at all
        // (bundled faces without a semibold instance snap and report none).
        let bold = font(at: "bold", in: result)
        let plain = font(at: "plain", in: result)
        #expect(bold != nil && plain != nil)
        #expect(bold?.pointSize == plain?.pointSize)
        #expect(bold?.fontName != plain?.fontName, "strong emphasis did not change the face")
        if let boldWeight = bold.flatMap(descriptorWeight(of:)),
           let plainWeight = plain.flatMap(descriptorWeight(of:)) {
            #expect(abs(boldWeight.rawValue - UIFont.Weight.semibold.rawValue) < 0.06)
            #expect(abs(boldWeight.rawValue - UIFont.Weight.bold.rawValue) >= 0.06)
            #expect(boldWeight.rawValue > plainWeight.rawValue)
        }

        // Italic via symbolic traits; strike via the attribute.
        #expect(font(at: "ital", in: result)?.fontDescriptor.symbolicTraits.contains(.traitItalic) == true)
        let strikeRange = range(of: "gone", in: result)
        #expect(result.attribute(.strikethroughStyle, at: strikeRange.location, effectiveRange: nil) != nil)
    }

    @Test("Links keep the context font and gain the primary tint")
    func linkAttributes() {
        let result = build(fixtureDocument())
        let heading = style.headingFont(traits: traits)
        let body = style.bodyFont(traits: traits)

        // Link inside the heading: heading font, primary color, .link URL.
        let headingLink = range(of: "link", in: result)
        let headingLinkFont = result.attribute(.font, at: headingLink.location, effectiveRange: nil) as? UIFont
        #expect(headingLinkFont?.pointSize == heading.pointSize)
        #expect(headingLinkFont?.fontName == font(at: "Title", in: result)?.fontName)
        #expect(result.attribute(.link, at: headingLink.location, effectiveRange: nil) as? URL == linkURL)
        #expect((result.attribute(.foregroundColor, at: headingLink.location, effectiveRange: nil) as? UIColor) === style.linkColor)

        // A body-level link keeps the body size.
        let document = ShowNotesDocument(blocks: [
            .paragraph(runs: [.link(url: linkURL, runs: [.text("bodylink")])]),
        ])
        let bodyResult = build(document)
        #expect(font(at: "bodylink", in: bodyResult)?.pointSize == body.pointSize)
        let bodyLink = range(of: "bodylink", in: bodyResult)
        #expect(bodyResult.attribute(.link, at: bodyLink.location, effectiveRange: nil) as? URL == linkURL)
    }

    // MARK: Colors

    @Test("Colors: quote body tint, code fill, divider secondary")
    func colors() {
        let result = build(fixtureDocument())

        let quoted = range(of: "Quoted", in: result)
        #expect((result.attribute(.foregroundColor, at: quoted.location, effectiveRange: nil) as? UIColor) === style.quoteColor)

        let code = range(of: "let x = 1", in: result)
        #expect((result.attribute(.backgroundColor, at: code.location, effectiveRange: nil) as? UIColor) === style.codeBackgroundColor)
        #expect(font(at: "let x = 1", in: result)?.fontDescriptor.symbolicTraits.contains(.traitMonoSpace) == true)

        let divider = range(of: "· · ·", in: result)
        #expect((result.attribute(.foregroundColor, at: divider.location, effectiveRange: nil) as? UIColor) === style.secondaryColor)
        #expect(paragraphStyle(at: "· · ·", in: result)?.alignment == .center)
    }

    // MARK: Paragraph geometry

    @Test("List geometry: marker tab stop, headIndent, depth step, item spacing")
    func listGeometry() {
        let result = build(fixtureDocument())

        // The marker column is max(fixed floor, measured "99.\t" width)
        // at the body size — assert against the same measurement.
        let markerProbe = NSAttributedString(string: "99.\t", attributes: [.font: style.bodyFont(traits: nil)])
        let measured = ceil(markerProbe.size().width) + Spacing.xs
        let column = max(style.listMarkerColumn, measured)

        let item = paragraphStyle(at: "Second", in: result)
        #expect(item?.firstLineHeadIndent == 0)
        #expect(item?.headIndent == column)
        #expect(item?.tabStops.count == 1)
        #expect(item?.tabStops.first?.location == column)
        #expect(item?.paragraphSpacing == Spacing.xs)

        let nested = paragraphStyle(at: "Nested", in: result)
        #expect(nested?.firstLineHeadIndent == style.listDepthStep)
        #expect(nested?.headIndent == style.listDepthStep + column)
        #expect(nested?.tabStops.first?.location == style.listDepthStep + column)
    }

    @Test("Block spacing and quote nesting indents")
    func blockSpacingAndQuotes() {
        let document = ShowNotesDocument(blocks: [
            .paragraph(runs: [.text("Intro")]),
            .heading(level: 2, runs: [.text("Head")]),
            .quote(blocks: [
                .paragraph(runs: [.text("L1")]),
                .quote(blocks: [.paragraph(runs: [.text("L2")])]),
            ]),
        ])
        let result = build(document)

        #expect(paragraphStyle(at: "Intro", in: result)?.paragraphSpacing == Spacing.md)

        let heading = paragraphStyle(at: "Head", in: result)
        #expect(heading?.paragraphSpacingBefore == Spacing.gap)
        #expect(heading?.paragraphSpacing == Spacing.gap + Spacing.md)

        // One quoteIndent per nesting level.
        #expect(paragraphStyle(at: "L1", in: result)?.headIndent == Spacing.pageHeader)
        #expect(paragraphStyle(at: "L2", in: result)?.headIndent == 2 * Spacing.pageHeader)

        // Line-height multiple carries over from the v1 pipeline.
        #expect(abs((paragraphStyle(at: "Intro", in: result)?.lineHeightMultiple ?? 0) - 1.2) < 0.001)
    }

    // MARK: Superscript / subscript

    @Test("Superscript/subscript: 0.75x size and ±0.35x baseline offset")
    func baselineShifts() {
        let document = ShowNotesDocument(blocks: [
            .paragraph(runs: [
                .text("x"),
                .superscript(runs: [.text("2")]),
                .`subscript`(runs: [.text("3")]),
            ]),
        ])
        let result = build(document)
        let body = style.bodyFont(traits: traits)

        let sup = range(of: "2", in: result)
        let supFont = result.attribute(.font, at: sup.location, effectiveRange: nil) as? UIFont
        let supOffset = result.attribute(.baselineOffset, at: sup.location, effectiveRange: nil) as? NSNumber
        #expect(abs((supFont?.pointSize ?? 0) - body.pointSize * 0.75) < 0.01)
        #expect(supOffset != nil)
        if let supOffset {
            #expect(abs(CGFloat(supOffset.doubleValue) - 0.35 * body.pointSize) < 0.01)
        }

        let sub = range(of: "3", in: result)
        let subOffset = result.attribute(.baselineOffset, at: sub.location, effectiveRange: nil) as? NSNumber
        #expect(subOffset != nil, "subscript run lost its baselineOffset")
        if let subOffset {
            #expect(abs(CGFloat(subOffset.doubleValue) + 0.35 * body.pointSize) < 0.01)
        }
    }

    // MARK: Attachments

    private final class CountingProvider: ShowNotesAttachmentProviding {
        var images: [ShowNotesImage] = []
        func attachment(for image: ShowNotesImage) -> NSTextAttachment {
            images.append(image)
            let attachment = NSTextAttachment()
            attachment.bounds = CGRect(x: 0, y: 0, width: 10, height: 10)
            return attachment
        }
    }

    @Test("Attachments render in document order through the injected provider")
    func attachments() {
        let provider = CountingProvider()
        let first = ShowNotesImage(
            url: URL(string: "https://img.example/1")!,
            alt: nil,
            declaredSize: CGSize(width: 100, height: 50),
            index: 0
        )
        let second = ShowNotesImage(
            url: URL(string: "https://img.example/2")!,
            alt: nil,
            declaredSize: nil,
            index: 1
        )
        let document = ShowNotesDocument(blocks: [
            .image(first),
            .paragraph(runs: [.text(" "), .image(second), .text(" ")]),
        ])
        let result = build(document, provider: provider)

        // Provider saw the images in document order.
        #expect(provider.images.map(\.url) == [first.url, second.url])

        var attachments: [NSTextAttachment] = []
        result.enumerateAttribute(.attachment, in: NSRange(location: 0, length: result.length)) { value, _, _ in
            if let attachment = value as? NSTextAttachment { attachments.append(attachment) }
        }
        #expect(attachments.count == 2)

        // The whitespace-flanked inline image becomes a standalone
        // paragraph: exactly one object character per image, nothing else.
        #expect(result.string == "\u{FFFC}\n\u{FFFC}")
        #expect(!result.string.hasSuffix("\n"))
    }
}
