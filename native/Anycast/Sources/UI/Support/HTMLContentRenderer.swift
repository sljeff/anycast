import UIKit
import WebKit
import AnycastKit

/// HTML show-notes pipeline (07 §2.4, 08 §7.4): SwiftSoup-sanitized payload
/// (AnycastKit `HtmlText.displayPayload` — the Dart sanitize_html default
/// policy), parsed OFF the main thread with `NSAttributedString.loadFromHTML`
/// (the synchronous `init(html:)` must not run on main — iOS runtime warning
/// + stutter), post-processed into the app's dark typography, and delivered
/// on the main thread into a link-enabled text view. Links open through the
/// injectable handler (K7 registered enhancement — SFSafariViewController);
/// in the Dart baseline links were NOT tappable.
///
/// Per-episode in-memory cache: Detail and the future player page 0 share
/// one parsed attributed string per `cacheKey` (enclosure URL).
@MainActor
final class HTMLContentRenderer {

    /// Called with every tapped link. Production injects an
    /// SFSafariViewController presenter; nil falls back to the system
    /// default (open outside the app).
    var onLinkTap: ((URL) -> Void)?

    private final class CacheEntry: NSObject {
        let html: String
        let attributed: NSAttributedString
        init(html: String, attributed: NSAttributedString) {
            self.html = html
            self.attributed = attributed
        }
    }

    /// NSAttributedString does not declare Sendable on iOS; box it so task
    /// results can cross executors. The boxed values are treated as frozen
    /// after delivery (never mutated again).
    private struct SendableText: @unchecked Sendable {
        let value: NSAttributedString
    }

    /// One in-flight render per (episode, payload); a second request for the
    /// same pair awaits the first instead of re-parsing.
    private var inFlight: [String: Task<SendableText, Never>] = [:]
    private let cache = NSCache<NSString, CacheEntry>()

    /// Per-text-view render generations. A reused cell or a page that
    /// switched episodes can have two renders in flight for the same text
    /// view; only the latest may write — a slow older parse landing last
    /// would overwrite the newer content with nothing left to correct it.
    private var renderGenerations: [ObjectIdentifier: Int] = [:]

    init(onLinkTap: ((URL) -> Void)? = nil) {
        self.onLinkTap = onLinkTap
    }

    // MARK: - Text view

    /// A non-editable, non-scrolling text view configured for show notes —
    /// UITextView (not UILabel) because links must be tappable.
    static func makeTextView(linkTarget: HTMLContentRenderer? = nil) -> UITextView {
        let textView = LinkTextView()
        textView.backgroundColor = .clear
        textView.isEditable = false
        textView.isScrollEnabled = false
        textView.textContainerInset = .zero
        textView.textContainer.lineFragmentPadding = 0
        textView.linkTextAttributes = [.foregroundColor: Theme.tabSelectedGreen]
        textView.renderer = linkTarget
        return textView
    }

    // MARK: - Render

    /// Routes `html` through the Dart `renderHtml` decision (03 §7):
    /// empty → empty; starts with '<' → sanitized HTML (htmlToText fallback
    /// when sanitization empties it); anything else → plain string.
    func attributedString(
        for html: String,
        cacheKey: String,
        traits: UITraitCollection? = nil
    ) async -> NSAttributedString {
        await attributedString(
            for: HtmlText.displayPayload(for: html),
            cacheKey: cacheKey,
            traits: traits
        )
    }

    /// Payload-taking core: `render` parses the payload once and shares it
    /// with its progressive plain-text bridge, instead of each entry point
    /// re-running `displayPayload` (sanitize + parse) over the same HTML.
    private func attributedString(
        for payload: HtmlText.DisplayPayload,
        cacheKey: String,
        traits: UITraitCollection?
    ) async -> NSAttributedString {
        switch payload {
        case .empty:
            return NSAttributedString()
        case let .text(plain):
            // Synchronous passthrough — no parsing, no cache needed.
            return NSAttributedString(string: plain, attributes: baseAttributes(traits: traits))
        case let .html(sanitized):
            return await renderSanitized(sanitized, cacheKey: cacheKey, traits: traits)
        }
    }

