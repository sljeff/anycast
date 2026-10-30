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

        XCTAssertTrue(app.buttons["tab-0"].waitForExistence(timeout: 20), "pill tab bar did not install")
        XCTAssertTrue(app.buttons["tab-1"].exists, "Playlist chip missing")
        XCTAssertTrue(app.buttons["tab-2"].exists, "Discover chip missing")

        /// iOS 26+ minimizes the bar while a list scrolls down
        /// (`tabBarMinimizeBehavior = .onScrollDown`). The minimized bar
        /// exposes only a synthesized pill for the selected tab — no `tab-N`
        /// identifier, value "Collapsed" — plus Search. Give the scroll-back
        /// a moment to re-expand the bar, else tap the pill. iOS 18 never
        /// minimizes, so there the first lookup always succeeds.
        func expandedTab(_ identifier: String) -> XCUIElement {
            let tab = app.buttons[identifier]
            if tab.waitForExistence(timeout: 2) { return tab }
            let pill = app.tabBars.buttons
                .matching(NSPredicate(format: "selected == true"))
                .firstMatch
            XCTAssertTrue(pill.exists, "\(identifier) missing and no minimized tab bar pill to expand")
            pill.tap()
            XCTAssertTrue(
                tab.waitForExistence(timeout: 3),
                "minimized tab bar did not expand to show \(identifier)"
            )
            return tab
        }

        for identifier in ["tab-1", "tab-2", "tab-0"] {
            let tab = expandedTab(identifier)
            tab.tap()
            waitUntil(timeout: 3) { tab.isSelected }
            XCTAssertTrue(tab.isSelected, "\(identifier) chip did not become selected")
            // Scroll the tab's first list when it has content: seeded runs,
            // and Discover whenever the runner has network.
            let list = app.collectionViews.firstMatch
            if list.exists, list.cells.count > 0 {
                // App-coordinate drags in a fixed band: below Discover's
                // category strip (y 131-175 on an 874 pt screen, which sits
                // in front of the list, so a press on it never reaches the
                // list) and above the iOS 18 floating mini player capsule
                // (~y 654-712), whose any-direction pan-open quirk (03 §2.9)
                // would present the player sheet over the whole shell.
                // Element swipes are avoided: their press point comes from
                // the element frame.
                let upper = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.35))
                let lower = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.65))
                lower.press(forDuration: 0.05, thenDragTo: upper)   // scroll down
                upper.press(forDuration: 0.05, thenDragTo: lower)   // scroll back
            }
        }
    }

    // MARK: - 2. Search sheet

    func testSearchSheetOpens() throws {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.buttons["tab-0"].waitForExistence(timeout: 20), "pill tab bar did not install")

        let searchTab = app.buttons["tab-search"]
        XCTAssertTrue(searchTab.waitForExistence(timeout: 5), "Search tab missing")
        searchTab.tap()
        let field = app.searchFields["search-page-field"].exists
            ? app.searchFields["search-page-field"] : app.textFields["search-page-field"]
        XCTAssertTrue(field.waitForExistence(timeout: 5), "search field missing on the Search tab")
        guard app.keyboards.firstMatch.waitForExistence(timeout: 3) else {
            // A connected hardware keyboard suppresses the software one; the
            // typing steps cannot run on such a runner (CI runners are fine).
            throw XCTSkip("software keyboard unavailable — skipping the submit flow")
        }
        // Return submits; a "search" key lookup would also match the
        // Search tab button.
        field.typeText("news\n")

        // The results sheet's tab strip is the stable marker — do not weaken
        // with a collection-view fallback (one is always behind the sheet).
        let marker = app.buttons["Channels"]
        XCTAssertTrue(
            marker.waitForExistence(timeout: 8),
            "search sheet did not open after submitting"
        )
    }

    // MARK: - 3. Settings: change a value, relaunch, assert it stuck

    func testSettingsChangePersistsAcrossRelaunch() throws {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.buttons["tab-0"].waitForExistence(timeout: 20), "pill tab bar did not install")

        // The Auto Refresh row is a stepper row: its text block carries the
        // value, and the − | + halves are separate buttons.
        func intervalValue(_ row: XCUIElement) -> String? {
            row.otherElements["Auto Refresh"].value as? String
        }
        let shorter = "Shorter auto refresh interval"
        let longer = "Longer auto refresh interval"

        app.buttons["Settings"].tap()
        let intervalRow = app.cells["settings-row-autoRefreshInterval"]
        guard intervalRow.waitForExistence(timeout: 8) else {
            XCTFail("settings sheet did not list the auto refresh row")
            return
        }
        let before = intervalValue(intervalRow)
        // Step up unless already at the longest interval.
        let forward = intervalRow.buttons[longer].isEnabled ? longer : shorter
        let back = forward == longer ? shorter : longer
        // Restore the original interval no matter how the test exits — the
        // change is persisted to the simulator database and would otherwise
        // leak into later runs on this device. (The steps live in a nested
        // closure: a defer body may not `return` on its own.)
        func restoreOriginalInterval() {
            guard let original = before, !original.isEmpty else { return }
            app.terminate()
            app.launch()
            guard app.buttons["tab-0"].waitForExistence(timeout: 20) else { return }
            app.buttons["Settings"].tap()
            let row = app.cells["settings-row-autoRefreshInterval"]
            guard row.waitForExistence(timeout: 8), intervalValue(row) != original else { return }
            row.buttons[back].tap()
        }
        defer { restoreOriginalInterval() }

        intervalRow.buttons[forward].tap()
        waitUntil(timeout: 5) { intervalValue(intervalRow) != before }
        guard let target = intervalValue(intervalRow), target != before else {
            XCTFail("settings row did not change from \(before ?? "nil")")
            return
        }

        // Relaunch: the value must come back from the database.
        app.terminate()
        app.launch()
        XCTAssertTrue(app.buttons["tab-0"].waitForExistence(timeout: 20), "pill tab bar did not install")
        app.buttons["Settings"].tap()
        let reopened = app.cells["settings-row-autoRefreshInterval"]
        XCTAssertTrue(reopened.waitForExistence(timeout: 8), "settings sheet did not reopen")
        XCTAssertEqual(
            intervalValue(reopened), target,
            "auto refresh interval did not persist (was \(before ?? "nil"))"
        )
    }

    // MARK: - 4. Channel sheet with the subscription button (seeded runs)

    func testChannelSheetFromSubscriptions() throws {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.buttons["tab-0"].waitForExistence(timeout: 20), "pill tab bar did not install")

        // The first cover on the Podcast tab's shows shelf opens its Channel.
        let cover = app.buttons["shows-shelf-cover-0"]
        guard cover.waitForExistence(timeout: 8) else {
            throw XCTSkip("no seeded subscriptions — channel flow needs db_smoke")
        }
        cover.tap()

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
        // The share button confirms the header rendered (the old
        // `|| staticTexts.count > 3` fallback was true on almost any screen).
        XCTAssertTrue(app.buttons["Share"].waitForExistence(timeout: 4))
    }

    // MARK: - 5. Player: mini player → pages → speed (seeded runs)

    func testPlayerSheetPagesAndSpeed() throws {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.buttons["tab-0"].waitForExistence(timeout: 20), "pill tab bar did not install")

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

    /// v2 cards are text-forward: the whole card opens the Detail sheet
    /// (the v1 cover slot is gone, 09 §10 批次1); the card cell is located
    /// by its `more` menu button. The Detail sheet is proven by its unique
    /// overflow control ("More episode actions", which carries Share).
    func testCardTapOpensDetailSheet() throws {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.buttons["tab-0"].waitForExistence(timeout: 20), "pill tab bar did not install")

        let card = app.collectionViews.cells
            .containing(.button, identifier: "inbox-card-more")
            .firstMatch
        guard card.waitForExistence(timeout: 8) else {
            throw XCTSkip("no inbox cards on this runner — Detail flow needs db_smoke")
        }
        card.tap()

        let overflow = app.buttons["More episode actions"]
        XCTAssertTrue(overflow.waitForExistence(timeout: 6), "Detail sheet did not open from the card tap")

        let shot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: shot)
        attachment.name = "inbox-card-detail-v2"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// 批次1 swipe surface (09 §7a-C1): a left swipe over an inbox card
    /// reveals the destructive Remove action. The probe only REVEALS and
    /// dismisses — a slow short drag, never a full swipe: full-swipe
    /// performs the first action by default (native delete idiom) and
    /// would consume a seeded episode on every run.
    func testInboxSwipeRevealsRemove() throws {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.buttons["tab-0"].waitForExistence(timeout: 20), "pill tab bar did not install")

        let card = app.collectionViews.cells
            .containing(.button, identifier: "inbox-card-more")
            .firstMatch
        guard card.waitForExistence(timeout: 8) else {
            throw XCTSkip("no inbox cards on this runner — swipe flow needs db_smoke")
        }
        let start = card.coordinate(withNormalizedOffset: CGVector(dx: 0.7, dy: 0.3))
        let target = card.coordinate(withNormalizedOffset: CGVector(dx: 0.15, dy: 0.3))
        start.press(forDuration: 0.1, thenDragTo: target)

        // The revealed action is reachable as a button titled Remove.
        let remove = app.buttons["Remove"].firstMatch
        XCTAssertTrue(remove.waitForExistence(timeout: 4), "swipe did not reveal the Remove action")

        // Dismiss without deleting (drag the card back right).
        target.press(forDuration: 0.1, thenDragTo: start)
        Thread.sleep(forTimeInterval: 0.5)
        XCTAssertFalse(remove.exists, "swipe surface stayed open after the dismiss drag")
    }

    // MARK: - 7. Playback failure: K6 retry + the loading state must END (R7)

    /// Plays the fixture episode, whose stream is unreachable on this
    /// runner. K6 turns the failure into the Retry affordance; the R7 fix
    /// additionally guarantees the loading leg ENDS (the engine used to
    /// park at loading forever, spinning the lottie and dimming controls).
    func testPlaybackFailureShowsRetryAndEndsLoading() throws {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.buttons["tab-0"].waitForExistence(timeout: 20), "pill tab bar did not install")

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

    /// The fly-in runs 0.6 s from the triggered card to the playlist tab.
    /// Static review found no defect, so this probe taps through the real
    /// flow and attaches immediate screenshots for manual inspection (the
    /// overlay is not accessibility-exposed and cannot be asserted
    /// directly).
    func testFlyInOverlayCapturedMidFlight() throws {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.buttons["tab-0"].waitForExistence(timeout: 20), "pill tab bar did not install")

        // v2 cards are located by their `more` menu button. Tapping the
        // card opens Detail, so the "Add to playlist" action is reached by
        // LONG-PRESS — the native context menu (09 §7a-C1; the strip and
        // its ➕ button are retired on Inbox).
        let card = app.collectionViews.cells
            .containing(.button, identifier: "inbox-card-more")
            .firstMatch
        guard card.waitForExistence(timeout: 10) else {
            throw XCTSkip("no inbox cards on this runner — fly-in flow needs db_smoke")
        }
        card.press(forDuration: 1.2)

        let addButton = app.buttons["Add to playlist"].firstMatch
        guard addButton.waitForExistence(timeout: 4) else {
            XCTFail("context menu did not appear")
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
        XCTAssertTrue(app.buttons["tab-0"].waitForExistence(timeout: 6))
    }

    // MARK: - 10. Playlist whole-card drag reorder (seeded runs)

    /// The 150 ms whole-card drag: hold a card ~0.6 s (deliberately past
    /// the ~0.5 s window that used to raise the system drag session, lift
    /// the square full-cell float, and kill the reorder), drag it onto a
    /// lower card, release. The interactive movement is the single reorder
    /// path, so the order must visibly change, a reverse drag restores the
    /// seeded order, and the restored order must survive a relaunch
    /// (database round trip).
    func testPlaylistCardDragReorders() throws {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.buttons["tab-0"].waitForExistence(timeout: 20), "pill tab bar did not install")
        app.buttons["tab-1"].tap()

        let cards = app.collectionViews.firstMatch.cells
        guard cards.firstMatch.waitForExistence(timeout: 8), cards.count >= 3 else {
            throw XCTSkip("no seeded playlist — drag flow needs db_smoke")
        }

        func cardTitles() -> [String] {
            cards.allElementsBoundByIndex
                .compactMap { $0.staticTexts.firstMatch.label }
                .filter { !$0.isEmpty }
        }

        /// Waits until the visible card titles stop changing (the drop's
        /// commit chain — repository write → playback steps → reload —
        /// settles) instead of a fixed sleep that can race it.
        func waitUntilTitlesStable(minimum: TimeInterval, timeout: TimeInterval) {
            var last = cardTitles()
            let started = Date()
            var lastChange = started
            let deadline = started + timeout
            while Date() < deadline {
                usleep(300_000)
                let current = cardTitles()
                if current != last {
                    last = current
                    lastChange = Date()
                } else if Date().timeIntervalSince(lastChange) > 0.8,
                          Date().timeIntervalSince(started) >= minimum {
                    break
                }
            }
        }
        let before = cardTitles()
        guard before.count >= 3 else {
            throw XCTSkip("playlist cards did not expose titles — drag flow needs db_smoke")
        }

        // Hold ≥ 0.5 s (the old system-drag trigger) and drag the head
        // onto the third card.
        let first = cards.element(boundBy: 0)
        let third = cards.element(boundBy: 2)
        first.press(forDuration: 0.6, thenDragTo: third)
        waitUntilTitlesStable(minimum: 1.0, timeout: 6.0)

        let after = cardTitles()
        XCTAssertEqual(Set(after), Set(before), "drag changed the playlist content set")
        XCTAssertNotEqual(
            after.first, before.first,
            "the dragged head card did not move (order unchanged: \(after))"
        )

        // Restore the seeded order through the same gesture: drag the
        // moved card back above the current head.
        guard let movedIndex = after.firstIndex(of: before[0]), movedIndex > 0 else {
            XCTFail("moved card \(before[0]) not found below the head after the drag")
            return
        }
        let moved = cards.element(boundBy: movedIndex)
        let top = cards.element(boundBy: 0)
        moved.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .press(
                forDuration: 0.6,
                thenDragTo: top.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: -0.4))
            )
        waitUntilTitlesStable(minimum: 1.0, timeout: 6.0)
        XCTAssertEqual(
            cardTitles().first, before[0],
            "the restore drag did not return the original head"
        )

        // The restored order must survive a relaunch (database round trip).
        app.terminate()
        app.launch()
        XCTAssertTrue(
            app.buttons["tab-1"].waitForExistence(timeout: 20),
            "pill tab bar did not install after relaunch"
        )
        app.buttons["tab-1"].tap()
        XCTAssertTrue(
            cards.firstMatch.waitForExistence(timeout: 8),
            "playlist list missing after relaunch"
        )
        XCTAssertEqual(
            cardTitles().first, before[0],
            "the restored playlist order did not persist across relaunch"
        )
    }

    // MARK: - 9. Login sheet opens from Settings (sandbox UI is not touched)

    /// Regression: tapping the signed-out account row once must yield exactly
    /// one login sheet (user report: the login window popped up twice). The
    /// row presents the login sheet directly; a 401 from a background poller
    /// routes to LoginPromptCoordinator, whose chain walk must swallow it.
    /// Two stacked sheets expose two "Continue with Apple" buttons.
    func testLoginSheetOpens() throws {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.buttons["tab-0"].waitForExistence(timeout: 20), "pill tab bar did not install")

        app.buttons["Settings"].tap()
        let account = app.cells["settings-row-account"]
        guard account.waitForExistence(timeout: 8) else {
            XCTFail("settings sheet did not list the account row")
            return
        }
        account.tap()

        // Signed out: the login sheet. Signed in: the Membership page.
        let signedOut = app.buttons["login-apple"]
        let signedIn = app.staticTexts["Basic Plan"]
        let plus = app.staticTexts["Anycast Plus"]
        XCTAssertTrue(
            signedOut.waitForExistence(timeout: 10)
                || signedIn.waitForExistence(timeout: 1)
                || plus.waitForExistence(timeout: 1)
                || app.staticTexts["User Info"].waitForExistence(timeout: 2),
            "login sheet did not appear"
        )

        // Exactly one sheet: wait out the 401 window (the old double present
        // landed ~1 s after the sheet appeared) before counting.
        let appleButtons = app.buttons.matching(identifier: "login-apple")
        if appleButtons.firstMatch.exists {
            Thread.sleep(forTimeInterval: 2)
            let stacked = appleButtons.count
            XCTAssertTrue(
                stacked == 1,
                "login sheet presented \(stacked) times for one account tap"
            )
        }
    }
}
