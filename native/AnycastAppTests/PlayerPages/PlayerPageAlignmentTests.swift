import UIKit
import Testing
@testable import Anycast

/// Player main page: one 24 pt content column (artwork, title row, scrubber,
/// transport) with speed and sleep beside it; This episode page: chapters
/// and notes scroll under a fixed header. Hosts the real container (live context, seeded data
/// not required) in a private window of an exact size.
@MainActor
@Suite(.serialized)
struct PlayerPageAlignmentTests {

    // MARK: - Main page

    @Test("Main page: artwork, title row and scrubber share one 24 pt column; share glyph meets its edge")
    func mainColumn() async throws {
        guard let host = await Host.make(size: CGSize(width: 402, height: 812)) else { return }
        defer { host.discard() }
        let page = try #require(host.showMain())
        let column = CGRect(x: 24, y: 0, width: 402 - 48, height: 0)

        let cover = try #require(Host.firstView(in: page.view) { ($0 as? UIImageView)?.accessibilityLabel == "Episode artwork" })
        let coverFrame = page.view.convert(cover.bounds, from: cover)
        #expect(abs(coverFrame.minX - column.minX) < 0.5, "cover leading \(coverFrame.minX)")
        #expect(abs(coverFrame.maxX - column.maxX) < 0.5, "cover trailing \(coverFrame.maxX)")
        #expect(abs(coverFrame.width - coverFrame.height) < 1.5, "cover not square: \(coverFrame)")

        let progress = try #require(Host.firstView(in: page.view) { $0 is PlayerProgressBarView })
        let progressFrame = page.view.convert(progress.bounds, from: progress)
        #expect(abs(progressFrame.minX - column.minX) < 0.5)
        #expect(abs(progressFrame.maxX - column.maxX) < 0.5)

        let channel = try #require(Host.firstView(in: page.view) { $0.accessibilityLabel?.hasPrefix("Open channel") == true })
        let channelFrame = page.view.convert(channel.bounds, from: channel)
        #expect(abs(channelFrame.minX - column.minX) < 0.5, "title block leading \(channelFrame.minX)")

        let share = try #require(Host.firstView(in: page.view) { $0.accessibilityLabel == "Share episode" })
        let shareFrame = page.view.convert(share.bounds, from: share)
        #expect(shareFrame.width >= 44 && shareFrame.height >= 44, "share hit target \(shareFrame.size)")
        #expect(shareFrame.minX >= channelFrame.maxX, "title text must end before the share button")
        let ink = try #require(Host.inkRect(of: share))
        let inkInPage = ink.offsetBy(dx: shareFrame.minX, dy: shareFrame.minY)
        #expect(abs(inkInPage.maxX - column.maxX) <= 1, "share glyph trailing ink \(inkInPage.maxX) vs \(column.maxX)")
    }

