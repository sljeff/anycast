import XCTest

/// Minimal smoke (05 §6.2): the app launches and a window exists. The full
/// scripted pass (tabs → search → channel → play → …) arrives with the M3
/// screens; today the app surfaces the M1 placeholder RootViewController.
final class SmokeUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testLaunchShowsWindow() throws {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 10))
    }
}