    /// Renders into `textView`; reuse-safe in the sense that only the latest
    /// `cacheKey`'s result is applied (cell reuse passes a fresh key and this
    /// awaits in order at the call site).
    ///
    /// Progressive bridge: WebKit's first HTML parse takes seconds cold, and
    /// the Detail sheet showed a blank body that whole time (the walkthrough
    /// recording caught it) — Dart's flutter_html paints immediately. Until
    /// the rich parse lands, show the same fast plain text the cards use.
    func render(_ html: String, cacheKey: String, into textView: UITextView) async {
        let textViewKey = ObjectIdentifier(textView)
        renderGenerations[textViewKey, default: 0] += 1
        let generation = renderGenerations[textViewKey]!
        defer {
            // Leave the slot for a newer render; reclaim it when ours is
            // still the latest (bounded growth over reused text views).
            if renderGenerations[textViewKey] == generation {
                renderGenerations.removeValue(forKey: textViewKey)
            }
        }
        let isLatest = { [weak self] in
            self?.renderGenerations[textViewKey] == generation
        }
        let payload = HtmlText.displayPayload(for: html)
        if case let .html(sanitized) = payload,
           cachedEntry(cacheKey: cacheKey)?.html != sanitized,
           textView.attributedText.length == 0 {
            let plain = await PlainTextHTMLCache.shared.plainText(for: html)
            // The rich render below is the only writer afterwards; if it
            // already finished during the plain-text hop this is a no-op.
            if isLatest(), textView.attributedText.length == 0 {
                textView.attributedText = NSAttributedString(
                    string: plain,
                    attributes: baseAttributes(traits: textView.traitCollection)
                )
            }
        }
        let attributed = await attributedString(
            for: payload, cacheKey: cacheKey, traits: textView.traitCollection
        )
        guard isLatest() else { return }
        textView.attributedText = attributed
    }

    /// Test/peek accessor for the in-memory cache.
    func cachedEntry(cacheKey: String) -> (html: String, attributed: NSAttributedString)? {
        guard let entry = cache.object(forKey: NSString(string: cacheKey)) else { return nil }
        return (entry.html, entry.attributed)
    }

    // MARK: - Internals

    private func renderSanitized(
        _ sanitized: String,
        cacheKey: String,
        traits: UITraitCollection?
    ) async -> NSAttributedString {
        let nsKey = NSString(string: cacheKey)
        if let entry = cache.object(forKey: nsKey), entry.html == sanitized {
            return entry.attributed
        }

        let flightKey = "\(cacheKey)#\(sanitized.hashValue)"
        if let existing = inFlight[flightKey] {
            return await existing.value.value
        }

        let base = baseAttributes(traits: traits)
        let task = Task<SendableText, Never>(priority: .userInitiated) { [weak self] in
            // parseOffMain is nonisolated: the WebKit parse hops to the
            // global executor; only the bookkeeping below stays on main.
            let parsed = await Self.parseOffMain(sanitized, attributes: base)
            self?.inFlight[flightKey] = nil
            self?.cache.setObject(CacheEntry(html: sanitized, attributed: parsed), forKey: nsKey)
            return SendableText(value: parsed)
        }
        inFlight[flightKey] = task
        return await task.value.value
    }

    private func baseAttributes(traits: UITraitCollection?) -> [NSAttributedString.Key: Any] {
        [
            .font: Typography.htmlBody.font(traits: traits),
            .foregroundColor: Typography.htmlBody.color,
        ]
    }

    /// The WebKit parse + dark-theme post-pass, off the main actor.
    /// SDK 27 hosts the HTML import in WebKit as `fromHTML(_:options:)`
    /// (the old Foundation `loadFromHTML` family is gone from the SDK); it
    /// returns a (string, documentAttributes) tuple.
    nonisolated private static func parseOffMain(
        _ html: String,
        attributes base: [NSAttributedString.Key: Any]
    ) async -> NSAttributedString {
        let loaded: NSAttributedString
        do {
            let (parsed, _) = try await NSAttributedString.fromHTML(
                html,
                options: [.documentType: NSAttributedString.DocumentType.html]
            )
            loaded = parsed
        } catch {
            // Dart onErrorBuilder printed the error in robotoMono red — keep
            // the same visible signal instead of hiding the failure.
            return NSAttributedString(
                string: error.localizedDescription,
                attributes: Typography.htmlError.attributes()
            )
        }
        return postProcess(loaded, base: base)
    }