    @Test("Main page: play centered, the two skip glyphs symmetric about it")
    func transportSymmetry() async throws {
        guard let host = await Host.make(size: CGSize(width: 402, height: 812)) else { return }
        defer { host.discard() }
        let page = try #require(host.showMain())

        func inkMidX(_ label: String) throws -> CGFloat {
            let button = try #require(Host.firstView(in: page.view) { ($0 as? UIButton)?.accessibilityLabel == label })
            let frame = page.view.convert(button.bounds, from: button)
            let ink = try #require(Host.inkRect(of: button))
            return frame.minX + ink.midX
        }
        let replay = try inkMidX("Seek back 10 seconds")
        let forward = try inkMidX("Seek forward 30 seconds")
        let center = page.view.bounds.midX
        #expect(abs((center - replay) - (forward - center)) <= 1,
                "skip glyphs asymmetric: \(center - replay) vs \(forward - center)")
    }

    @Test("Main page: short windows shrink the artwork (still centered) and keep the controls on screen")
    func compactHeight() async throws {
        for size in [CGSize(width: 375, height: 667), CGSize(width: 320, height: 568)] {
            guard let host = await Host.make(size: size) else { return }
            defer { host.discard() }
            let page = try #require(host.showMain())
            let cover = try #require(Host.firstView(in: page.view) { ($0 as? UIImageView)?.accessibilityLabel == "Episode artwork" })
            let coverFrame = page.view.convert(cover.bounds, from: cover)
            #expect(coverFrame.width <= size.width - 48 + 0.5)
            #expect(abs(coverFrame.midX - page.view.bounds.midX) < 1, "cover off center at \(size)")
            #expect(coverFrame.minY >= 24 - 0.5, "cover crammed at \(size): \(coverFrame)")
            let play = try #require(Host.firstView(in: page.view) { ($0 as? UIButton)?.accessibilityLabel == "Play or pause" })
            let playFrame = page.view.convert(play.bounds, from: play)
            #expect(playFrame.maxY <= page.view.bounds.maxY, "controls pushed off-screen at \(size)")
            #expect(coverFrame.width > 100, "cover collapsed at \(size): \(coverFrame)")
            // The artwork gives way before the scrubber is squeezed into the transport.
            let bar = try #require(Host.firstView(in: page.view) { $0 is PlayerProgressBarView })
            #expect(bar.bounds.height >= 59.5, "scrubber compressed to \(bar.bounds.height) at \(size)")
        }
    }

    @Test("Main page: large Dynamic Type keeps the controls inside the page")
    func largeType() async throws {
        guard let host = await Host.make(size: CGSize(width: 402, height: 812)) else { return }
        defer { host.discard() }
        host.container.traitOverrides.preferredContentSizeCategory = .accessibilityLarge
        let page = try #require(host.showMain())
        host.window.layoutIfNeeded()
        let play = try #require(Host.firstView(in: page.view) { ($0 as? UIButton)?.accessibilityLabel == "Play or pause" })
        let playFrame = page.view.convert(play.bounds, from: play)
        #expect(playFrame.maxY <= page.view.bounds.maxY)
        let cover = try #require(Host.firstView(in: page.view) { ($0 as? UIImageView)?.accessibilityLabel == "Episode artwork" })
        let coverFrame = page.view.convert(cover.bounds, from: cover)
        #expect(coverFrame.minY >= 24 - 0.5)
        #expect(abs(coverFrame.midX - page.view.bounds.midX) < 1)
    }

    @Test("Main page: speed and sleep flank the transport inside the column, in the thumb zone")
    func mainAccessories() async throws {
        guard let host = await Host.make(size: CGSize(width: 402, height: 812)) else { return }
        defer { host.discard() }
        let page = try #require(host.showMain())
        let play = try #require(Host.firstView(in: page.view) { ($0 as? UIButton)?.accessibilityLabel == "Play or pause" })
        let playFrame = page.view.convert(play.bounds, from: play)
        for (identifier, isLeading) in [("player-speed", true), ("player-sleep", false)] {
            let button = try #require(Host.firstView(in: page.view) { $0.accessibilityIdentifier == identifier } as? UIButton)
            let frame = page.view.convert(button.bounds, from: button)
            #expect(frame.width >= 44 && frame.height >= 44, "\(identifier) hit target \(frame.size)")
            #expect(abs(frame.midY - playFrame.midY) < 0.5, "\(identifier) off the transport row")
            #expect(isLeading ? abs(frame.minX - 24) < 0.5 : abs(frame.maxX - (402 - 24)) < 0.5, "\(identifier) at \(frame)")
            #expect(button.showsMenuAsPrimaryAction && button.menu != nil)
            #expect(frame.minY > page.view.bounds.height / 2, "\(identifier) left the thumb zone")
        }
    }

    // MARK: - This episode page

    @Test("This episode: long notes scroll under the fixed header")
    func episodeLongNotes() async throws {
        guard let host = await Host.make(size: CGSize(width: 402, height: 812)) else { return }
        defer { host.discard() }
        let page = try #require(host.showEpisode())
        let paragraphs = (1...50).map { "Paragraph \($0): a fairly long line of show notes that wraps over more than one line." }
        try host.setNotes(paragraphs.joined(separator: "\n\n"), in: page)

        let scroll = try #require(Host.firstView(in: page.view) { $0.accessibilityIdentifier == "player-episode-scroll" } as? UIScrollView)
        let notes = try #require(Host.firstView(in: page.view) { $0.accessibilityIdentifier == "player-episode-notes" })
        #expect(scroll.contentSize.height > scroll.bounds.height + 100, "long notes must scroll: \(scroll.contentSize)")
        let notesFrame = page.view.convert(notes.bounds, from: notes)
        #expect(abs(notesFrame.minX - 24) < 0.5 && abs(notesFrame.maxX - (402 - 24)) < 0.5, "notes column \(notesFrame)")
        let selector = try #require(Host.firstView(in: host.container.view) { $0 is PlayerPageTabView })
        let selectorTop = host.container.view.convert(selector.bounds, from: selector).minY
        let pageBottom = host.container.view.convert(page.view.bounds, from: page.view).maxY
        #expect(pageBottom <= selectorTop + 0.5)
    }

    // MARK: - Host

    /// A private window hosting the real container at an exact size.
    @MainActor
    final class Host {
        let window: UIWindow
        let container: PlayerPageContainer
        private let previousKey: UIWindow?

        private init(window: UIWindow, container: PlayerPageContainer, previousKey: UIWindow?) {
            self.window = window
            self.container = container
            self.previousKey = previousKey
        }

        static func make(size: CGSize) async -> Host? {
            var context: UIContext?
            for _ in 0..<40 {
                if let live = (UIApplication.shared.delegate as? AppDelegate)?.environment.uiContext {
                    context = live
                    break
                }
                try? await Task.sleep(for: .milliseconds(500))
            }
            guard let context else { print("[player-align] shell not ready; skipping"); return nil }
            let scene = UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .first { $0.activationState == .foregroundActive }
            let window = scene.map { UIWindow(windowScene: $0) } ?? UIWindow(frame: UIScreen.main.bounds)
            let previousKey = scene?.keyWindow
            let container = PlayerPageContainer(context: context)
            window.frame = CGRect(origin: .zero, size: size)
            window.rootViewController = container
            window.isHidden = false
            let host = Host(window: window, container: container, previousKey: previousKey)
            await host.settle()
            return host
        }

        func discard() {
            previousKey?.makeKey()
            window.rootViewController = nil
            window.isHidden = true
        }

        func settle() async {
            window.layoutIfNeeded()
            try? await Task.sleep(for: .milliseconds(400))
            window.layoutIfNeeded()
        }

        /// Walks the pager back to page 0 (the data source is the only
        /// public handle on the pages).
        private func showFirstPage() -> UIViewController? {
            guard let pager = Self.firstController(UIPageViewController.self, in: container),
                  var current = pager.viewControllers?.first else { return nil }
            while let previous = pager.dataSource?.pageViewController(pager, viewControllerBefore: current) {
                current = previous
            }
            pager.setViewControllers([current], direction: .forward, animated: false)
            window.layoutIfNeeded()
            return current
        }

        func showMain() -> PlayerMainPageViewController? {
            let page = Self.firstController(UIPageViewController.self, in: container)?.viewControllers?.first
            window.layoutIfNeeded()
            return page as? PlayerMainPageViewController
        }

        func showEpisode() -> EpisodePageViewController? {
            let page = showFirstPage() as? EpisodePageViewController
            window.layoutIfNeeded()
            return page
        }

        /// Replaces the notes' rendered content (the live seed's description
        /// would otherwise decide the test) and re-lays the page out.
        func setNotes(_ text: String, in page: EpisodePageViewController) throws {
            let textView = try #require(Self.firstView(in: page.view) { $0 is UITextView } as? UITextView)
            // An empty seed hides the notes host; the layout under test
            // needs it live.
            var ancestor: UIView? = textView
            while let view = ancestor { view.isHidden = false; ancestor = view.superview }
            textView.text = text
            textView.font = TypographyV2.body.font()
            window.layoutIfNeeded()
        }

        static func firstView(in root: UIView, where match: (UIView) -> Bool) -> UIView? {
            for subview in root.subviews {
                if match(subview) { return subview }
                if let found = firstView(in: subview, where: match) { return found }
            }
            return nil
        }

        static func firstController<T: UIViewController>(_ type: T.Type, in root: UIViewController) -> T? {
            for child in root.children {
                if let match = child as? T { return match }
                if let found = firstController(type, in: child) { return found }
            }
            return nil
        }

        /// The bounding box of the control's visible glyph pixels (alpha
        /// above a small threshold), in the control's own coordinates.
        static func inkRect(of view: UIView) -> CGRect? {
            let scale: CGFloat = 4
            let format = UIGraphicsImageRendererFormat()
            format.scale = scale
            let renderer = UIGraphicsImageRenderer(size: view.bounds.size, format: format)
            let image = renderer.image { context in view.layer.render(in: context.cgContext) }
            guard let cgImage = image.cgImage, let data = cgImage.dataProvider?.data,
                  let bytes = CFDataGetBytePtr(data) else { return nil }
            let width = cgImage.width, height = cgImage.height
            let bytesPerRow = cgImage.bytesPerRow, bytesPerPixel = cgImage.bitsPerPixel / 8
            var minX = width, maxX = -1, minY = height, maxY = -1
            for y in 0..<height {
                for x in 0..<width where bytes[y * bytesPerRow + x * bytesPerPixel + 3] > 40 {
                    minX = min(minX, x); maxX = max(maxX, x)
                    minY = min(minY, y); maxY = max(maxY, y)
                }
            }
            guard maxX >= 0 else { return nil }
            return CGRect(
                x: CGFloat(minX) / scale, y: CGFloat(minY) / scale,
                width: CGFloat(maxX - minX + 1) / scale, height: CGFloat(maxY - minY + 1) / scale
            )
        }
    }
}
