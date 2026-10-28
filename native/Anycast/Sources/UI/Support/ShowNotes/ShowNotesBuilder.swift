import UIKit
import AnycastKit

/// Produces the text attachment for one image reference. The production
/// factory (`ShowNotesImageAttachment`) is being delivered in parallel;
/// the builder only ever sees this protocol so the two compile
/// independently and tests can inject counting stubs.
protocol ShowNotesAttachmentProviding {
    func attachment(for image: ShowNotesImage) -> NSTextAttachment
}

/// Isolated provider (tests, previews): reserves a stable layout box
/// (declared size aspect-fitted to `maxWidth`, else a 16:9 stand-in) with
/// no image content, so documents measure without touching the image
/// pipeline. Not for production rendering — image loads and the zoom
/// viewer only work with `ShowNotesImageAttachmentFactory` output.
struct ShowNotesPlaceholderAttachmentProvider: ShowNotesAttachmentProviding {

    var maxWidth: CGFloat = 320

    func attachment(for image: ShowNotesImage) -> NSTextAttachment {
        let attachment = NSTextAttachment()
        let box: CGSize
        if let declared = image.declaredSize, declared.width > 0, declared.height > 0 {
            let scale = min(1, maxWidth / declared.width)
            box = CGSize(width: declared.width * scale, height: declared.height * scale)
        } else {
            box = CGSize(width: 160, height: 90)
        }
        attachment.bounds = CGRect(origin: .zero, size: box)
        return attachment
    }
}

/// Production attachment factory: bridges the parallel-delivered
/// `ShowNotesImageAttachment` into the builder's provider protocol. The
/// host text view backfills image loads and opens the zoom viewer by
/// casting attachments to that concrete type, so every image the builder
/// emits must come from here (the placeholder reserves a box but loads
/// nothing). This is the builder's default now that both halves live in
/// the target.
struct ShowNotesImageAttachmentFactory: ShowNotesAttachmentProviding {
    func attachment(for image: ShowNotesImage) -> NSTextAttachment {
        ShowNotesImageAttachment(noteImage: image)
    }
}

/// Compiles a normalized show-notes document (`ShowNotesDocument`, the
/// AnycastKit IR) into display text. Synchronous and allocation-only —
/// no network, no clocks, no caches; ShowNotesStore owns caching.
///
/// Structure follows the IR: one `NSMutableParagraphStyle` per block
/// (spacing, indents, tab stops), recursive inline runs (emphasis mutates
/// the font via descriptor traits; links restyle only color + `.link`).
/// Lists use explicit text markers ("1.\t" / "•\t") with an `NSTextTab`
/// stop instead of `NSTextList` — measurable, controllable geometry.
@MainActor
struct ShowNotesBuilder {

    private let attachmentProvider: ShowNotesAttachmentProviding

    init(attachmentProvider: ShowNotesAttachmentProviding = ShowNotesImageAttachmentFactory()) {
        self.attachmentProvider = attachmentProvider
    }

    func attributedString(
        from document: ShowNotesDocument,
        style: ShowNotesStyle = ShowNotesStyle(),
        traits: UITraitCollection
    ) -> NSAttributedString {
        guard !document.isEmpty, !document.blocks.isEmpty else {
            return NSAttributedString(string: "")
        }
        let composer = Composer(
            style: style,
            traits: traits,
            attachmentProvider: attachmentProvider
        )
        return composer.compose(blocks: document.blocks)
    }
}

/// Per-render state. A class so the recursive block/run walk appends into
/// one output without threading it through every parameter.
@MainActor
private final class Composer {

    private let style: ShowNotesStyle
    private let attachmentProvider: ShowNotesAttachmentProviding
    private let bodyFont: UIFont
    private let headingFont: UIFont
    private let output = NSMutableAttributedString()

    /// Continuation number for ordered list items whose IR number is nil
    /// (the "+1 顺延" rule). Any non-ordered-list block resets the sequence.
    private var implicitOrderNumber: Int?

    /// Width the widest realistic ordered marker ("99.\t") needs at the
    /// current body size — the tab column's measured floor.
    private lazy var markerColumnWidth: CGFloat = {
        let probe = NSAttributedString(string: "99.\t", attributes: [.font: bodyFont])
        return ceil(probe.size().width) + Spacing.xs
    }()

    init(style: ShowNotesStyle, traits: UITraitCollection, attachmentProvider: ShowNotesAttachmentProviding) {
        self.style = style
        self.attachmentProvider = attachmentProvider
        self.bodyFont = style.bodyFont(traits: traits)
        self.headingFont = style.headingFont(traits: traits)
    }

