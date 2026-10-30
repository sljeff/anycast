import UIKit
import Testing
import AnycastKit
@testable import Anycast

/// ScrollEdgeChrome: scroll content fades out behind fixed chrome instead
/// of being hard-cut. One component, an OS branch inside it: the iOS 26
/// system scroll edge interaction, or the iOS 18 `ScrollEdgeFade`.
@MainActor
struct ScrollEdgeChromeTests {

    private func makeHost() -> (host: UIView, scrollView: UIScrollView, chrome: UIView) {
        let host = UIView(frame: CGRect(x: 0, y: 0, width: 400, height: 800))
        let scrollView = UIScrollView(frame: host.bounds)
        scrollView.contentInsetAdjustmentBehavior = .never
        host.addSubview(scrollView)
        let chrome = UIView(frame: CGRect(x: 0, y: 0, width: 400, height: 100))
        host.addSubview(chrome)
        return (host, scrollView, chrome)
    }

    @Test("attach adds the solid fade on every OS, plus the system interaction on iOS 26+")
    func attachBranchesByOS() {
        let (host, scrollView, chrome) = makeHost()
        let fade = ScrollEdgeChrome.attach(chrome: chrome, to: scrollView, edge: .top, in: host)
        #expect(fade.superview === host)
        // Stacking: scroll view < fade < chrome.
        let order = host.subviews
        let fadeIndex = order.firstIndex(of: fade) ?? -1
        let scrollIndex = order.firstIndex(of: scrollView) ?? -1
        let chromeIndex = order.firstIndex(of: chrome) ?? -1
        #expect(scrollIndex < fadeIndex && fadeIndex < chromeIndex)
        if #available(iOS 26.0, *) {
            let edgeInteractions = chrome.interactions.compactMap { $0 as? UIScrollEdgeElementContainerInteraction }
            #expect(edgeInteractions.count == 1)
            #expect(edgeInteractions.first?.scrollView === scrollView)
            #expect(edgeInteractions.first?.edge == .top)
            #expect(scrollView.topEdgeEffect.isHidden == false)
            #expect(scrollView.topEdgeEffect.style == ScrollEdgeChrome.edgeEffectStyle)
        } else {
            #expect(chrome.interactions.isEmpty)
        }
    }

    @Test("the chrome ends up above the scroll view whatever the add order")
    func chromeStacksAboveScrollView() {
        let host = UIView(frame: CGRect(x: 0, y: 0, width: 400, height: 800))
        let chrome = UIView(frame: CGRect(x: 0, y: 0, width: 400, height: 100))
        host.addSubview(chrome)
        let scrollView = UIScrollView(frame: host.bounds)
        host.addSubview(scrollView)   // above the chrome, as the list screens add it
        ScrollEdgeChrome.attach(chrome: chrome, to: scrollView, edge: .top, in: host)
        let order = host.subviews
        #expect(order.firstIndex(of: scrollView)! < order.firstIndex(of: chrome)!)
    }

    @Test("retarget points the iOS 26 interaction at another scroll view")
    func retargetSwapsScrollView() {
        guard #available(iOS 26.0, *) else { return }
        let (host, first, chrome) = makeHost()
        ScrollEdgeChrome.attach(chrome: chrome, to: first, edge: .top, in: host)
        let second = UIScrollView(frame: host.bounds)
        host.addSubview(second)
        ScrollEdgeChrome.retarget(chrome: chrome, to: second, edge: .top)
        let interaction = chrome.interactions.compactMap { $0 as? UIScrollEdgeElementContainerInteraction }.first
        #expect(interaction?.scrollView === second)
        #expect(chrome.interactions.compactMap { $0 as? UIScrollEdgeElementContainerInteraction }.count == 1)
    }

    @Test("the fade covers the chrome plus the ramp, in the surface colour, on every OS")
    func fadeGeometryAndColor() throws {
        let (host, scrollView, chrome) = makeHost()
        let surface = UIColor.red
        let fade = ScrollEdgeChrome.attach(
            chrome: chrome, to: scrollView, edge: .top, in: host, fadeColor: surface
        )
        host.layoutIfNeeded()
        #expect(fade.frame.minY == 0)
        #expect(fade.frame.maxY == chrome.frame.maxY + ScrollEdgeFade.fadeLength)
        let gradient = try #require(fade.layer.sublayers?.first as? CAGradientLayer)
        let first = try #require((gradient.colors?.first).map { $0 as! CGColor })
        #expect(first.alpha == 1)
        #expect(UIColor(cgColor: first).cgColor.components?.first == 1, "red component = surface colour")

        // A short resting gap shortens the ramp so resting rows are not veiled.
        let (host2, scroll2, chrome2) = makeHost()
        let tight = ScrollEdgeChrome.attach(
            chrome: chrome2, to: scroll2, edge: .top, in: host2, restingGap: 8
        )
        host2.layoutIfNeeded()
        #expect(tight.frame.maxY == chrome2.frame.maxY + 8)
    }

    @Test("bottom edge strip hugs the host bottom and is touch transparent")
    func bottomEdgeStrip() {
        let (host, scrollView, _) = makeHost()
        let strip = ScrollEdgeChrome.attachBottomEdge(to: scrollView, in: host)
        host.layoutIfNeeded()
        #expect(strip.frame.maxY == host.bounds.maxY)
        #expect(strip.frame.height >= 24)
        #expect(strip.hitTest(CGPoint(x: 10, y: strip.bounds.midY), with: nil) == nil)
        if #available(iOS 26.0, *) {
            #expect(strip.interactions.contains { $0 is UIScrollEdgeElementContainerInteraction })
        }
    }

    @Test("clearTop / clearBottom keep the resting rows where they were and follow a resting offset")
    func restingInsets() {
        let (_, scrollView, _) = makeHost()
        scrollView.frame = CGRect(x: 0, y: 20, width: 400, height: 760)
        scrollView.contentSize = CGSize(width: 400, height: 3000)
        scrollView.contentOffset = .zero
        ScrollEdgeChrome.clearTop(of: scrollView, to: 120)
        #expect(scrollView.contentInset.top == 100, "120 - the 20 pt the scroll view already sits at")
        #expect(scrollView.contentOffset.y == -100, "a list resting at its top follows the inset")

        scrollView.contentOffset.y = 500
        ScrollEdgeChrome.clearTop(of: scrollView, to: 140)
        #expect(scrollView.contentInset.top == 120)
        #expect(scrollView.contentOffset.y == 500, "a scrolled list keeps its place")

        ScrollEdgeChrome.clearBottom(of: scrollView, to: 700)
        #expect(scrollView.contentInset.bottom == 80, "frame bottom 780 - chrome top 700")
    }

    // MARK: - Screens: the list runs under the chrome, resting layout intact

    @Test("Inbox list spans the page; the first row still rests below the pinned header")
    func inboxRunsUnderHeader() async throws {
        guard let inbox = await Self.liveInbox() else { print("[edge] shell not ready"); return }
        inbox.view.layoutIfNeeded()
        let header = try #require(Self.firstDescendant(of: inbox.view, of: HeaderView.self))
        let list = try #require(Self.firstDescendant(of: inbox.view, of: UICollectionView.self))
        #expect(list.frame.minY == inbox.view.bounds.minY, "the list starts at the top of the page")
        // Where the first row rests = list top + adjusted top inset.
        let restingTop = list.frame.minY + list.adjustedContentInset.top
        #expect(abs(restingTop - (header.frame.maxY + Spacing.xs)) < 0.5)
        #expect(list.frame.maxY == inbox.view.bounds.maxY)
    }

    @Test("Settings list runs under the title row and the bottom edge, resting layout intact")
    func settingsRunsUnderTitle() async throws {
        guard let context = await Self.liveUIContext() else { print("[edge] no context"); return }
        let controller = SettingsViewController(context: context)
        let window = Self.hostWindow(controller, size: CGSize(width: 402, height: 700))
        defer { TraitHostWindow.detach(window) }
        let list = try #require(Self.firstDescendant(of: controller.view, of: UICollectionView.self))
        let title = try #require(Self.firstLabel(in: controller.view, text: "Settings"))
        #expect(list.frame.minY == 0)
        #expect(list.frame.maxY == controller.view.bounds.maxY)
        let restingTop = list.frame.minY + list.adjustedContentInset.top
        #expect(abs(restingTop - (title.frame.maxY + Spacing.xs)) < 0.5)
        #expect(list.contentInset.bottom == Spacing.pageHeader, "the last row's resting gap is unchanged")
    }

    @Test("Chat list runs under the header and the composer, resting layout intact")
    func chatRunsUnderChrome() async throws {
        guard let context = await Self.liveUIContext() else { print("[edge] no context"); return }
        let conversation = ChatConversation(transport: SilentTransport())
        let controller = ChatViewController(
            context: context, episodeTitle: "Edge test", enclosureURL: "demo://edge",
            conversation: conversation
        )
        let window = Self.hostWindow(controller, size: CGSize(width: 402, height: 700))
        defer { TraitHostWindow.detach(window) }
        let list = try #require(Self.firstDescendant(of: controller.view, of: UICollectionView.self))
        let bar = try #require(Self.firstDescendant(of: controller.view, of: ChatInputBar.self))
        // The composer sits in the bottom chrome stack (with the example
        // questions above it on an empty thread); compare in the list's space.
        let chrome = try #require(bar.superview)
        let barFrame = bar.convert(bar.bounds, to: list.superview)
        let chromeFrame = chrome.convert(chrome.bounds, to: list.superview)
        // Header bar: the 64 pt row at the top of the page (safe area top).
        let headerBottom = list.frame.minY + list.adjustedContentInset.top
        #expect(headerBottom - list.frame.minY >= 64 - 0.5, "the list's top inset covers the 64 pt header")
        #expect(abs(list.frame.maxY - barFrame.maxY) < 0.5, "the list runs under the composer")
        let restingBottom = list.frame.maxY - list.adjustedContentInset.bottom
        #expect(abs(restingBottom - chromeFrame.minY) < 0.5, "the last row still rests on the bottom chrome")
    }

    @Test("iOS 26 tab shell lays a page-background fade behind the bars; its top tracks the bars")
    func shellBottomBarFade() async throws {
        guard let context = await Self.liveUIContext() else { print("[edge] no context"); return }
        let shell = MainTabBarController(context: context)
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        let window = scene.map { UIWindow(windowScene: $0) } ?? UIWindow(frame: UIScreen.main.bounds)
        window.rootViewController = shell
        window.isHidden = false
        defer {
            window.rootViewController = nil
            window.isHidden = true
        }
        guard #available(iOS 26.0, *) else {
            #expect(shell.bottomBarFade == nil, "iOS 18 keeps its capsule fade instead")
            return
        }
        for _ in 0..<4 {
            window.layoutIfNeeded()
            try await Task.sleep(for: .milliseconds(250))
        }
        let fade = try #require(shell.bottomBarFade)
        #expect(fade.superview === shell.view)
        #expect(fade.isUserInteractionEnabled == false)
        #expect(fade.frame.maxY == shell.view.bounds.maxY, "solid down to the screen bottom")

        // Stacking: tab content < fade < the container hosting the system bars.
        var barContainer: UIView? = shell.tabBar
        while let candidate = barContainer, candidate.superview !== shell.view { barContainer = candidate.superview }
        let order = shell.view.subviews
        let fadeIndex = try #require(order.firstIndex(of: fade))
        let barsIndex = try #require(barContainer.flatMap { order.firstIndex(of: $0) })
        #expect(fadeIndex < barsIndex, "the glass bars sit above the fade")
        #expect(fadeIndex > 0, "the fade sits above the page content")

        // The ramp ends exactly where the bars begin: the system's content
        // layout guide, which follows the accessory and the minimizing tab bar.
        let barsTop = shell.view.convert(shell.contentLayoutGuide.layoutFrame, from: shell.view).maxY
        #expect(abs(fade.frame.minY - (barsTop - ScrollEdgeFade.fadeLength)) < 0.5)
        #expect(barsTop <= shell.tabBar.frame.minY + 0.5, "never starts below the tab bar's top")
        if let accessory = shell.bottomAccessory {
            let accessoryTop = shell.view.convert(accessory.contentView.bounds, from: accessory.contentView).minY
            #expect(abs(barsTop - accessoryTop) < 0.5, "with the mini player up, the fade's top tracks the accessory's top")
        }
    }

    // MARK: - Helpers

    private final class SilentTransport: ChatTransport {
        func chat(
            enclosureURL: String, input: String, history: [[String: String]]
        ) async -> ChatTransportOutcome {
            .reply("ok")
        }
    }

    private static func hostWindow(_ controller: UIViewController, size: CGSize) -> UIWindow {
        controller.view.frame = CGRect(origin: .zero, size: size)
        let window = TraitHostWindow.attach(controller.view)
        window.frame = CGRect(origin: .zero, size: size)
        controller.view.layoutIfNeeded()
        // The scene window carries the status bar's safe area; a sheet's view
        // sits below it, so cancel it for the sheet-shaped screens.
        controller.additionalSafeAreaInsets.top = -controller.view.safeAreaInsets.top
        controller.view.setNeedsLayout()
        controller.view.layoutIfNeeded()
        controller.view.setNeedsLayout()
        controller.view.layoutIfNeeded()
        return window
    }

    private static func liveUIContext() async -> UIContext? {
        for _ in 0..<40 {
            if let context = (UIApplication.shared.delegate as? AppDelegate)?.environment.uiContext {
                return context
            }
            try? await Task.sleep(for: .milliseconds(500))
        }
        return nil
    }

    private static func liveInbox() async -> InboxPageViewController? {
        for _ in 0..<40 {
            let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            let root = scenes.flatMap(\.windows).compactMap(\.rootViewController).first { $0 is MainTabBarController }
            if let tabs = root as? MainTabBarController,
               let inbox = tabs.tabs.first?.viewController as? InboxPageViewController,
               inbox.isViewLoaded, inbox.view.window != nil {
                return inbox
            }
            try? await Task.sleep(for: .milliseconds(500))
        }
        return nil
    }

    private static func firstDescendant<T: UIView>(of view: UIView, of type: T.Type) -> T? {
        if let match = view as? T { return match }
        for subview in view.subviews {
            if let found = firstDescendant(of: subview, of: type) { return found }
        }
        return nil
    }

    private static func firstLabel(in view: UIView, text: String) -> UILabel? {
        if let label = view as? UILabel, label.text == text { return label }
        for subview in view.subviews {
            if let found = firstLabel(in: subview, text: text) { return found }
        }
        return nil
    }
}
