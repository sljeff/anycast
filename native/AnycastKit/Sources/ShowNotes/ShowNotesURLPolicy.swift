import Foundation

/// Shared URL-scheme policy for the HTML rendering paths.
///
/// The two required predicates mirror `HtmlText`'s historical behavior
/// exactly (Dart `sanitize_html`'s `_validLink` / `_validUrl`): schemeless
/// (relative) URLs are permitted there because the sanitizer re-serializes
/// fragments in place. `HtmlText` delegates to this type; its observable
/// behavior is unchanged.
///
/// The show-notes IR pipeline uses the stricter `…Absolute…` variants: a link
/// or image survives into the IR only when it carries an absolute http(s)
/// (host required) or, for links, a `mailto:` URL. Everything else degrades to
/// plain text (links) or is dropped (images).
public enum ShowNotesURLPolicy {

    /// https/http/mailto/schemeless allowed — mirrors `HtmlText.isPermittedLink`
    /// (Dart `_validLink`).
    public static func isPermittedLink(_ s: String) -> Bool {
        permittedSchemes(s, allowed: ["https", "http", "mailto"])
    }

    /// https/http/schemeless allowed — mirrors `HtmlText.isPermittedURL`
    /// (Dart `_validUrl`).
    public static func isPermittedImageURL(_ s: String) -> Bool {
        permittedSchemes(s, allowed: ["https", "http"])
    }

    // MARK: - Absolute variants (show-notes IR pipeline)

    /// True when `s` is an absolute link the IR may keep: http/https with a
    /// host, or any `mailto:` URL. Relative, anchor-only, protocol-relative,
    /// `javascript:`, `data:` and other schemes are rejected.
    public static func isPermittedAbsoluteLink(_ s: String) -> Bool {
        absoluteLinkURL(s) != nil
    }

    /// True when `s` is an absolute http/https image URL with a host.
    public static func isPermittedAbsoluteImageURL(_ s: String) -> Bool {
        absoluteImageURL(s) != nil
    }

    /// The parsed URL when `s` is a permitted absolute link (see
    /// `isPermittedAbsoluteLink`), otherwise nil.
    public static func absoluteLinkURL(_ s: String) -> URL? {
        guard let url = parse(s), let scheme = url.scheme?.lowercased() else { return nil }
        if scheme == "mailto" { return url }
        guard scheme == "https" || scheme == "http" else { return nil }
        return (url.host?.isEmpty == false) ? url : nil
    }

    /// The parsed URL when `s` is a permitted absolute image URL (see
    /// `isPermittedAbsoluteImageURL`), otherwise nil.
    public static func absoluteImageURL(_ s: String) -> URL? {
        guard let url = parse(s), let scheme = url.scheme?.lowercased() else { return nil }
        guard scheme == "https" || scheme == "http" else { return nil }
        return (url.host?.isEmpty == false) ? url : nil
    }

    // MARK: - Core

    /// The Dart parity rule: a URL parses and either carries no scheme
    /// (relative — permitted) or carries one of `allowed` (case-insensitive).
    static func permittedSchemes(_ url: String, allowed: [String]) -> Bool {
        guard let parsed = URL(string: url) else { return false }
        guard let scheme = parsed.scheme?.lowercased() else { return true } // no scheme
        return allowed.contains(scheme)
    }

    /// Parse after trimming surrounding whitespace (attribute values from
    /// real-world markup frequently carry padding).
    private static func parse(_ s: String) -> URL? {
        let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return URL(string: trimmed)
    }
}