    // MARK: Entry

    func compose(blocks: [ShowNotesBlock]) -> NSAttributedString {
        append(blocks: blocks, indent: 0, bodyColor: nil)
        trimTrailingLineBreaks()
        return NSAttributedString(attributedString: output)
    }

    // MARK: Blocks

    private func append(blocks: [ShowNotesBlock], indent: CGFloat, bodyColor: UIColor?) {
        for block in blocks {
            switch block {
            case .heading(_, let runs):
                // One tier: every heading level renders identically, so
                // the level is intentionally ignored.
                let attributes = headingAttributes()
                let paragraph = makeParagraph(spacing: style.headingSpacing, indent: indent)
                // Above a heading the previous block already contributes its
                // own after-gap; this before-gap lifts headings clear of
                // body text (p→h = body.after + heading.before).
                paragraph.paragraphSpacingBefore = style.headingSpacingBefore
                appendBlock(paragraph: paragraph, baseAttributes: attributes) {
                    append(runs: runs, attributes: attributes)
                }

            case .paragraph(let runs):
                // An inline image flanked only by whitespace is a block
                // image in disguise — promote it to a standalone paragraph.
                if let images = standaloneImages(in: runs) {
                    appendImageParagraph(images: images, indent: indent)
                } else {
                    let attributes = bodyAttributes(color: bodyColor)
                    appendBlock(
                        paragraph: makeParagraph(spacing: style.paragraphSpacing, indent: indent),
                        baseAttributes: attributes
                    ) {
                        append(runs: runs, attributes: attributes)
                    }
                }

            case .listItem(let ordered, let number, let depth, let runs):
                appendListItem(
                    ordered: ordered,
                    number: number,
                    depth: depth,
                    runs: runs,
                    indent: indent,
                    bodyColor: bodyColor
                )

            case .quote(let inner):
                // Recurse: inner blocks indent one more level and tint body
                // text with the quote color (headings/code keep their own).
                append(blocks: inner, indent: indent + style.quoteIndent, bodyColor: style.quoteColor)

            case .codeBlock(let text):
                appendCodeBlock(text: text, indent: indent)

            case .image(let image):
                appendImageParagraph(images: [image], indent: indent)

            case .divider:
                let attributes = bodyAttributes(color: style.secondaryColor)
                appendBlock(
                    paragraph: makeParagraph(spacing: style.paragraphSpacing, indent: indent, alignment: .center),
                    baseAttributes: attributes
                ) {
                    output.append(NSAttributedString(string: "· · ·", attributes: attributes))
                }
            }
            // Only an ordered item continues the implicit numbering;
            // everything else (including unordered items and quotes)
            // breaks the sequence.
            if case .listItem(true, _, _, _) = block { continue }
            implicitOrderNumber = nil
        }
    }

    /// Appends `content`, its terminating "\n", and stamps the paragraph
    /// style over the whole paragraph — TextKit reads the style across the
    /// paragraph's full range, terminator included.
    private func appendBlock(
        paragraph: NSMutableParagraphStyle,
        baseAttributes: [NSAttributedString.Key: Any],
        content: () -> Void
    ) {
        let start = output.length
        content()
        let frozen = paragraph.copy() as! NSParagraphStyle
        var terminator = baseAttributes
        terminator[.paragraphStyle] = frozen
        output.append(NSAttributedString(string: "\n", attributes: terminator))
        output.addAttribute(
            .paragraphStyle,
            value: frozen,
            range: NSRange(location: start, length: output.length - start)
        )
    }

    /// Base paragraph style shared by every block: symmetric spacing
    /// (inter-block gap resolves as max(prev after, next before)), the
    /// carried-over 1.2 line-height multiple, and the running indent.
    private func makeParagraph(
        spacing: CGFloat,
        indent: CGFloat,
        alignment: NSTextAlignment = .natural
    ) -> NSMutableParagraphStyle {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = alignment
        paragraph.lineHeightMultiple = style.lineHeightMultiple
        // TextKit ADDS the previous paragraph's `paragraphSpacing` to the
        // next one's `paragraphSpacingBefore` — setting both symmetric
        // halves here doubled every inter-block gap. The default is
        // after-only; blocks that need air ABOVE them (headings) set their
        // own `spacingBefore` on top.
        paragraph.paragraphSpacingBefore = 0
        paragraph.paragraphSpacing = spacing
        paragraph.firstLineHeadIndent = indent
        paragraph.headIndent = indent
        return paragraph
    }

