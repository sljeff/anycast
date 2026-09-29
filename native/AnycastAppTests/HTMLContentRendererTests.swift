import UIKit
import Testing
@testable import Anycast

/// HTMLContentRenderer — the synchronous pieces of the pipeline plus the
/// in-memory cache (07 §2.4). Fixed small inputs; the WebKit parse path
/// (loadFromHTML) is exercised once to prove end-to-end delivery.
@MainActor
struct HTMLContentRendererTests {

    @Test("Empty HTML renders nothing")
    func empty() async {
        let renderer = HTMLContentRenderer()
        let result = await renderer.attributedString(for: "", cacheKey: "k0")
        #expect(result.length == 0)
    }

    @Test("Plain (non-'<') strings pass through untouched")
    func plainPassthrough() async {
        let renderer = HTMLContentRenderer()
        let result = await renderer.attributedString(for: "Just a plain description", cacheKey: "k1")
        #expect(result.string == "Just a plain description")
        let color = result.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? UIColor
        #expect(color === Theme.primaryLightMax)
    }

    @Test("Sanitization-empty HTML falls back to htmlToText")
    func sanitizeEmptyFallback() async {
        let renderer = HTMLContentRenderer()
        // <center> is outside the sanitize_html whitelist, so the sanitized
        // fragment is empty; the renderHtml fallback routes through
        // htmlToText, which keeps the element's text.
        let result = await renderer.attributedString(for: "<center>alert(1)</center>", cacheKey: "k2")
        #expect(result.string == "alert(1)")
    }

    @Test("HTML parses off-main and lands in the per-episode cache")
    func htmlParsesAndCaches() async {
        let renderer = HTMLContentRenderer()
        let html = "<p>Hello <b>world</b></p>"
        let first = await renderer.attributedString(for: html, cacheKey: "episode-a")
        #expect(first.string.contains("Hello"))
        #expect(first.string.contains("world"))

        // Cached under the episode key with the sanitized payload attached.
        let entry = renderer.cachedEntry(cacheKey: "episode-a")
        #expect(entry != nil)
        #expect(entry?.html.contains("<b>") == true)
        #expect(entry?.attributed.string == first.string)

        // Second call for the same episode returns the cached instance.
        let second = await renderer.attributedString(for: html, cacheKey: "episode-a")
        #expect(second == first)

        // A different payload for the same key is re-rendered (not the
        // stale entry).
        let updated = "<p>Newer notes</p>"
        let third = await renderer.attributedString(for: updated, cacheKey: "episode-a")
        #expect(third.string.contains("Newer notes"))
    }

    @Test("Unstyled body text renders in the app color — WebKit stamps it black otherwise")
    func unstyledTextIsAppColored() async {
        let renderer = HTMLContentRenderer()
        let result = await renderer.attributedString(
            for: "<p>Hello dark mode</p>", cacheKey: "episode-color"
        )
        #expect(result.string.contains("Hello"))
        let color = result.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? UIColor
        #expect(color === Theme.primaryLightMax)
        let font = result.attribute(.font, at: 0, effectiveRange: nil) as? UIFont
        #expect(font?.pointSize == Typography.htmlBody.font().pointSize)
    }

    @Test("Links are tinted with the app link green")
    func linkColor() async {
        let renderer = HTMLContentRenderer()
        let html = "<p>See <a href=\"https://example.com\">docs</a></p>"
        let result = await renderer.attributedString(for: html, cacheKey: "episode-link")
        var sawLink = false
        result.enumerateAttribute(.link, in: NSRange(location: 0, length: result.length)) { value, _, stop in
            if value != nil {
                let range = (result.string as NSString).range(of: "docs")
                let color = result.attribute(.foregroundColor, at: range.location, effectiveRange: nil) as? UIColor
                #expect(color === Theme.tabSelectedGreen)
                sawLink = true
                stop.pointee = true
            }
        }
        #expect(sawLink)
    }

    @Test("PlainTextHTMLCache memoizes per input")
    func plainTextCacheMemoizes() async {
        let cache = PlainTextHTMLCache()
        let html = "<p>Cached <em>description</em> body</p>"
        let first = await cache.plainText(for: html)
        #expect(first == "Cached description body")
        let second = await cache.plainText(for: html)
        #expect(second == first)
        let count = await cache.count
        #expect(count == 1)
        #expect(await cache.plainText(for: nil) == "")
    }
}
