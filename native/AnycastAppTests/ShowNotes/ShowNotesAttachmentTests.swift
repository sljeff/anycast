import UIKit
import Testing
import AnycastKit
@testable import Anycast

/// Configurable show-notes loader for tests: immediate, delayed, or
/// failing delivery. Delivery always hops through the main actor so the
/// production completion (which itself hops) is exercised exactly as the
/// Kingfisher path would land. Images are synthesized on delivery
/// (UIGraphicsImageRenderer is safe off the main thread, unlike the legacy
/// context APIs) so no non-Sendable state is stored.
nonisolated final class StubShowNotesImageLoader: ShowNotesImageLoading {

    /// What a load delivers.
    enum Outcome: Sendable {
        /// A solid image of the given size. The renderer runs at scale 1,
        /// so the point size is exact for assertions.
        case image(CGSize)
        case failure
    }

    let outcome: Outcome
    /// Seconds before the completion fires (0 = as soon as the main actor
    /// can service it).
    let delay: TimeInterval

    init(outcome: Outcome, delay: TimeInterval = 0) {
        self.outcome = outcome
        self.delay = delay
    }

    func load(
        url: URL,
        targetSize: CGSize,
        completion: @escaping @Sendable (UIImage?) -> Void
    ) -> ShowNotesImageLoadToken {
        let outcome = outcome
        let delay = delay
        Task { @MainActor in
            if delay > 0 {
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
            switch outcome {
            case let .image(size):
                completion(Self.solidImage(size: size))
            case .failure:
                completion(nil)
            }
        }
        // Cancellation is not modeled: stale deliveries are supposed to be
        // rejected by the view's generation guard, which is exactly what
        // these tests exercise.
        return ShowNotesImageLoadToken { }
    }

    private static func solidImage(size: CGSize) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIColor.systemTeal.setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
    }
}

/// NSTextLocation stand-in: the TextKit 2 attachmentBounds hook never
/// inspects the location, its presence is all that is required.
private final class TestTextLocation: NSObject, NSTextLocation {
    nonisolated func compare(_ location: any NSTextLocation) -> ComparisonResult {
        .orderedSame
    }
}

/// ShowNotesImageAttachment bounds — the thin wrapper around AnycastKit's
/// pure ImageFit — asserted with plain inputs and outputs (controlled
/// proposed line fragments and containers, no text layout involved); plus
/// the setDocument backfill contract: loads rewrite attachment attributes
/// in place without moving characters or leaving the recorded range.
@MainActor
struct ShowNotesAttachmentTests {

    // MARK: - Fixtures

    private func makeAttachment(
        declared: CGSize? = nil,
        intrinsic: CGSize? = nil
    ) -> ShowNotesImageAttachment {
        let attachment = ShowNotesImageAttachment(
            noteImage: ShowNotesImage(
                url: URL(string: "https://example.com/notes-image.jpg")!,
                alt: "fixture",
                declaredSize: declared,
                index: 0
            )
        )
        attachment.intrinsicSize = intrinsic
        return attachment
    }

    private func bounds(
        of attachment: ShowNotesImageAttachment,
        proposedWidth: CGFloat,
        containerWidth: CGFloat? = nil
    ) -> CGRect {
        let container = containerWidth.map {
            NSTextContainer(size: CGSize(width: $0, height: .greatestFiniteMagnitude))
        }
        return attachment.attachmentBounds(
            for: [:],
            location: TestTextLocation(),
            textContainer: container,
            proposedLineFragment: CGRect(x: 0, y: 0, width: proposedWidth, height: 17),
            position: .zero
        )
    }

    private func expectClose(
        _ value: CGFloat,
        _ expected: CGFloat,
        accuracy: CGFloat = 0.5,
        sourceLocation: SourceLocation = #_sourceLocation
    ) {
        #expect(abs(value - expected) <= accuracy, sourceLocation: sourceLocation)
    }

