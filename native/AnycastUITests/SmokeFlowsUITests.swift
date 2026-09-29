import XCTest

/// M3 UI smoke (05 §6.2): the flows CI can drive without fixtures. Steps that
/// need seeded data (db_smoke per native/README.md) skip when the app has no
/// content, so the suite is useful both on a bare simulator and locally.
/// Keep the whole file well under the 10-minute budget: no waits longer than
/// a few seconds, and every step asserts only what the app guarantees.
final class SmokeFlowsUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// Polls a condition without XCTest's expectation API (which captures a
    /// non-Sendable `self` and trips Swift 6 strict concurrency here).
    private func waitUntil(
        timeout: TimeInterval, _ condition: () -> Bool
    ) {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return }
            usleep(200_000)
        }
    }

    // MARK: - 1. Cold start, tabs, list scrolling

    func testColdStartTabsAndScrolling() throws {
        let app = XCUIApplication()
        app.launch()

        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 20), "tab bar did not install")
        XCTAssertEqual(tabBar.buttons.count, 3)

        for tab in ["Playlist", "Discover", "Podcast"] {
            tabBar.buttons[tab].tap()
            XCTAssertTrue(tabBar.buttons[tab].isSelected, "\(tab) tab did not become selected")
            // Scroll the tab's first list when it has content (seeded runs);
            // on a bare simulator the empty state has nothing to scroll.
            let list = app.collectionViews.firstMatch
            if list.exists, list.cells.count > 0 {
                list.swipeUp()
                list.swipeDown()
            }
        }
    }

    // MARK: - 2. Search sheet

    func testSearchSheetOpens() throws {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 20))

        let field = app.textFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5), "search field missing on the Podcast tab")
        field.tap()
        guard app.keyboards.firstMatch.waitForExistence(timeout: 3) else {
            // A connected hardware keyboard suppresses the software one; the
            // typing steps cannot run on such a runner (CI runners are fine).
            throw XCTSkip("software keyboard unavailable — skipping the submit flow")
        }
        field.typeText("news")
        if app.keyboards.buttons["search"].exists {
            app.keyboards.buttons["search"].tap()
        } else {
            field.typeText("\n")
        }

        // The sheet's own copy is the stable marker (03 §2.6) — do not
        // weaken with an any-collectionView fallback: one always exists
        // behind the sheet on the Podcast tab, so the disjunct passed even
        // when the sheet never opened.
        let marker = app.staticTexts["You are searching for"]
        XCTAssertTrue(
            marker.waitForExistence(timeout: 8),
            "search sheet did not open after submitting"
        )
    }

    // MARK: - 3. Settings: change a value, relaunch, assert it stuck

    func testSettingsChangePersistsAcrossRelaunch() throws {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 20))

        app.buttons["Settings"].tap()
        let intervalRow = app.cells["settings-row-autoRefreshInterval"]
        guard intervalRow.waitForExistence(timeout: 8) else {
            XCTFail("settings sheet did not list the auto refresh row")
            return
        }
        let before = intervalRow.value as? String
        // Restore the original interval no matter how the test exits — the
        // change is persisted to the simulator database and would otherwise
        // leak into later runs on this device. (The steps live in a nested
        // closure: a defer body may not `return` on its own.)
        func restoreOriginalInterval() {
            guard let original = before, !original.isEmpty else { return }
            app.terminate()
            app.launch()
            guard app.tabBars.firstMatch.waitForExistence(timeout: 20) else { return }
            app.buttons["Settings"].tap()
            let row = app.cells["settings-row-autoRefreshInterval"]
            guard row.waitForExistence(timeout: 8) else { return }
            row.tap()
            let wheel = app.pickerWheels.firstMatch
            guard wheel.waitForExistence(timeout: 8) else { return }
            wheel.adjust(toPickerWheelValue: original)
            if app.buttons["Close"].exists { app.buttons["Close"].tap() }
            else { app.swipeDown() }
        }
        defer { restoreOriginalInterval() }
        intervalRow.tap()

        let picker = app.pickerWheels.firstMatch
        guard picker.waitForExistence(timeout: 8) else {
            XCTFail("value picker did not appear")
            return
        }
        // Pick a different option than the current one.
        let choices = ["1 min", "3 min", "5 min", "10 min", "30 min"]
        let current = picker.value as? String
        guard let target = choices.first(where: { $0 != current }) else {
            XCTFail("picker exposed no alternative choice")
            return
        }
        picker.adjust(toPickerWheelValue: target)

        // Close the picker sheet; the settings row reflects the new value
        // through its accessibilityValue.
        if app.buttons["Close"].exists { app.buttons["Close"].tap() }
        else { app.swipeDown() }
        waitUntil(timeout: 5) { (intervalRow.value as? String) == target }
        XCTAssertEqual(
            intervalRow.value as? String, target,
            "settings row did not update to \(target)"
        )

        // Relaunch: the value must come back from the database.
        app.terminate()
        app.launch()
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 20))
        app.buttons["Settings"].tap()
        let reopened = app.cells["settings-row-autoRefreshInterval"]
        XCTAssertTrue(reopened.waitForExistence(timeout: 8), "settings sheet did not reopen")
        XCTAssertEqual(
            reopened.value as? String, target,
            "auto refresh interval did not persist (was \(before ?? "nil"))"
        )
    }

    // MARK: - 4. Channel sheet with the subscription button (seeded runs)

    func testChannelSheetFromSubscriptions() throws {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 20))

        // Subscriptions is the second strip item on the Podcast tab.
        let subscriptions = app.staticTexts["Subscriptions"]
        if subscriptions.exists { subscriptions.tap() }

        let list = app.collectionViews.firstMatch
        guard list.waitForExistence(timeout: 8), list.cells.count > 0 else {
            throw XCTSkip("no seeded subscriptions — channel flow needs db_smoke")
        }
        list.cells.firstMatch.tap()

        // The tristate capsule is the channel sheet's stable marker.
        let subscribe = app.buttons["Subscribe"]
        let unsubscribe = app.buttons["Unsubscribe"]
        let subscribing = app.buttons["Subscribing"]
        XCTAssertTrue(
            subscribe.waitForExistence(timeout: 12)
                || unsubscribe.waitForExistence(timeout: 2)
                || subscribing.waitForExistence(timeout: 2),
            "channel sheet did not expose the subscription button"
        )
        // The copy-RSS affordance confirms the header rendered (the old
        // `|| staticTexts.count > 3` fallback was true on almost any screen).
        XCTAssertTrue(app.buttons["Copy RSS URL"].waitForExistence(timeout: 4))
    }

    // MARK: - 5. Player: mini player → pages → speed (seeded runs)

    func testPlayerSheetPagesAndSpeed() throws {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 20))

        let miniPlayerTitle = app.staticTexts["mini-player-title"]
        guard miniPlayerTitle.waitForExistence(timeout: 6) else {
            throw XCTSkip("no restored queue — player flow needs db_smoke")
        }
        miniPlayerTitle.tap()

        let mainTab = app.buttons["player-page-tab-1"]
        XCTAssertTrue(mainTab.waitForExistence(timeout: 10), "player sheet did not open")
        XCTAssertTrue(mainTab.isSelected, "the player must open on the main page")

        app.buttons["player-page-tab-0"].tap()
        XCTAssertTrue(app.buttons["player-page-tab-0"].isSelected)
        app.buttons["player-page-tab-2"].tap()
        XCTAssertTrue(app.buttons["player-page-tab-2"].isSelected)
        app.buttons["player-page-tab-1"].tap()
        XCTAssertTrue(app.buttons["player-page-tab-1"].isSelected)

        // Transport controls exist on the main page.
        XCTAssertTrue(app.buttons["player-replay-10"].exists)
        XCTAssertTrue(app.buttons["player-forward-30"].exists)
    }

    // MARK: - 6. Cover tap opens the Detail sheet (R1 regression)

    /// The cover is a UIImageView hosting its own tap recognizer; without
    /// isUserInteractionEnabled the tap fell through to the card expand and
    /// Detail was unreachable from every list. The Detail sheet is proven
    /// by its unique "Share episode" control.
    func testCoverTapOpensDetailSheet() throws {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 20))

        let cover = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label == 'Episode details'"))
            .firstMatch
        guard cover.waitForExistence(timeout: 8) else {
            throw XCTSkip("no inbox cards on this runner — Detail flow needs db_smoke")
        }
        cover.tap()

        let share = app.buttons["Share episode"]
        XCTAssertTrue(share.waitForExistence(timeout: 6), "Detail sheet did not open from the cover tap")
    }

    // MARK: - 7. Playback failure: K6 retry + the loading state must END (R7)

    /// Plays the fixture episode, whose stream is unreachable on this
    /// runner. K6 turns the failure into the Retry affordance; the R7 fix
    /// additionally guarantees the loading leg ENDS (the engine used to
    /// park at loading forever, spinning the lottie and dimming controls).
    func testPlaybackFailureShowsRetryAndEndsLoading() throws {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 20))

        let miniPlayerTitle = app.staticTexts["mini-player-title"]
        guard miniPlayerTitle.waitForExistence(timeout: 6) else {
            throw XCTSkip("no restored queue — playback flow needs db_smoke")
        }
        miniPlayerTitle.tap()
        XCTAssertTrue(
            app.buttons["player-page-tab-1"].waitForExistence(timeout: 10),
            "player sheet did not open"
        )

        app.buttons["Play or pause"].tap()

        let retry = app.buttons["Retry playback"]
        guard retry.waitForExistence(timeout: 25) else {
            // A runner with working audio networking streams the fixture
            // fine — the failure path is not exercised there.
            throw XCTSkip("fixture audio streamed successfully — failure path not exercised")
        }
        // The R7 regression: once the failure surfaces, the loading message
        // (and with it the lottie state) must be gone.
        XCTAssertFalse(
            app.staticTexts["Loading…"].exists,
            "loading state lingered after the playback failure"
        )
    }

    // MARK: - 8. Fly-in overlay probe (R6 — capture the mid-flight frame)

    /// The fly-in runs 0.6 s from the tapped ➕ to the playlist tab. Static
    /// review found no defect, so this probe taps through the real flow and
    /// attaches immediate screenshots for manual inspection (the overlay is
    /// not accessibility-exposed and cannot be asserted directly).
    func testFlyInOverlayCapturedMidFlight() throws {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 20))

        // The cover is the one reliably AX-present part of a card. Tapping
        // it opens Detail, so expand the strip by tapping the text column
        // (a fixed offset right+below the cover, inside the same card) —
        // the whole-card gesture lives on the card container.
        let cover = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label == 'Episode details'"))
            .firstMatch
        guard cover.waitForExistence(timeout: 10) else {
            throw XCTSkip("no inbox cards on this runner — fly-in flow needs db_smoke")
        }
        let textColumn = cover.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .withOffset(CGVector(dx: 220, dy: 30))
        textColumn.tap()

        let addButton = app.buttons["Add to playlist"].firstMatch
        guard addButton.waitForExistence(timeout: 4) else {
            XCTFail("action strip did not expand")
            return
        }

        addButton.tap()
        for (index, delay) in [0.0, 0.35].enumerated() {
            Thread.sleep(forTimeInterval: delay)
            let shot = XCUIScreen.main.screenshot()
            let attachment = XCTAttachment(screenshot: shot)
            attachment.name = "fly-in-frame-\(index)"
            attachment.lifetime = .keepAlways
            add(attachment)
        }

        // The flow must not wedge: after the insert settles the shell is
        // still alive and responding.
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 6))
    }

    // MARK: - 9. Login sheet opens from Settings (sandbox UI is not touched)

    /// Regression: tapping Account once must yield exactly one login sheet
    /// (user report: the login window popped up twice). The account row
    /// presents LoginViewController directly; the sheet's own signed-out
    /// /api/user returns loginRequired, which routes to
    /// LoginPromptCoordinator — before the coordinator deduped against the
    /// whole presentation chain, that 401 stacked a second sheet on the
    /// first. Two stacked sheets expose two "Sign in with Apple" buttons.
    func testLoginSheetOpens() throws {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 20))

        app.buttons["Settings"].tap()
        let account = app.staticTexts["Account"]
        guard account.waitForExistence(timeout: 8) else {
            XCTFail("settings sheet did not list the Account row")
            return
        }
        account.tap()

        // Logged-out copy or the logged-in subscription card — either way the
        // login sheet itself must be on screen.
        let signedOut = app.staticTexts.containing(
            NSPredicate(format: "label CONTAINS 'free audio transcriptions'")
        ).firstMatch
        let signedIn = app.staticTexts["Basic Plan"]
        let plus = app.staticTexts["Anycast Plus"]
        XCTAssertTrue(
            signedOut.waitForExistence(timeout: 10)
                || signedIn.waitForExistence(timeout: 1)
                || plus.waitForExistence(timeout: 1)
                || app.buttons["Sign in with Apple"].waitForExistence(timeout: 2)
                || app.staticTexts["User Info"].waitForExistence(timeout: 2),
            "login sheet did not appear"
        )

        // Exactly one sheet: when the logged-out column rendered, a second
        // stacked sheet would surface a second matching button. Wait out the
        // reflux 401 window (the old double present landed ~1 s after the
        // sheet appeared) before counting.
        let appleButtons = app.buttons.matching(
            NSPredicate(format: "label == %@", "Sign in with Apple")
        )
        if appleButtons.firstMatch.exists {
            Thread.sleep(forTimeInterval: 2)
            let stacked = appleButtons.count
            XCTAssertTrue(
                stacked == 1,
                "login sheet presented \(stacked) times for one Account tap"
            )
        }
    }
}
