import CryptoKit
import Foundation
import UIKit
import AnycastKit

/// Shared caches for the show-notes pipeline: HTML → document (parsed
/// once per payload, off the main actor) and document → attributed string
/// (rebuilt per metric signature). All state lives on the main actor;
/// only the SwiftSoup normalization runs inside a detached task.
///
/// Growth is bounded by the distinct episode payloads seen this session —
/// same shape as the old renderer's per-episode in-memory cache.
@MainActor
final class ShowNotesStore {

    /// Cache-format version. Bump when normalization rules or builder
    /// styling semantics change; both cache layers key on it
    /// ("notes.doc.v<policyVersion>|…") so stale entries key apart.
    static let policyVersion = 1

    /// Payloads past this size skip the pipeline entirely (empty
    /// document); the caller renders the plain-text fallback instead.
    static let maxHTMLBytes = 2 * 1024 * 1024

    static let shared = ShowNotesStore()

    /// Injectable parse step — tests count invocations. Runs detached
    /// (SwiftSoup is not main-thread work); production defers to the
    /// AnycastKit normalizer.
    var normalizeHTML: @Sendable (_ html: String) -> ShowNotesDocument = {
        ShowNotesNormalizer.normalize(html: $0)
    }

    private let builder: ShowNotesBuilder

    /// Parsed documents, keyed by `documentKey(html:)`.
    private(set) var documentCache: [String: ShowNotesDocument] = [:]
    /// Built text, keyed by `textKey(html:style:traits:)`.
    private(set) var textCache: [String: NSAttributedString] = [:]
    /// One parse per key; concurrent callers await the same task.
    private var inFlightParses: [String: Task<SendableDocument, Never>] = [:]

    init(builder: ShowNotesBuilder = ShowNotesBuilder()) {
        self.builder = builder
    }

    // MARK: Documents

    func document(html: String) async -> ShowNotesDocument {
        guard html.utf8.count <= Self.maxHTMLBytes else {
            return ShowNotesDocument(blocks: [])
        }
        let key = Self.documentKey(html: html)
        if let cached = documentCache[key] { return cached }
        if let inFlight = inFlightParses[key] {
            return await inFlight.value.value
        }
        let normalizer = normalizeHTML
        let task = Task.detached(priority: .userInitiated) {
            SendableDocument(value: normalizer(html))
        }
        inFlightParses[key] = task
        let parsed = await task.value
        inFlightParses[key] = nil
        documentCache[key] = parsed.value
        return parsed.value
    }

    // MARK: Attributed text

    func attributedString(
        html: String,
        style: ShowNotesStyle,
        traits: UITraitCollection
    ) async -> NSAttributedString {
        let key = Self.textKey(html: html, style: style, traits: traits)
        if let cached = textCache[key] { return cached }
        let document = await self.document(html: html)
        // The parse hop may have raced a sibling build of the same key.
        if let cached = textCache[key] { return cached }
        let rendered = builder.attributedString(from: document, style: style, traits: traits)
        storeInTextCache(key: key, value: rendered)
        return rendered
    }

    /// The text layer is the memory-heavy one (it retains attachments that
    /// later hold loaded UIImages). Cap it with FIFO eviction — a plain
    /// dictionary would grow unbounded across a long browsing session.
    private static let textCacheLimit = 60
    private var textCacheOrder: [String] = []

    private func storeInTextCache(key: String, value: NSAttributedString) {
        if textCache[key] == nil, textCache.count >= Self.textCacheLimit,
           let oldest = textCacheOrder.first {
            textCache.removeValue(forKey: oldest)
            textCacheOrder.removeFirst()
        }
        if textCache[key] == nil { textCacheOrder.append(key) }
        textCache[key] = value
    }


    /// Plain-text escape hatch (oversized payloads and any future parse
    /// refusal): one body paragraph, no parsing, no cache traffic.
    func attributedFallback(
        plain: String,
        style: ShowNotesStyle,
        traits: UITraitCollection
    ) -> NSAttributedString {
        builder.attributedString(
            from: ShowNotesDocument(blocks: [.paragraph(runs: [.text(plain)])]),
            style: style,
            traits: traits
        )
    }

    // MARK: Cache keys

    /// "notes.doc.v<policy>|<SHA-256 of the payload>" — one parse per
    /// byte-identical payload.
    static func documentKey(html: String) -> String {
        let digest = SHA256.hash(data: Data(html.utf8))
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        return "notes.doc.v\(policyVersion)|\(hex)"
    }

    /// Document key + metric signature: text rebuilds only when the
    /// payload, policy version, or rendering traits change.
    static func textKey(html: String, style: ShowNotesStyle, traits: UITraitCollection) -> String {
        documentKey(html: html) + "|" + style.metricSignature(traitCollection: traits)
    }
}

/// ShowNotesDocument is a frozen value tree of Sendable leaves, but the
/// parallel-delivered type may not declare Sendable conformance yet; box
/// it so parse results can cross executors (same pattern as
/// HTMLContentRenderer's SendableText).
nonisolated private struct SendableDocument: @unchecked Sendable {
    let value: ShowNotesDocument
}