    private func bodyAttributes(color: UIColor?) -> [NSAttributedString.Key: Any] {
        [.font: bodyFont, .foregroundColor: color ?? style.body.color]
    }

    private func headingAttributes() -> [NSAttributedString.Key: Any] {
        [.font: headingFont, .foregroundColor: style.heading.color]
    }

    // MARK: List items

    private func appendListItem(
        ordered: Bool,
        number: Int?,
        depth: Int,
        runs: [ShowNotesRun],
        indent: CGFloat,
        bodyColor: UIColor?
    ) {
        let marker: String
        if ordered {
            // IR numbers win; nil continues the running sequence (+1).
            let resolved = number ?? ((implicitOrderNumber ?? 0) + 1)
            implicitOrderNumber = resolved
            marker = "\(resolved).\t"
        } else {
            marker = "•\t"
        }

        let firstLine = indent + CGFloat(depth) * style.listDepthStep
        // The fixed column is only the floor: "10.\t" at the current body
        // size (Dynamic Type grows it) must fit too, or the tab overshoots
        // its stop and wrapped lines mis-align under the marker.
        let column = firstLine + max(style.listMarkerColumn, markerColumnWidth)
        let paragraph = makeParagraph(spacing: style.listItemSpacing, indent: firstLine)
        paragraph.headIndent = column
        // The marker ends with "\t"; the stop parks the item text at the
        // column so wrapped lines (headIndent) align under it.
        paragraph.tabStops = [NSTextTab(textAlignment: .natural, location: column, options: [:])]

        let attributes = bodyAttributes(color: bodyColor)
        appendBlock(paragraph: paragraph, baseAttributes: attributes) {
            output.append(NSAttributedString(string: marker, attributes: attributes))
            append(runs: runs, attributes: attributes)
        }
    }

    // MARK: Code blocks

    private func appendCodeBlock(text: String, indent: CGFloat) {
        let mono = style.monoFont(ofSize: bodyFont.pointSize, weight: .regular)
        let spaceWidth = (" " as NSString).size(withAttributes: [.font: mono]).width
        let padCount = max(1, Int((style.codePadding / max(spaceWidth, 0.5)).rounded(.up)))
        let pad = String(repeating: " ", count: padCount)
        // Block fill ships as `.backgroundColor` runs (spec-sanctioned);
        // padding is materialized as space columns and blank padded lines
        // so the fill has breathing room without a custom drawing layer.
        // Newlines in the source are preserved verbatim.
        let lines = text.components(separatedBy: "\n").map { pad + $0 + pad }
        // U+2028 keeps every code line inside ONE paragraph — "\n" would
        // apply the block's inter-paragraph spacing between code lines.
        let padded = ([pad] + lines + [pad]).joined(separator: "\u{2028}")

        let attributes: [NSAttributedString.Key: Any] = [
            .font: mono,
            .foregroundColor: style.codeTextColor,
            .backgroundColor: style.codeBackgroundColor,
        ]
        appendBlock(
            paragraph: makeParagraph(spacing: style.paragraphSpacing, indent: indent),
            baseAttributes: attributes
        ) {
            output.append(NSAttributedString(string: padded, attributes: attributes))
        }
    }

    // MARK: Images

    private func appendImageParagraph(images: [ShowNotesImage], indent: CGFloat) {
        let attributes = bodyAttributes(color: nil)
        appendBlock(
            paragraph: makeParagraph(spacing: style.paragraphSpacing, indent: indent),
            baseAttributes: attributes
        ) {
            for image in images {
                appendAttachment(image, attributes: attributes)
            }
        }
    }

    private func appendAttachment(_ image: ShowNotesImage, attributes: [NSAttributedString.Key: Any]) {
        let attachment = attachmentProvider.attachment(for: image)
        let attachmentString = NSAttributedString(attachment: attachment)
        let range = NSRange(location: output.length, length: attachmentString.length)
        output.append(attachmentString)
        // Merge the context attributes around `.attachment` so the run
        // keeps the surrounding font/color (links, quote tint).
        output.addAttributes(attributes, range: range)
    }

    /// Paragraph runs that are ONLY images plus whitespace render as a
    /// standalone image paragraph (block-image semantics); the whitespace
    /// is dropped. Anything else returns nil and renders inline.
    private func standaloneImages(in runs: [ShowNotesRun]) -> [ShowNotesImage]? {
        var images: [ShowNotesImage] = []
        for run in runs {
            switch run {
            case .image(let image):
                images.append(image)
            case .text(let string):
                if !string.allSatisfy({ $0.isWhitespace }) { return nil }
            default:
                return nil
            }
        }
        return images.isEmpty ? nil : images
    }

