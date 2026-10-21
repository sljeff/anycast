import UIKit
import AnycastKit

/// Inline text attachment for a show-notes image. Layout space is derived
/// from the shared pure helper `ImageFit`: before the bytes arrive the
/// declared size (or the 16:9 fallback aspect) reserves the box, and once
/// the load lands the intrinsic size takes over — both pass through the
/// same fit-width policy, so the reserved and final rects share a rule.
///
/// Only the TextKit 2 bounds hook (the iOS 15+ `NSTextLocation`-based
/// `attachmentBounds`) is overridden; the legacy `Int`-location variant is
/// deliberately NOT overridden, and nothing here touches `layoutManager`.
/// The rendered pixels live in the inherited `NSTextAttachment.image`
/// property; the show-notes metadata therefore had to be named
/// `noteImage` to avoid colliding with it.
///
/// `nonisolated`: in this SDK NSTextAttachment's initializers and the
/// bounds hook are nonisolated, and the MainActor-by-default app target
/// would otherwise isolate the overrides into a mismatch. The app still
/// only touches instances on the main actor (loads backfill there).
nonisolated final class ShowNotesImageAttachment: NSTextAttachment {

    /// Show-notes image IR (URL, alt, declared size, order). Read by the
    /// host text view when starting loads and when opening the viewer.
    let noteImage: ShowNotesImage

    /// Size of the loaded image (points, scale 1 from the downsampling
    /// pipeline). Nil until the owning text view backfills it; the bounds
    /// use `placeholderSize` until then.
    var intrinsicSize: CGSize?

    /// Space reserved before (or without) a loaded image: the feed's
    /// declared size when it is usable, otherwise a 16:9 aspect box that
    /// `ImageFit` scales into the column.
    var placeholderSize: CGSize

    init(noteImage: ShowNotesImage) {
        self.noteImage = noteImage
        if let declared = noteImage.declaredSize,
           declared.width > 0, declared.height > 0 {
            self.placeholderSize = declared
        } else {
            // No usable declared size: hand ImageFit an invalid intrinsic
            // so its own 16:9 placeholder path reserves the full column
            // width. A valid-but-small box would instead fall under the
            // small-icon rule (intrinsic width < minimumContentWidth) and
            // reserve only its own tiny size.
            self.placeholderSize = .zero
        }
        super.init(data: nil, ofType: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    // MARK: - Bounds

    override func attachmentBounds(
        for attributes: [NSAttributedString.Key: Any],
        location: NSTextLocation,
        textContainer: NSTextContainer?,
        proposedLineFragment: CGRect,
        position: CGPoint
    ) -> CGRect {
        // The column actually available to this line is the narrower of the
        // proposed fragment and the container; before layout the container
        // can carry a sentinel width, in which case the fragment wins.
        let columnWidth = min(
            proposedLineFragment.width,
            textContainer?.size.width ?? proposedLineFragment.width
        )
        guard columnWidth > 0 else { return .zero }
        // A feed-declared small icon is a hard display cap: it must survive
        // the loaded bitmap being far larger, or a width=16 logo balloons to
        // full column width the moment the 512px source decodes.
        var available = columnWidth
        if let declared = noteImage.declaredSize, declared.width > 0, declared.width < 32 {
            available = min(available, declared.width)
        }
        // Extreme aspect ratios (divider strips, tall infographics) must not
        // own unbounded layout height: cap at 1.5× the column width; the
        // zoom viewer still shows the whole image.
        let base = intrinsicSize ?? placeholderSize
        let fitted = ImageFit.size(
            intrinsic: base,
            availableWidth: available,
            maxHeight: 1.5 * columnWidth
        )
        // `.zero` (tracking pixels / collapsed spacers) renders nothing.
        return CGRect(origin: .zero, size: fitted)
    }
}

/// Production `ShowNotesAttachmentProviding` for `ShowNotesBuilder`: every
/// image reference becomes a lazy `ShowNotesImageAttachment` that reserves
/// its declared/16:9 box and upgrades to the loaded bitmap in place.
struct ShowNotesImageAttachmentProvider: ShowNotesAttachmentProviding {

    func attachment(for image: ShowNotesImage) -> NSTextAttachment {
        ShowNotesImageAttachment(noteImage: image)
    }
}
