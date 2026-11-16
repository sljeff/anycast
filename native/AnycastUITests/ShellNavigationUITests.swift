import XCTest

/// Shell smoke: primary destinations, Podcast's inner tabs, header search,
/// and the mini player (only
/// meaningful on a seeded simulator), and the player sheet with its
/// PageTab capsule. Runs unseeded — the mini-player step is guarded on
/// presence. Tab targets are the BottomTabBarView accessibility
/// identifiers (tab-0/1/2), not system tab-bar buttons.
final class ShellNavigationUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testTabsSwitchAndMiniPlayerOpensPlayerSheet() throws {
        let app = XCUIApplication()
        app.launch()

        // The pill bar's three primary destinations install with startup.
        let inboxTab = app.buttons["tab-0"]
        XCTAssertTrue(inboxTab.waitForExistence(timeout: 20), "pill tab bar did not install")
        XCTAssertTrue(app.buttons["tab-1"].exists, "Playlist chip missing")
        XCTAssertTrue(app.buttons["tab-2"].exists, "Discover chip missing")
        let searchTab = app.buttons["tab-search"]
        XCTAssertTrue(searchTab.exists, "Search tab missing")

        // The Podcast tab is the Inbox; with subscriptions its shows shelf
        // ends in the All shows button, which opens the Shows sheet.
        let allShows = app.buttons["shows-shelf-all"]
        if allShows.waitForExistence(timeout: 8) {
            allShows.tap()
            XCTAssertTrue(
                app.staticTexts["library-sheet-title"].waitForExistence(timeout: 4),
                "All shows did not open the Shows sheet"
            )
            app.swipeDown()
            XCTAssertTrue(inboxTab.waitForExistence(timeout: 4))
            // A plain swipe sometimes scrolls the sheet's grid instead of
            // dragging the sheet; when it did not dismiss, drag the
            // grabber band (just above the title) down past the bottom.
            let sheetTitle = app.staticTexts["library-sheet-title"]
            if sheetTitle.exists {
                let grab = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0))
                    .withOffset(CGVector(dx: 0, dy: sheetTitle.frame.minY - 8))
                let bottom = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.95))
                grab.press(forDuration: 0.1, thenDragTo: bottom)
            }
            // Wait out the dismissal: a chip tapped under the sheet's
            // disappearing view never receives the touch.
            let dismissed = Date().addingTimeInterval(4)
            while sheetTitle.exists && Date() < dismissed {
                Thread.sleep(forTimeInterval: 0.1)
            }
            XCTAssertFalse(sheetTitle.exists, "Shows sheet did not dismiss")
        }

        // Switch through every tab; children are prewarmed so this must
        // be instant (07 §2.1). The chip's selected flag lands a beat
        // after the tap when the run is busy, and a transient over the
        // bottom chrome can eat a first tap outright — so poll for the
        // selection and retry the tap once.
        func selected(_ identifier: String) -> Bool {
            let chip = app.buttons[identifier]
            let deadline = Date().addingTimeInterval(3)
            while Date() < deadline {
                if chip.isSelected { return true }
                Thread.sleep(forTimeInterval: 0.1)
            }
            return chip.isSelected
        }
        func tapAndSelect(_ identifier: String, _ message: String) {
            let chip = app.buttons[identifier]
            chip.tap()
            if !selected(identifier) {
                chip.tap()
                XCTAssertTrue(selected(identifier), message)
            }
        }
        tapAndSelect("tab-1", "Playlist chip did not become selected")
        tapAndSelect("tab-2", "Discover chip did not become selected")
        tapAndSelect("tab-0", "Inbox chip did not become selected")

        // The Search tab opens in its entry state with the field focused;
        // submitting runs the search on the same page.
        searchTab.tap()
        let field = app.searchFields["search-page-field"].exists
            ? app.searchFields["search-page-field"] : app.textFields["search-page-field"]
        XCTAssertTrue(field.waitForExistence(timeout: 8), "search field missing on the Search tab")
        guard app.keyboards.firstMatch.waitForExistence(timeout: 3) else {
            throw XCTSkip("software keyboard unavailable — skipping search submission")
        }
        field.typeText("news\n")
        XCTAssertTrue(app.buttons["Channels"].waitForExistence(timeout: 8), "search results did not appear")
        // While search is active the bar collapses to one unnamed tab
        // button; closing search brings the full bar back asynchronously,
        // so wait for the chip instead of tapping into the collapsed bar.
        app.buttons["Close"].tap()
        XCTAssertTrue(app.buttons["tab-0"].waitForExistence(timeout: 3), "full tab bar did not come back after Close")
        tapAndSelect("tab-0", "Podcast tab did not come back")

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
