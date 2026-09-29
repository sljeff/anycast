import UIKit
import Testing
@testable import Anycast

/// Regression for the zero-height drag-seek time bar: every subview used
/// to pin only centerY, so Auto Layout gave `LyricsTimeBarView` a
/// zero-height bounds — it still painted (views don't clip) but the 36 pt
/// play button sat outside `bounds`, making every touch fall through to
/// the collection view and leaving drag-to-seek unusable.
@MainActor
struct LyricsTimeBarLayoutTests {

    @Test("time bar bounds cover the play button after layout")
    func timeBarBoundsCoverPlayButton() {
        let host = UIView(frame: CGRect(x: 0, y: 0, width: 402, height: 400))
        let lyrics = LyricsView()
        lyrics.translatesAutoresizingMaskIntoConstraints = false
        host.addSubview(lyrics)
        NSLayoutConstraint.activate([
            lyrics.leadingAnchor.constraint(equalTo: host.leadingAnchor),
            lyrics.trailingAnchor.constraint(equalTo: host.trailingAnchor),
            lyrics.topAnchor.constraint(equalTo: host.topAnchor),
            lyrics.bottomAnchor.constraint(equalTo: host.bottomAnchor),
        ])
        host.layoutIfNeeded()

        // The bar is private; reach it through the button it must cover.
        let button = Self.firstDescendant(
            of: lyrics,
            matching: { ($0 as? UIButton)?.accessibilityLabel == "Play from selected line" }
        )
        #expect(button != nil, "play button not found in the LyricsView hierarchy")
        guard let button, let bar = button.superview else { return }

        #expect(bar.bounds.height >= 36, "time bar laid out at \(bar.bounds.height) pt — touches fall outside bounds")
        let buttonCenterInBar = bar.convert(
            CGPoint(x: button.bounds.midX, y: button.bounds.midY),
            from: button
        )
        #expect(
            bar.point(inside: buttonCenterInBar, with: nil),
            "play button center must be hittable inside the bar's bounds"
        )
    }

    private static func firstDescendant(
        of view: UIView,
        matching predicate: (UIView) -> Bool
    ) -> UIView? {
        if predicate(view) { return view }
        for subview in view.subviews {
            if let match = firstDescendant(of: subview, matching: predicate) {
                return match
            }
        }
        return nil
    }
}