    /// Links → the app link green (03 §5.1 0x6EE7B7); everything else gets
    /// re-based onto the app's htmlBody style. The WebKit import stamps a
    /// full computed style on EVERY run — unstyled body text arrives as
    /// 12pt Times in pure black, which is invisible on the dark surface and
    /// is NOT an author choice (the Dart `textStyle` colors it onSurface).
    /// So: pure-black colors and the default-size Times face are treated as
    /// "unstyled" and rebased; authored colors and sized/emphasized fonts
    /// keep their intent (size scales relative to the 12pt default).
    nonisolated private static func postProcess(
        _ source: NSAttributedString,
        base: [NSAttributedString.Key: Any]
    ) -> NSAttributedString {
        let result = NSMutableAttributedString(attributedString: source)
        let full = NSRange(location: 0, length: result.length)
        var replacements: [(NSRange, [NSAttributedString.Key: Any])] = []
        result.enumerateAttributes(in: full) { attrs, range, _ in
            var attributes = attrs
            // The WebKit import stamps document/paragraph backgrounds on
            // runs; flutter_html painted show notes on a transparent
            // surface, so authored-looking backgrounds are an import
            // artifact — strip them (they rendered as a white block on the
            // v2 sheet).
            attributes.removeValue(forKey: .backgroundColor)
            if attrs[.link] != nil {
                attributes[.foregroundColor] = Theme.tabSelectedGreen
            } else {
                let color = attrs[.foregroundColor] as? UIColor
                if (color == nil || color!.isWebKitDefaultBlack),
                   let baseColor = base[.foregroundColor] {
                    attributes[.foregroundColor] = baseColor
                }
                if let baseFont = base[.font] as? UIFont {
                    attributes[.font] = rebasedFont(attrs[.font] as? UIFont, onto: baseFont)
                }
            }
            let paragraph = (attrs[.paragraphStyle] as? NSParagraphStyle).map {
                $0.mutableCopy() as! NSMutableParagraphStyle
            } ?? NSMutableParagraphStyle()
            paragraph.lineHeightMultiple = 1.2
            attributes[.paragraphStyle] = paragraph
            replacements.append((range, attributes))
        }
        for (range, attributes) in replacements {
            result.setAttributes(attributes, range: range)
        }
        return result
    }

    /// Rebase a WebKit-imported font onto the app body font: family and size
    /// switch to the base, the parsed size ratio is preserved (h1 ≈ 2× the
    /// 12pt default), and symbolic emphasis traits (bold/italic) carry over
    /// when the family has them.
    nonisolated private static func rebasedFont(_ parsed: UIFont?, onto base: UIFont) -> UIFont {
        guard let parsed else { return base }
        let scale = max(parsed.pointSize / 12.0, 0.5)
        let traits = parsed.fontDescriptor.symbolicTraits
            .intersection([.traitBold, .traitItalic, .traitMonoSpace])
        var descriptor = base.fontDescriptor
        if !traits.isEmpty,
           let withTraits = descriptor.withSymbolicTraits(traits) {
            descriptor = withTraits
        }
        return UIFont(descriptor: descriptor, size: base.pointSize * scale)
    }
}

private extension UIColor {
    /// Pure (or effectively pure) black — the color WebKit stamps on
    /// unstyled runs. A tight threshold keeps authored near-blank colors
    /// distinguishable; black on a dark surface is unreadable either way.
    var isWebKitDefaultBlack: Bool {
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        guard getRed(&red, green: &green, blue: &blue, alpha: &alpha) else { return false }
        return alpha > 0.9 && red < 0.05 && green < 0.05 && blue < 0.05
    }
}

/// UITextView whose link taps route back into the renderer's injectable
/// handler instead of the default behavior.
@MainActor
private final class LinkTextView: UITextView, UITextViewDelegate {

    weak var renderer: HTMLContentRenderer?

    override init(frame: CGRect, textContainer: NSTextContainer?) {
        super.init(frame: frame, textContainer: textContainer)
        delegate = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func textView(
        _ textView: UITextView,
        shouldInteractWith url: URL,
        in characterRange: NSRange,
        interaction: UITextItemInteraction
    ) -> Bool {
        if let handler = renderer?.onLinkTap {
            handler(url)
            return false
        }
        return true
    }
}
