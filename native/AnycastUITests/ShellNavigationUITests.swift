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
        let searchButton = app.buttons["header-search"]
        XCTAssertTrue(searchButton.exists, "header search button missing")

        let inboxSection = app.buttons["podcast-section-0"]
        let subscriptionsSection = app.buttons["podcast-section-1"]
        XCTAssertTrue(inboxSection.exists, "Podcast Inbox section missing")
        XCTAssertTrue(subscriptionsSection.exists, "Podcast Subscriptions section missing")
        subscriptionsSection.tap()
        XCTAssertTrue(subscriptionsSection.isSelected, "Subscriptions section did not become selected")
        inboxSection.tap()
        XCTAssertTrue(inboxSection.isSelected, "Inbox section did not become selected")

        // Switch through every tab; children are prewarmed so this must
        // be instant (07 §2.1).
        app.buttons["tab-1"].tap()
        XCTAssertTrue(app.buttons["tab-1"].isSelected, "Playlist chip did not become selected")
        app.buttons["tab-2"].tap()
        XCTAssertTrue(app.buttons["tab-2"].isSelected, "Discover chip did not become selected")
        app.buttons["tab-0"].tap()
        XCTAssertTrue(app.buttons["tab-0"].isSelected, "Inbox chip did not become selected")

        // The header button opens the search sheet in its entry state with
        // the field focused; submitting runs the search in the same sheet.
        searchButton.tap()
        let sheetField = app.textFields["search-page-field"]
        XCTAssertTrue(sheetField.waitForExistence(timeout: 8), "search sheet did not open")
        guard app.keyboards.firstMatch.waitForExistence(timeout: 3) else {
            throw XCTSkip("software keyboard unavailable — skipping search submission")
        }
        sheetField.typeText("news\n")
        XCTAssertTrue(app.buttons["Channels"].waitForExistence(timeout: 8), "search results did not appear")
        // Swipe the sheet down to close it.
        sheetField.swipeDown(velocity: .fast)
        XCTAssertTrue(
            sheetField.waitForNonExistence(timeout: 4),
            "search results sheet did not close"
        )

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