    // MARK: Inline runs

    private func append(runs: [ShowNotesRun], attributes: [NSAttributedString.Key: Any]) {
        for run in runs {
            switch run {
            case .text(let string):
                output.append(NSAttributedString(string: string, attributes: attributes))

            case .lineBreak:
                // U+2028 breaks the LINE inside the same paragraph; "\n"
                // would end the paragraph and earn full inter-paragraph
                // spacing for a mere <br>.
                output.append(NSAttributedString(string: "\u{2028}", attributes: attributes))

            case .emphasis(let inner, let strong, let italic, let mono, let strike):
                var innerAttributes = attributes
                innerAttributes[.font] = derivedFont(
                    from: attributes[.font] as? UIFont ?? bodyFont,
                    strong: strong,
                    italic: italic,
                    mono: mono
                )
                if strike {
                    innerAttributes[.strikethroughStyle] = NSNumber(value: NSUnderlineStyle.single.rawValue)
                }
                append(runs: inner, attributes: innerAttributes)

            case .link(let url, let inner):
                // Color and `.link` change; the font inherits the context
                // so a link inside a heading stays heading-sized.
                var innerAttributes = attributes
                innerAttributes[.link] = url
                innerAttributes[.foregroundColor] = style.linkColor
                append(runs: inner, attributes: innerAttributes)

            case .image(let image):
                appendAttachment(image, attributes: attributes)

            case .superscript(let inner):
                let font = attributes[.font] as? UIFont ?? bodyFont
                append(runs: inner, attributes: baselineShifted(attributes, offset: 0.35 * font.pointSize))

            case .`subscript`(let inner):
                let font = attributes[.font] as? UIFont ?? bodyFont
                append(runs: inner, attributes: baselineShifted(attributes, offset: -0.35 * font.pointSize))
            }
        }
    }

    /// 0.75× the context size, shifted by `offset` (±0.35 × font size).
    private func baselineShifted(
        _ attributes: [NSAttributedString.Key: Any],
        offset: CGFloat
    ) -> [NSAttributedString.Key: Any] {
        let font = attributes[.font] as? UIFont ?? bodyFont
        var shifted = attributes
        shifted[.font] = UIFont(descriptor: font.fontDescriptor, size: font.pointSize * 0.75)
        shifted[.baselineOffset] = NSNumber(value: Double(offset))
        return shifted
    }

    /// Emphasis via font descriptor traits. Strong is the SEMIBOLD weight
    /// trait — never full bold; italic is the symbolic italic trait; mono
    /// swaps to system monospaced at the surrounding size (weight carried
    /// over best-effort, since the family change drops other traits).
    private func derivedFont(from font: UIFont, strong: Bool, italic: Bool, mono: Bool) -> UIFont {
        if mono {
            let weight: UIFont.Weight = strong ? .semibold : Self.weight(of: font)
            return style.monoFont(ofSize: font.pointSize, weight: weight)
        }
        var descriptor = font.fontDescriptor
        if strong {
            descriptor = descriptor.addingAttributes([
                .traits: [UIFontDescriptor.TraitKey.weight: UIFont.Weight.semibold]
            ])
        }
        if italic, let italicDescriptor = descriptor.withSymbolicTraits(.traitItalic) {
            descriptor = italicDescriptor
        }
        return UIFont(descriptor: descriptor, size: font.pointSize)
    }

    /// Best-effort weight read-back from the descriptor traits dictionary
    /// (bridged keys may be `TraitKey` structs or raw strings).
    private static func weight(of font: UIFont) -> UIFont.Weight {
        guard let traits = font.fontDescriptor.fontAttributes[.traits] as? [AnyHashable: Any] else {
            return .regular
        }
        let keys: [AnyHashable] = [
            UIFontDescriptor.TraitKey.weight,
            UIFontDescriptor.TraitKey.weight.rawValue,
        ]
        for key in keys {
            if let number = traits[key] as? NSNumber {
                return UIFont.Weight(rawValue: CGFloat(number.doubleValue))
            }
        }
        return .regular
    }

    // MARK: Trailing whitespace

    /// The document must not end on an empty paragraph: every block emits
    /// its own terminator, so the final one is trimmed.
    private func trimTrailingLineBreaks() {
        while output.length > 0,
              (output.string as NSString).character(at: output.length - 1) == 0x0A {
            output.deleteCharacters(in: NSRange(location: output.length - 1, length: 1))
        }
    }
}
