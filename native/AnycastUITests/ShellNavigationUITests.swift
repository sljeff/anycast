import XCTest

/// T0b shell smoke (05 §6.2): tab bar structure, tab switching, the mini
/// player (only meaningful on a seeded simulator), and the player sheet
/// with its PageTab capsule. Runs unseeded — the mini-player step is
/// guarded on presence.
final class ShellNavigationUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testTabsSwitchAndMiniPlayerOpensPlayerSheet() throws {
        let app = XCUIApplication()
        app.launch()

        // 3 tabs render after the startup DAG installs the shell.
        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 20), "tab bar did not install")
        XCTAssertEqual(tabBar.buttons.count, 3)

        // Switch through every tab; children are prewarmed so this must
        // be instant (07 §2.1).
        tabBar.buttons["Playlist"].tap()
        tabBar.buttons["Discover"].tap()
        tabBar.buttons["Podcast"].tap()

        // Mini player appears only when a queue was restored (db_smoke
        // seeding per native/README.md); skip visibly when unseeded.
        let miniPlayerTitle = app.staticTexts["mini-player-title"]
        try XCTSkipUnless(
            miniPlayerTitle.waitForExistence(timeout: 5),
            "mini player absent: simulator is not seeded with a restored queue (db_smoke); skipping mini-player/player-sheet steps"
        )
        miniPlayerTitle.tap()

        let pageTabMain = app.buttons["player-page-tab-1"]
        XCTAssertTrue(
            pageTabMain.waitForExistence(timeout: 10),
            "player sheet with PageTab capsule did not appear"
        )

        // Capsule taps switch pages; swipe-sync coverage arrives with the
        // real player pages (T4+).
        app.buttons["player-page-tab-0"].tap()
        XCTAssertTrue(app.buttons["player-page-tab-0"].isSelected)
    }
}
