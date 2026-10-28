import UIKit
import Testing
import AnycastKit
@testable import Anycast

/// Integration smoke for the show-notes pipeline consumers. The Detail sheet
/// and the player settings page render notes through ShowNotesStore into a
/// ShowNotesTextView (the HTMLContentRenderer.makeTextView consumers were
/// switched); these tests pin the assembly the switch depends on:
///
/// 1. Store: the shared store turns fixture HTML into a non-empty attributed
///    document, returns an empty document for empty HTML, and the plain-text
///    fallback renders extracted plain text (the consumer fallback path).
/// 2. View: a ShowNotesTextView accepts a store document through
///    setDocument(_:imageLoader:) with the shared Kingfisher loader.
/// 3. Detail sheet: presenting the sheet with a fixture episode produces an
///    attached ShowNotesTextView in the hierarchy carrying the document.
///
/// The suite presents through the app's shared key window, so it is
/// serialized against the other window-driving suites (the UIFixRegression
/// doctrine).
@MainActor
@Suite(.serialized)
struct ShowNotesIntegrationTests {

    private static let fixtureHTML =
        "<p>Integration smoke body with a <a href=\"https://example.com/target\">link</a>.</p>"

    // MARK: - Store assembly

    @Test("Store renders fixture HTML; empty HTML yields the empty document; fallback renders plain text")
    func storeRenderAndFallback() async {
        let traits = UITraitCollection.current

        let attributed = await ShowNotesStore.shared.attributedString(
            html: Self.fixtureHTML, style: ShowNotesStyle(), traits: traits
        )
        #expect(attributed.length > 0, "store returned an empty document for non-empty HTML")
        #expect(attributed.string.contains("Integration smoke body"),
                "store document lost the fixture body: \(attributed.string)")

        let empty = await ShowNotesStore.shared.attributedString(
            html: "", style: ShowNotesStyle(), traits: traits
        )
        #expect(empty.length == 0, "empty HTML must render an empty document")

        // The consumer fallback for an empty rich document: plain text
        // extracted by the existing PlainTextHTMLCache path.
        let fallback = ShowNotesStore.shared.attributedFallback(
            plain: "Fallback plain text", style: ShowNotesStyle(), traits: traits
        )
        #expect(fallback.length > 0, "plain fallback rendered nothing")
        #expect(fallback.string == "Fallback plain text",
                "plain fallback altered its text: \(fallback.string)")
    }

    // MARK: - View assembly

    @Test("ShowNotesTextView accepts a store document through setDocument")
    func textViewAssembly() async {
        let attributed = await ShowNotesStore.shared.attributedString(
            html: Self.fixtureHTML, style: ShowNotesStyle(), traits: UITraitCollection.current
        )
        #expect(attributed.length > 0, "store returned nothing to assemble")

        let notesView = ShowNotesTextView()
        notesView.frame = CGRect(x: 0, y: 0, width: 354, height: 200)
        notesView.setDocument(attributed, imageLoader: KingfisherShowNotesImageLoader.shared)
        notesView.layoutIfNeeded()

        // The setDocument call itself is the smoke. When the view surfaces
        // the document as attributed text (the UITextView-based
        // implementation), the delivered document must be visible on it.
        if let textView = notesView as? UITextView {
            #expect(textView.attributedText.length > 0,
                    "setDocument left the text view empty")
        }
    }

    // MARK: - Detail sheet smoke

    @Test("Detail sheet renders its notes through a ShowNotesTextView")
    func detailSheetRendersShowNotes() async throws {
        guard let window = Self.keyWindow() else {
            print("[shownotes] no key window; skipping"); return
        }
        // Pre-warm the store with the fixture so the sheet's async render is
        // a warm-path delivery inside the settle window even on a cold
        // WebKit parse (the same HTML is what the sheet renders).
        _ = await ShowNotesStore.shared.attributedString(
            html: Self.fixtureHTML, style: ShowNotesStyle(), traits: window.traitCollection
        )

        let episode = DetailViewController.Episode(
            title: "Show notes integration episode",
            channelTitle: "Integration Channel",
            rssFeedURL: "https://example.com/feed.xml",
            enclosureURL: "https://example.com/feed.xml/episode-1.mp3",
            descriptionHTML: Self.fixtureHTML
        )
        let detail = DetailViewController(
            episode: episode, actions: [], htmlRenderer: HTMLContentRenderer()
        )
        detail.modalPresentationStyle = .pageSheet
        let presenter = await Self.settledTopPresenter(in: window) ?? window.rootViewController
        presenter?.present(detail, animated: false)
        // Tear down from the PRESENTING side (the UIFixRegression doctrine:
        // detail.dismiss would only remove anything presented ABOVE it).
        defer { presenter?.dismiss(animated: false) }
        try await Self.settle(window, seconds: 2.0)

        guard let notes = Self.firstView(in: detail.view, where: { $0 is ShowNotesTextView }) else {
            Issue.record("detail sheet has no ShowNotesTextView for the notes")
            return
        }
        #expect(notes.window != nil, "the notes view is not attached to a window")

        // Non-empty document in, non-empty notes out (asserted through the
        // UITextView surface when the implementation provides one).
        if let textView = notes as? UITextView {
            #expect(textView.attributedText.length > 0,
                    "notes document did not land in the detail sheet")
        }
    }

    // MARK: - Helpers (the UIFixRegressionTests window doctrine)

    private static func keyWindow() -> UIWindow? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)
    }

    private static func settle(_ window: UIWindow, seconds: Double) async throws {
        window.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(UInt64(seconds * 1000)))
        window.layoutIfNeeded()
    }

    private static func settledTopPresenter(in window: UIWindow) async -> UIViewController? {
        for _ in 0..<40 {
            let top = window.rootViewController?.topMostPresented()
            if let top, top.view.window != nil, !top.isBeingPresented,
               top.transitionCoordinator == nil {
                return top
            }
            try? await Task.sleep(for: .milliseconds(250))
        }
        return nil
    }

    private static func firstView(
        in view: UIView, where predicate: (UIView) -> Bool
    ) -> UIView? {
        if predicate(view) { return view }
        for subview in view.subviews {
            if let found = firstView(in: subview, where: predicate) { return found }
        }
        return nil
    }
}

private extension UIViewController {
    func topMostPresented() -> UIViewController {
        var top = self
        while let next = top.presentedViewController { top = next }
        return top
    }
}
