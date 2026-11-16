import XCTest

extension XCUIApplication {

    /// Launches onto the tab shell. A fresh simulator would otherwise open
    /// on the first-launch onboarding, which covers everything these tests
    /// drive. The argument domain sets the `onboarding.completed` default
    /// for this launch only; nothing is written to the app's defaults.
    func launchPastOnboarding() {
        if !launchArguments.contains("-onboarding.completed") {
            launchArguments += ["-onboarding.completed", "YES"]
        }
        launch()
    }
}
