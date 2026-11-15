import UIKit
import AnycastKit

/// Host text view for show-notes documents with inline image attachments
/// (the rich pipeline's replacement for the plain
/// `HTMLContentRenderer.makeTextView` factory). Non-scrolling — the owning
/// page owns the scroll — and non-editable but selectable.
///
/// Interaction routing uses the iOS 17+ text-item primary action API: image
/// attachments open through `presentImage`, links go through `onLinkTap`
/// (falling back to the system default action when no handler is injected).
/// The deprecated `shouldInteractWith` family is intentionally NOT
/// implemented, no tap gesture recognizers are installed, and
/// `layoutManager` is never touched so the view stays on TextKit 2.
///
/// Inline images load lazily: each attachment reserves its placeholder box
/// first, and a completed load rewrites only the attachment's attributes in
/// place (length-preserving `editedAttributes`), so character positions
/// never move and no error text is ever spliced into the document.
@MainActor
final class ShowNotesTextView: UITextView, UITextViewDelegate {

    /// Called with every tapped link. Production injects the app's link
    /// presenter; nil keeps the system default action.
    var onLinkTap: ((URL) -> Void)?

    /// Called when the user taps an inline image attachment. The second
    /// argument is the loaded image when available (the viewer's seed /
    /// transition thumbnail), nil while still on the placeholder.
    var presentImage: ((ShowNotesImage, UIImage?) -> Void)?

    /// Preferred content size category changed — the owning page must
    /// rebuild the document (font metrics feed the builder).
    var onMetricsChange: (() -> Void)?

    /// A load landed and the attachment's box (placeholder aspect →
    /// intrinsic aspect) may have changed height. v1 does no scroll
    /// compensation; this hook exists for a later pass (the argument is
    /// the attachment's character location).
    var onAttachmentHeightChanged: ((Int) -> Void)?

    /// Monotonic per-view document generation. A late completion from a
    /// document that was already replaced must not backfill the new one.
    private var documentGeneration = 0

    /// Loads started for the current document; all cancelled when the next
    /// document arrives (reuse, episode switch).
    private var activeTokens: [ShowNotesImageLoadToken] = []

    override init(frame: CGRect, textContainer: NSTextContainer?) {
        super.init(frame: frame, textContainer: textContainer)
        delegate = self
        backgroundColor = .clear
        isEditable = false
        isSelectable = true
        isScrollEnabled = false
        textContainerInset = .zero
        // Must target the receiver's container — the init PARAMETER is nil
        // for the plain inits (UIKit creates the container in super), and
        // setting it there is a silent no-op (5 pt left/right regression).
        self.textContainer.lineFragmentPadding = 0
        linkTextAttributes = [.foregroundColor: Theme.primary]
        // Preferred content size category changed — the owning page must
        // rebuild the document (font metrics feed the builder). The modern
        // registration API instead of the deprecated traitCollectionDidChange.
        registerForTraitChanges([UITraitPreferredContentSizeCategory.self]) {
            (view: ShowNotesTextView, _: UITraitCollection) in
            view.onMetricsChange?()
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    // MARK: - Document

    /// Installs a built show-notes document and starts the inline image
    /// loads through `imageLoader`.
    func setDocument(_ attributed: NSAttributedString, imageLoader: ShowNotesImageLoading) {
        documentGeneration &+= 1
        let generation = documentGeneration
        for token in activeTokens { token.cancel() }
        activeTokens.removeAll()

        // Replace through textStorage: the attachment objects the storage
        // holds are the ones that get backfilled (attributed string copies
        // retain attribute values, so instances survive the move).
        textStorage.setAttributedString(attributed)

        // Record attachment character positions (and URLs) BEFORE starting
        // any load. Completions only ever apply length-preserving attribute
        // edits at these exact ranges, so re-querying storage after a load
        // lands is unnecessary and could only mis-align. The completion
        // carries only Sendable data and re-resolves the attachment at the
        // recorded location on the main actor.
        var pending: [(location: Int, url: URL)] = []
        let full = NSRange(location: 0, length: textStorage.length)
        textStorage.enumerateAttribute(.attachment, in: full) { value, range, _ in
            if let attachment = value as? ShowNotesImageAttachment,
               range.length == 1,
               attachment.intrinsicSize == nil {
                pending.append((range.location, attachment.noteImage.url))
            }
        }

        let targetSize = loadTargetSize
        for item in pending {
            let token = imageLoader.load(url: item.url, targetSize: targetSize) { [weak self] image in
                Task { @MainActor in
                    self?.applyLoadResult(
                        generation: generation,
                        location: item.location,
                        image: image
                    )
                }
            }
            activeTokens.append(token)
        }
    }

    /// Downsample target for inline loads: the current column as a square
    /// box. The processor fits the longest side within the box, so
    /// landscape bodies get full column width and portraits full column
    /// height — enough pixels for the fit-width display without keeping
    /// full-resolution show-notes art resident. Before layout the
    /// container carries a sentinel width; fall back to a typical column.
    private var loadTargetSize: CGSize {
        let width = textContainer.size.width
        let column = (width > 0 && width < 10_000) ? width : 320
        return CGSize(width: column, height: column)
    }

    /// Main-actor landing for a completed load.
    private func applyLoadResult(generation: Int, location: Int, image: UIImage?) {
        guard generation == documentGeneration else { return }
        guard location >= 0, location < textStorage.length else { return }
        guard let attachment = textStorage.attribute(
            .attachment, at: location, effectiveRange: nil
        ) as? ShowNotesImageAttachment else { return }
        guard let image else {
            // Failure keeps the declared/16:9 placeholder box; nothing is
            // inserted into the document. The shared cache hands the SAME
            // attachment to every visible text view — if a sibling view's
            // load already backfilled this instance, THIS view still needs
            // an edited pass or its layout stays on the stale placeholder.
            if attachment.intrinsicSize != nil {
                textStorage.beginEditing()
                textStorage.edited(
                    .editedAttributes,
                    range: NSRange(location: location, length: 1),
                    changeInLength: 0
                )
                textStorage.endEditing()
            }
            return
        }
        attachment.image = image
        // Kingfisher's downsampling pipeline produces scale-1 images, so
        // the point size carries the true pixel aspect.
        attachment.intrinsicSize = image.size

        textStorage.beginEditing()
        textStorage.edited(
            .editedAttributes,
            range: NSRange(location: location, length: 1),
            changeInLength: 0
        )
        textStorage.endEditing()
        onAttachmentHeightChanged?(location)
    }

    // MARK: - UITextViewDelegate (iOS 17+ text item routing)

    func textView(
        _ textView: UITextView,
        primaryActionFor textItem: UITextItem,
        defaultAction: UIAction
    ) -> UIAction? {
        switch textItem.content {
        case .textAttachment(let attachment):
            guard let imageAttachment = attachment as? ShowNotesImageAttachment else { return nil }
            // Read `image` at tap time, not action-creation time — the load
            // may land between layout and the tap.
            return UIAction { [weak self] _ in
                guard let self else { return }
                self.presentImage?(imageAttachment.noteImage, imageAttachment.image)
            }
        case .link(let url):
            guard let handler = onLinkTap else { return defaultAction }
            return UIAction { _ in
                handler(url)
            }
        default:
            // Custom tags and anything new: no primary action.
            return nil
        }
    }
}
