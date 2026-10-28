import UIKit
import Testing
import AnycastKit
@testable import Anycast

/// ShowNotesStore — parse dedup (memory + in-flight), the two cache layers
/// keying apart on metric signature, policy-versioned keys, the oversized
/// bypass, and the plain-text fallback.
@MainActor
struct ShowNotesStoreTests {

    /// Thread-safe call counter for the injected parse closure (it runs
    /// inside a detached task, so the class itself must be nonisolated).
    nonisolated private final class Counter: @unchecked Sendable {
        private let lock = NSLock()
        private var count = 0
        func increment() {
            lock.lock()
            count += 1
            lock.unlock()
        }
        var value: Int {
            lock.lock()
            defer { lock.unlock() }
            return count
        }
    }

    private let traitsA = UITraitCollection(mutations: {
        $0.preferredContentSizeCategory = .large
        $0.displayScale = 3.0
        $0.userInterfaceStyle = .dark
    })
    private let traitsB = UITraitCollection(mutations: {
        $0.preferredContentSizeCategory = .extraSmall
        $0.displayScale = 2.0
        $0.userInterfaceStyle = .light
    })

    private func makeStore(counter: Counter) -> ShowNotesStore {
        let store = ShowNotesStore()
        store.normalizeHTML = { html in
            counter.increment()
            return ShowNotesDocument(blocks: [.paragraph(runs: [.text("parsed: " + html)])])
        }
        return store
    }

    // MARK: Parse dedup

    @Test("Identical payloads parse exactly once across both cache layers")
    func parsesOnce() async {
        let counter = Counter()
        let store = makeStore(counter: counter)

        let document = await store.document(html: "notes-a")
        #expect(document.blocks.count == 1)
        _ = await store.attributedString(html: "notes-a", style: ShowNotesStyle(), traits: traitsA)

        #expect(counter.value == 1)
        #expect(store.documentCache.count == 1)
        #expect(store.textCache.count == 1)

        // A different payload parses separately.
        _ = await store.document(html: "notes-b")
        #expect(counter.value == 2)
        #expect(store.documentCache.count == 2)
    }

    @Test("Concurrent requests for one payload share a single in-flight parse")
    func inFlightDedup() async {
        let counter = Counter()
        let store = makeStore(counter: counter)

        async let first = store.document(html: "shared")
        async let second = store.document(html: "shared")
        let (a, b) = await (first, second)

        #expect(counter.value == 1)
        #expect(a.blocks.count == b.blocks.count)
        #expect(store.documentCache.count == 1)
    }

    // MARK: Layer separation

    @Test("A metric-signature change rebuilds only the text layer")
    func textLayerKeying() async {
        let counter = Counter()
        let store = makeStore(counter: counter)
        let style = ShowNotesStyle()

        _ = await store.attributedString(html: "same", style: style, traits: traitsA)
        _ = await store.attributedString(html: "same", style: style, traits: traitsA)
        #expect(store.textCache.count == 1)

        _ = await store.attributedString(html: "same", style: style, traits: traitsB)
        #expect(store.textCache.count == 2)
        #expect(store.documentCache.count == 1)
        #expect(counter.value == 1)
    }

    // MARK: Keys

    @Test("Cache keys embed the policy version, payload digest and signature")
    func keyComposition() {
        let style = ShowNotesStyle()

        let documentKey = ShowNotesStore.documentKey(html: "payload")
        #expect(documentKey.hasPrefix("notes.doc.v\(ShowNotesStore.policyVersion)|"))
        // Deterministic per payload, distinct across payloads.
        #expect(ShowNotesStore.documentKey(html: "payload") == documentKey)
        #expect(ShowNotesStore.documentKey(html: "other") != documentKey)

        let textKey = ShowNotesStore.textKey(html: "payload", style: style, traits: traitsA)
        #expect(textKey.hasPrefix(documentKey + "|"))
        #expect(textKey.contains(style.metricSignature(traitCollection: traitsA)))
        #expect(ShowNotesStore.textKey(html: "payload", style: style, traits: traitsB)
            != ShowNotesStore.textKey(html: "payload", style: style, traits: traitsA))
    }

    @Test("metricSignature separates category, scale and appearance")
    func signatures() {
        let style = ShowNotesStyle()
        #expect(style.metricSignature(traitCollection: traitsA)
            != style.metricSignature(traitCollection: traitsB))
        // Light/dark is part of the signature even with equal metrics.
        let dark = UITraitCollection(userInterfaceStyle: .dark)
        let light = UITraitCollection(userInterfaceStyle: .light)
        #expect(style.metricSignature(traitCollection: dark)
            != style.metricSignature(traitCollection: light))
    }

    // MARK: Oversized bypass + fallback

    @Test("Oversized payloads bypass parsing and fall back to plain text")
    func oversizedFallback() async {
        let counter = Counter()
        let store = makeStore(counter: counter)
        let huge = String(repeating: "a", count: ShowNotesStore.maxHTMLBytes + 1)

        let document = await store.document(html: huge)
        #expect(document.isEmpty)
        #expect(counter.value == 0)
        #expect(store.documentCache.isEmpty)

        let style = ShowNotesStyle()
        let fallback = store.attributedFallback(plain: "plain words", style: style, traits: traitsA)
        #expect(fallback.string == "plain words")
        let font = fallback.attribute(.font, at: 0, effectiveRange: nil) as? UIFont
        #expect(font?.pointSize == style.bodyFont(traits: traitsA).pointSize)
        // The fallback does not touch either cache.
        #expect(store.textCache.isEmpty)
    }

    @Test("attributedFallback matches a builder paragraph document")
    func fallbackParity() {
        let store = ShowNotesStore()
        let style = ShowNotesStyle()
        let plain = "Fallback text"
        let viaFallback = store.attributedFallback(plain: plain, style: style, traits: traitsA)
        let viaBuilder = ShowNotesBuilder().attributedString(
            from: ShowNotesDocument(blocks: [.paragraph(runs: [.text(plain)])]),
            style: style,
            traits: traitsA
        )
        #expect(viaFallback == viaBuilder)
    }
}
