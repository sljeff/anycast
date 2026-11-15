import UIKit
import Testing
@testable import Anycast

/// Regression for the blank-transcript bug: the soft edge used to be a
/// `CAGradientLayer` mask on the collection view's own layer. A scroll
/// view's layer bounds origin is its contentOffset, so the mask stayed at
/// the content top and every line was masked out once the list scrolled
/// more than about one viewport (any episode past a few minutes).
@MainActor
struct LyricsViewScrollTests {

    static func makeLines(_ count: Int) -> [LyricLine] {
        (0..<count).map {
            LyricLine(startMilliseconds: $0 * 5_000, text: "Line number \($0) of the transcript", translation: nil)
        }
    }

    static func mount(_ lyrics: LyricsView, size: CGSize = CGSize(width: 402, height: 420)) -> UIWindow {
        let window = UIWindow(frame: CGRect(origin: .zero, size: size))
        let host = UIViewController()
        window.rootViewController = host
        window.makeKeyAndVisible()
        lyrics.translatesAutoresizingMaskIntoConstraints = false
        host.view.addSubview(lyrics)
        NSLayoutConstraint.activate([
            lyrics.leadingAnchor.constraint(equalTo: host.view.leadingAnchor),
            lyrics.trailingAnchor.constraint(equalTo: host.view.trailingAnchor),
            lyrics.topAnchor.constraint(equalTo: host.view.topAnchor),
            lyrics.bottomAnchor.constraint(equalTo: host.view.bottomAnchor),
        ])
        host.view.layoutIfNeeded()
        return window
    }

    @Test("A long document scrolled far in keeps the active line visible and unmasked")
    func activeLineVisibleFarIntoDocument() {
        let lyrics = LyricsView()
        let window = Self.mount(lyrics)
        defer { window.isHidden = true }

        let lines = Self.makeLines(200)
        let activeIndex = 150
        lyrics.updateDocument(lines: lines, positionMilliseconds: lines[activeIndex].startMilliseconds)
        window.layoutIfNeeded()

        let collection = lyrics.collectionView
        #expect(collection.contentOffset.y > collection.bounds.height * 2, "list did not scroll far into the document")
        #expect(collection.layer.mask == nil, "fade must not be a mask on the scrolling layer")
        #expect(lyrics.layer.mask == nil)
        #expect(collection.superview?.layer.mask != nil, "fade lives on the non-scrolling wrapper")

        let cell = collection.cellForItem(at: IndexPath(item: activeIndex, section: 0))
        #expect(cell != nil, "active line has no cell")
        guard let cell else { return }
        let visibleRect = collection.bounds
        #expect(cell.frame.intersects(visibleRect))
        // Fully inside the viewport, clear of the fade ramps.
        #expect(cell.frame.minY >= visibleRect.minY + LyricsView.edgeLength)
        #expect(cell.frame.maxY <= visibleRect.maxY - LyricsView.edgeLength)
    }

    @Test("Progress ticks far past the first viewport keep following visible")
    func progressFollowStaysVisible() {
        let lyrics = LyricsView()
        let window = Self.mount(lyrics)
        defer { window.isHidden = true }

        let lines = Self.makeLines(200)
        lyrics.updateDocument(lines: lines, positionMilliseconds: 0)
        lyrics.setProgress(positionMilliseconds: lines[120].startMilliseconds)
        // Let the follow animator finish.
        RunLoop.main.run(until: Date().addingTimeInterval(1.5))
        window.layoutIfNeeded()

        let collection = lyrics.collectionView
        let cell = collection.cellForItem(at: IndexPath(item: 120, section: 0))
        #expect(cell != nil)
        #expect(cell.map { $0.frame.intersects(collection.bounds) } == true)
        #expect(collection.layer.mask == nil)
    }
}