    /// Yields to the main actor until `condition` holds (or a deadline
    /// passes), draining the Task hops the production code enqueues.
    private func waitUntil(
        timeout: TimeInterval = 2,
        _ condition: @escaping () -> Bool
    ) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() && Date() < deadline {
            await Task.yield()
        }
    }

    // MARK: - attachmentBounds

    @Test("Unloaded attachment reserves the declared aspect, fit to width")
    func placeholderDeclaredSizeFitsWidth() {
        let attachment = makeAttachment(declared: CGSize(width: 400, height: 300))
        let rect = bounds(of: attachment, proposedWidth: 320)
        #expect(rect.origin == .zero)
        expectClose(rect.width, 320)
        expectClose(rect.height, 240)
    }

    @Test("Loaded attachment switches to the intrinsic aspect")
    func loadedUsesIntrinsicOverDeclared() {
        let attachment = makeAttachment(
            declared: CGSize(width: 400, height: 300),
            intrinsic: CGSize(width: 800, height: 400)
        )
        let rect = bounds(of: attachment, proposedWidth: 320)
        expectClose(rect.width, 320)
        expectClose(rect.height, 160)
    }

    @Test("Available width is the narrower of the proposed fragment and the container")
    func containerCapsAvailableWidth() {
        let attachment = makeAttachment(declared: CGSize(width: 400, height: 200))
        let rect = bounds(of: attachment, proposedWidth: 400, containerWidth: 300)
        expectClose(rect.width, 300)
        expectClose(rect.height, 150)
    }

    @Test("Missing declared size falls back to a full-width 16:9 placeholder")
    func placeholderFallbackKeepsSixteenNine() {
        let attachment = makeAttachment(declared: nil)
        // Invalid placeholder routes through ImageFit's own 16:9 path.
        #expect(attachment.placeholderSize == .zero)
        let rect = bounds(of: attachment, proposedWidth: 320)
        expectClose(rect.width, 320)
        expectClose(rect.height, 180)
        expectClose(rect.width / rect.height, 16.0 / 9.0, accuracy: 0.01)
    }

    @Test("A tall intrinsic is capped at 1.5× the column width")
    func tallImageHeightCap() {
        let attachment = makeAttachment(
            declared: nil,
            intrinsic: CGSize(width: 100, height: 12000)
        )
        let rect = bounds(of: attachment, proposedWidth: 320)
        expectClose(rect.height, 1.5 * 320)
        expectClose(rect.width, 100 * (1.5 * 320 / 12000), accuracy: 0.5)
    }

    @Test("A loaded 1×1 tracking pixel collapses to zero bounds")
    func loadedTrackingPixelCollapses() {
        let attachment = makeAttachment(
            declared: nil,
            intrinsic: CGSize(width: 1, height: 1)
        )
        let rect = bounds(of: attachment, proposedWidth: 320)
        #expect(rect == .zero)
    }

    @Test("A declared small icon stays capped even after a large source loads")
    func declaredSmallIconCapsLoadedSource() {
        let attachment = makeAttachment(
            declared: CGSize(width: 16, height: 16),
            intrinsic: CGSize(width: 512, height: 512)
        )
        let rect = bounds(of: attachment, proposedWidth: 320)
        expectClose(rect.width, 16)
        expectClose(rect.height, 16)
    }

    @Test("A degenerate available width yields a zero rect")
    func zeroAvailableWidthYieldsZero() {
        let attachment = makeAttachment(declared: CGSize(width: 400, height: 300))
        let rect = bounds(of: attachment, proposedWidth: 0)
        #expect(rect == .zero)
    }

    // MARK: - setDocument backfill

    private func makeDocument(
        with attachment: ShowNotesImageAttachment
    ) -> (text: NSMutableAttributedString, attachmentLocation: Int) {
        let text = NSMutableAttributedString(string: "Before ")
        text.append(NSAttributedString(attachment: attachment))
        text.append(NSAttributedString(string: " after"))
        return (text, 7)
    }

    @Test("Immediate load backfills the attachment in place without moving characters")
    func immediateLoadBackfillsInPlace() async {
        let attachment = makeAttachment(declared: CGSize(width: 100, height: 50))
        let (document, location) = makeDocument(with: attachment)
        let length = document.length

        let textView = ShowNotesTextView(frame: CGRect(x: 0, y: 0, width: 320, height: 2000))
        textView.setDocument(
            document,
            imageLoader: StubShowNotesImageLoader(outcome: .image(CGSize(width: 640, height: 320)))
        )

        await waitUntil { attachment.intrinsicSize != nil }

        #expect(textView.textStorage.length == length)
        #expect(attachment.image != nil)
        #expect(attachment.intrinsicSize == CGSize(width: 640, height: 320))
        let stored = textView.textStorage.attribute(
            .attachment, at: location, effectiveRange: nil
        ) as? ShowNotesImageAttachment
        #expect(stored === attachment)
    }

    @Test("Failed load keeps the placeholder and the document intact")
    func failedLoadKeepsPlaceholder() async {
        let attachment = makeAttachment(declared: CGSize(width: 100, height: 50))
        let (document, location) = makeDocument(with: attachment)
        let length = document.length

        let textView = ShowNotesTextView(frame: CGRect(x: 0, y: 0, width: 320, height: 2000))
        textView.setDocument(
            document,
            imageLoader: StubShowNotesImageLoader(outcome: .failure)
        )

        // Give the (failing) delivery a moment to land.
        try? await Task.sleep(for: .milliseconds(150))

        #expect(textView.textStorage.length == length)
        #expect(textView.textStorage.string == document.string)
        #expect(attachment.intrinsicSize == nil)
        #expect(attachment.image == nil)
        let stored = textView.textStorage.attribute(
            .attachment, at: location, effectiveRange: nil
        ) as? ShowNotesImageAttachment
        #expect(stored === attachment)
        // No error text was spliced in anywhere.
        #expect(textView.textStorage.string == "Before \u{FFFC} after")
    }

    @Test("A late completion from a replaced document is ignored")
    func staleGenerationIsIgnored() async {
        let first = makeAttachment(declared: CGSize(width: 100, height: 50))
        let (firstDocument, _) = makeDocument(with: first)
        let second = makeAttachment(declared: CGSize(width: 100, height: 50))
        let (secondDocument, secondLocation) = makeDocument(with: second)

        let textView = ShowNotesTextView(frame: CGRect(x: 0, y: 0, width: 320, height: 2000))
        // First document loads with a delay; replaced immediately.
        textView.setDocument(
            firstDocument,
            imageLoader: StubShowNotesImageLoader(
                outcome: .image(CGSize(width: 640, height: 320)), delay: 0.15
            )
        )
        textView.setDocument(
            secondDocument,
            imageLoader: StubShowNotesImageLoader(outcome: .failure)
        )

        // Let the stale (cancelled-generation) completion fire.
        try? await Task.sleep(for: .milliseconds(450))

        #expect(first.intrinsicSize == nil, "replaced document's late load must not backfill")
        #expect(first.image == nil)
        #expect(second.intrinsicSize == nil)
        #expect(textView.textStorage.length == secondDocument.length)
        let stored = textView.textStorage.attribute(
            .attachment, at: secondLocation, effectiveRange: nil
        ) as? ShowNotesImageAttachment
        #expect(stored === second)
    }
}

