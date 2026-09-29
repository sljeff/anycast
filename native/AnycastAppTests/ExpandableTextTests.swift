import UIKit
import Testing
@testable import Anycast

/// ExpandableText truncation logic — the Dart `tp.didExceedMaxLines`
/// equivalent (lib/widgets/expandable_text.dart).
@MainActor
struct ExpandableTextTests {

    @Test("Short text is not truncated and is not tappable")
    func shortText() {
        let view = ExpandableText(text: "Short line", style: .defaultText, maxLines: 2)
        view.frame = CGRect(x: 0, y: 0, width: 300, height: 60)
        view.layoutIfNeeded()

        #expect(!view.isTruncated)
        #expect(!view.isAccessibilityElement)
    }

    @Test("Two-line text fits exactly; three lines truncate")
    func boundary() {
        let twoLines = ExpandableText(
            text: "First line of text that is long enough\nSecond line",
            style: .defaultText,
            maxLines: 2
        )
        twoLines.frame = CGRect(x: 0, y: 0, width: 300, height: 80)
        twoLines.layoutIfNeeded()
        #expect(!twoLines.isTruncated)

        let threeLines = ExpandableText(
            text: "First line of text that is long enough\nSecond line continues here\nThird line",
            style: .defaultText,
            maxLines: 2
        )
        threeLines.frame = CGRect(x: 0, y: 0, width: 300, height: 80)
        threeLines.layoutIfNeeded()
        #expect(threeLines.isTruncated)
        #expect(threeLines.isAccessibilityElement)
        #expect(threeLines.accessibilityLabel == "Show full text")
    }

    @Test("Truncated surface collapses blank lines; full text does not")
    func blankLineCollapse() {
        let long = Array(repeating: "paragraph", count: 40).joined(separator: "\n\n")
        let view = ExpandableText(text: long, style: .defaultText, maxLines: 2)
        view.frame = CGRect(x: 0, y: 0, width: 200, height: 60)
        view.layoutIfNeeded()
        // The truncated copy replaces \n\n with \n (Dart line 71).
        let truncatedLabel = view.subviews.compactMap { $0 as? UILabel }.first
        #expect(truncatedLabel?.text?.contains("\n\n") == false)

        // "one\n\ntwo" renders as THREE lines (the blank line counts) —
        // it must NOT be truncated with a 3-line budget, and the original
        // blank lines are preserved when not truncated.
        let fitting = ExpandableText(text: "one\n\ntwo", style: .defaultText, maxLines: 3)
        fitting.frame = CGRect(x: 0, y: 0, width: 300, height: 80)
        fitting.layoutIfNeeded()
        #expect(!fitting.isTruncated)
        let plainLabel = fitting.subviews.compactMap { $0 as? UILabel }.first
        #expect(plainLabel?.text == "one\n\ntwo")
    }

    @Test("Tap only presents the full text when truncated")
    func tapRouting() {
        var presented: String?

        let long = ExpandableText(
            text: String(repeating: "word ", count: 80),
            style: .defaultText,
            maxLines: 2
        )
        long.presentFullText = { text, _ in presented = text }
        long.frame = CGRect(x: 0, y: 0, width: 200, height: 60)
        long.layoutIfNeeded()
        long.handleTap()
        #expect(presented != nil)

        presented = nil
        let short = ExpandableText(text: "fits", style: .defaultText, maxLines: 2)
        short.presentFullText = { text, _ in presented = text }
        short.frame = CGRect(x: 0, y: 0, width: 200, height: 60)
        short.layoutIfNeeded()
        short.handleTap()
        #expect(presented == nil)   // non-truncated taps do nothing
    }
}
