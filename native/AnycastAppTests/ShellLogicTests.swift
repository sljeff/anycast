import Foundation
import Testing
@testable import Anycast

/// T0b shell logic: the pure pieces of the tab shell, mini player, player
/// pager, and URL routing (docs/migration/05 §6.3 P0 anchors).
@MainActor
struct ShellLogicTests {

    // MARK: - PageTab selection state machine (03 §2.10)

    @Test("Player page selection starts on the main page and clamps")
    func pageSelectionBounds() {
        let selection = PlayerPageSelection(pageCount: 3)
        #expect(selection.selectedIndex == 1)

        #expect(selection.select(0) == true)
        #expect(selection.selectedIndex == 0)
        #expect(selection.select(2) == true)
        #expect(selection.selectedIndex == 2)

        // Out-of-range taps clamp to the boundaries, not crash. Clamping
        // onto the current index reports no change.
        #expect(selection.select(7) == false)
        #expect(selection.selectedIndex == 2)
        #expect(selection.select(-3) == true)
        #expect(selection.selectedIndex == 0)

        // Same-index selection reports no change.
        #expect(selection.select(0) == false)
        #expect(selection.selectedIndex == 0)
    }

    @Test("Player page selection resets to the initial page on close (PopScope quirk)")
    func pageSelectionReset() {
        let selection = PlayerPageSelection(pageCount: 3)
        selection.select(0)
        selection.reset()
        #expect(selection.selectedIndex == 1)

        // A non-default initial index resets to itself.
        let custom = PlayerPageSelection(pageCount: 3, initialIndex: 2)
        custom.select(0)
        custom.reset()
        #expect(custom.selectedIndex == 2)
    }

    // MARK: - Tab0 re-tap decision (03 §1.1)

    @Test("Tab0 re-tap: at top or no client refreshes, otherwise scrolls to top")
    func tabZeroRetap() {
        // No scroll client → refresh (bottom_nav_bar.dart:264-266).
        #expect(TabZeroRetap.action(hasClient: false, isAtTop: false) == .refresh)
        #expect(TabZeroRetap.action(hasClient: false, isAtTop: true) == .refresh)
        // At top → refresh.
        #expect(TabZeroRetap.action(hasClient: true, isAtTop: true) == .refresh)
        // Scrolled → 300 ms scroll-to-top.
        #expect(TabZeroRetap.action(hasClient: true, isAtTop: false) == .scrollToTop)
    }

    // MARK: - Mini player visibility (03 §2.9)

    @Test("Mini player collapses only when the queue is empty")
    func miniPlayerVisibility() {
        #expect(MiniPlayerVisibility.isVisible(queueCount: 0) == false)
        #expect(MiniPlayerVisibility.isVisible(queueCount: 1) == true)
        #expect(MiniPlayerVisibility.isVisible(queueCount: 12) == true)
    }

    // MARK: - Mini player time text (getPlayedAndTotalTime parity)

    @Test("Played/total text matches the Dart formatter")
    func playedAndTotalText() {
        #expect(PlayerBarView.playedAndTotalText(playedMilliseconds: 0, totalMilliseconds: 0) == "0:00 / 0:00")
        #expect(
            PlayerBarView.playedAndTotalText(playedMilliseconds: 75_000, totalMilliseconds: 3_661_000)
                == "1:15 / 61:01"
        )
        #expect(
            PlayerBarView.playedAndTotalText(playedMilliseconds: 604_999, totalMilliseconds: 605_000)
                == "10:04 / 10:05"
        )
    }
}

/// URL scheme dispatch (docs/migration/08 §12.2) — the pure classification.
@MainActor
struct URLRouterTests {

    private let router = URLRouter(bundleIdentifier: "com.kindjeff.anycast")

    private func url(_ string: String) -> URL {
        URL(string: string) ?? URL(fileURLWithPath: "/")
    }

    @Test("ShareMedia scheme routes to the share handoff")
    func shareMediaScheme() {
        #expect(router.classify(url("ShareMedia-com.kindjeff.anycast:/share?id=1")) == .shareHandoff)
        // Scheme comparison is case-insensitive.
        #expect(router.classify(url("sharemedia-com.kindjeff.anycast:/x")) == .shareHandoff)
        // A different bundle id is not ours.
        #expect(router.classify(url("ShareMedia-com.other.app:/x")) == .unhandled)
    }

    @Test("Google reverse-client schemes route to GIDSignIn")
    func googleSignInScheme() {
        #expect(
            router.classify(url("com.googleusercontent.apps.1092551717876-abc:/oauth2code?code=1"))
                == .googleSignIn
        )
    }

    @Test("Everything else is unhandled")
    func unhandledSchemes() {
        #expect(router.classify(url("https://anycast.website/player")) == .unhandled)
        #expect(router.classify(url("mailto:support@example.com")) == .unhandled)
    }
}
