import CoreGraphics
import Foundation

/// The IR for the show-notes rendering pipeline. `ShowNotesNormalizer` produces
/// a `ShowNotesDocument` from raw podcast show-notes HTML; downstream builders
/// and renderers consume only these types and never see HTML again.
///
/// This file is the type contract shared with the other pipeline agents: the
/// declarations below must stay shape-compatible (names, case labels, field
/// order, and associated-value labels are load-bearing).
public struct ShowNotesDocument: Equatable, Sendable {
    public var blocks: [ShowNotesBlock]
    public init(blocks: [ShowNotesBlock]) { self.blocks = blocks }
    public var isEmpty: Bool { blocks.isEmpty }
}

/// A block-level element of a show-notes document.
public enum ShowNotesBlock: Equatable, Sendable {
    /// `level` keeps the source heading level verbatim (h1–h8 → 1–8); the
    /// presentation layer maps it onto a single visual tier.
    case heading(level: Int, runs: [ShowNotesRun])
    case paragraph(runs: [ShowNotesRun])
    /// `ordered`/`number` come from the enclosing list (number is nil for
    /// unordered items); `depth` is the nesting level, capped by the
    /// normalizer; `runs` carry the item's merged inline content.
    case listItem(ordered: Bool, number: Int?, depth: Int, runs: [ShowNotesRun])
    /// Nested block content. The normalizer caps quote nesting.
    case quote(blocks: [ShowNotesBlock])
    /// Preformatted text; whitespace is significant and tabs were expanded.
    case codeBlock(text: String)
    case image(ShowNotesImage)
    case divider
}

/// Inline content inside a block.
public enum ShowNotesRun: Equatable, Sendable {
    case text(String)
    /// A styled span; combinations are expressed by the flag set so nested
    /// Nested emphasis stays nested (`strong` inside `em` is a nested
    /// run); the builder recurses. Flags carry only the direct emphasis.
    case emphasis(runs: [ShowNotesRun], strong: Bool, italic: Bool, mono: Bool, strike: Bool)
    case link(url: URL, runs: [ShowNotesRun])
    case image(ShowNotesImage)
    case lineBreak
    case superscript(runs: [ShowNotesRun])
    case `subscript`(runs: [ShowNotesRun])
}

/// An image reference. `index` is a stable document-order identifier assigned
/// by the normalizer (0-based, including images demoted to inline runs).
public struct ShowNotesImage: Equatable, Sendable {
    public var url: URL
    public var alt: String?
    /// Width/height declared in the source markup, used only as an aspect-ratio
    /// placeholder before the real size loads; nil when not declared.
    public var declaredSize: CGSize?
    public var index: Int   // document order, stable id
    public init(url: URL, alt: String?, declaredSize: CGSize?, index: Int) {
        self.url = url
        self.alt = alt
        self.declaredSize = declaredSize
        self.index = index
    }
}