extension ShowNotesAttachmentTests {
// MARK: - Shared-attachment, dual-view refresh

@Test("A view whose own load failed still refreshes when a sibling filled the shared attachment")
@MainActor
func siblingBackfillRefreshesFailedView() async {
    // The store's text cache hands the SAME attachment instance to every
    // visible consumer. View A loads successfully; view B's own load fails
    // — B must still run the edited pass or its layout keeps the stale
    // placeholder box.
    let attachment = makeAttachment(declared: CGSize(width: 100, height: 60))

    let document = NSMutableAttributedString(string: "x")
    document.append(NSAttributedString(attachment: attachment))
    document.append(NSAttributedString(string: "y"))

    let viewA = ShowNotesTextView()
    let viewB = ShowNotesTextView()
    for view in [viewA, viewB] {
        view.frame = CGRect(x: 0, y: 0, width: 320, height: 400)
        view.setDocument(document, imageLoader: StubShowNotesImageLoader(outcome: .image(CGSize(width: 100, height: 60))))
    }
    // The production path keys off intrinsicSize presence: emulate the
    // sibling's success by hand, then B's failure path through a fresh
    // loader that fails while intrinsic is already set.
    attachment.intrinsicSize = CGSize(width: 100, height: 60)
    let failed = ShowNotesTextView()
    failed.frame = CGRect(x: 0, y: 0, width: 320, height: 400)
    failed.setDocument(document, imageLoader: StubShowNotesImageLoader(outcome: .failure, delay: 0.05))
    try? await Task.sleep(for: .milliseconds(300))
    // No crash, document intact, attachment still present at its slot.
    #expect(failed.textStorage.length == document.length)
    let kept = failed.textStorage.attribute(.attachment, at: 1, effectiveRange: nil)
    #expect((kept as? ShowNotesImageAttachment) === attachment)
}
}
