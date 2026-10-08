import XCTest

/// T0b shell smoke (05 §6.2, v2 pill bar per 09 §10 V2): pill tab
/// structure, tab switching, the search circle, the mini player (only
/// meaningful on a seeded simulator), and the player sheet with its
/// PageTab capsule. Runs unseeded — the mini-player step is guarded on
/// presence. Tab targets are the BottomTabBarView accessibility
/// identifiers (tab-0/1/2/tab-search), not system tab-bar buttons.
final class ShellNavigationUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testTabsSwitchAndMiniPlayerOpensPlayerSheet() throws {
        let app = XCUIApplication()
        app.launch()

        // The pill bar's three chips + the search circle install with the
        // startup DAG.
        let inboxTab = app.buttons["tab-0"]
        XCTAssertTrue(inboxTab.waitForExistence(timeout: 20), "pill tab bar did not install")
        XCTAssertTrue(app.buttons["tab-1"].exists, "queue chip missing")
        XCTAssertTrue(app.buttons["tab-2"].exists, "library chip missing")
        XCTAssertTrue(app.buttons["tab-search"].exists, "search circle missing")

        // Switch through every tab; children are prewarmed so this must
        // be instant (07 §2.1).
        app.buttons["tab-1"].tap()
        XCTAssertTrue(app.buttons["tab-1"].isSelected, "queue chip did not become selected")
        app.buttons["tab-2"].tap()
        XCTAssertTrue(app.buttons["tab-2"].isSelected, "library chip did not become selected")
        app.buttons["tab-0"].tap()
        XCTAssertTrue(app.buttons["tab-0"].isSelected, "Inbox chip did not become selected")

        // The search circle pushes the search entry sheet (09 §3.1).
        app.buttons["tab-search"].tap()
        let entryField = app.textFields["search-entry-field"]
        XCTAssertTrue(
            entryField.waitForExistence(timeout: 8),
            "search entry sheet did not open from the search circle"
        )
        // Dismiss in two phases. The entry sheet becomes first responder on
        // appear, so it opens at the LARGE detent (keyboard lifted): drag 1
        // pulls it back to medium and drops the keyboard; drag 2 crosses the
        // dismissal threshold. Both press points stay well above the v2
        // floating mini player capsule (~y 654-712) — a swipe whose press
        // lands on the capsule triggers its any-direction pan-open quirk
        // (03 §2.9) and presents the player sheet instead.
        func dismissEntrySheet() {
            let upper = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.25))
            let middle = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            let bottom = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.95))
            upper.press(forDuration: 0.05, thenDragTo: middle)
            usleep(600_000)
            middle.press(forDuration: 0.05, thenDragTo: bottom)
        }
        dismissEntrySheet()
        // Wait out the dismissal — tapping through a still-presented
        // medium sheet hits the sheet, not the mini player behind it.
        let dismissDeadline = Date().addingTimeInterval(4)
        while entryField.exists, Date() < dismissDeadline {
            usleep(300_000)
        }
        if entryField.exists {
            dismissEntrySheet()
        }

        // Mini player appears only when a queue was restored (db_smoke
        // seeding per native/README.md); skip visibly when unseeded.
        let miniPlayerTitle = app.staticTexts["mini-player-title"]
        try XCTSkipUnless(
            miniPlayerTitle.waitForExistence(timeout: 5),
            "mini player absent: simulator is not seeded with a restored queue (db_smoke); skipping mini-player/player-sheet steps"
        )
        miniPlayerTitle.tap()
        // A transient over the bottom chrome (the sheet dismissal's tail or
        // a playback-error toast) can eat the first tap — the capsule is
        // one-shot hittable-checked. Retry once before failing.
        let pageTabMain = app.buttons["player-page-tab-1"]
        var appeared = pageTabMain.waitForExistence(timeout: 3)
        if !appeared, miniPlayerTitle.waitForExistence(timeout: 2) {
            miniPlayerTitle.tap()
            appeared = pageTabMain.waitForExistence(timeout: 8)
        }
        XCTAssertTrue(
            appeared,
            "player sheet with PageTab capsule did not appear"
        )

        // Capsule taps switch pages; swipe-sync coverage arrives with the
        // real player pages (T4+).
        app.buttons["player-page-tab-0"].tap()
        XCTAssertTrue(app.buttons["player-page-tab-0"].isSelected)
    }
}
