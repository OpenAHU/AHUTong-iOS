import XCTest

final class StartupScheduleUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    @MainActor
    func testSlowValidationDoesNotKeepSplashVisible() {
        let app = XCUIApplication()
        app.launchEnvironment["AHUTONG_CI_DISABLE_LIVE_PAYMENT"] = "1"
        app.launchArguments = ["--demo-consent", "--demo-session", "--demo-slow-session-validation"]
        app.launch()
        XCTAssertTrue(app.staticTexts["screen.home"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.otherElements["splash.android-parity"].exists)
        XCTAssertTrue(app.tabBars.firstMatch.exists)
    }

    @MainActor
    func testSelectedWeekSurvivesTabReentry() {
        let app = XCUIApplication()
        app.launchEnvironment["AHUTONG_CI_DISABLE_LIVE_PAYMENT"] = "1"
        app.launchArguments = ["--demo-consent", "--demo-session", "-schedule.preview-next", "NO", "-schedule.show-all", "NO"]
        app.launch()
        XCTAssertTrue(app.staticTexts["screen.home"].waitForExistence(timeout: 5))
        app.tabBars.buttons["课表"].tap()
        let secondWeek = app.buttons["schedule.week.2"]
        XCTAssertTrue(secondWeek.waitForExistence(timeout: 4))
        secondWeek.tap()
        XCTAssertTrue(secondWeek.isSelected)
        app.tabBars.buttons["设置"].tap()
        XCTAssertTrue(app.buttons["settings.preferences"].waitForExistence(timeout: 4))
        app.tabBars.buttons["课表"].tap()
        XCTAssertTrue(app.staticTexts["schedule.date.week.2.day.1"].waitForExistence(timeout: 4))
        XCTAssertTrue(secondWeek.isSelected)
        XCTAssertEqual(app.staticTexts["schedule.date.week.2.day.1"].label, "07-20")
        app.buttons["回到当前周"].tap()
        XCTAssertTrue(app.buttons["schedule.week.1"].isSelected)
    }

    @MainActor
    func testScheduleWeekSelectionUpdatesMatchingMondayDate() {
        let app = XCUIApplication()
        app.launchEnvironment["AHUTONG_CI_DISABLE_LIVE_PAYMENT"] = "1"
        // A preceding settings test can leave next-semester preview enabled.
        // This test needs the current semester's known date anchor.
        app.launchArguments = ["--demo-consent", "--demo-session", "-schedule.preview-next", "NO"]
        app.launch()
        XCTAssertTrue(app.staticTexts["screen.home"].waitForExistence(timeout: 5))
        app.tabBars.buttons["课表"].tap()
        let firstMonday = app.staticTexts["schedule.date.week.1.day.1"]
        XCTAssertTrue(firstMonday.waitForExistence(timeout: 4))
        XCTAssertEqual(firstMonday.label, "07-13")
        app.buttons["schedule.week.2"].tap()
        let nextMonday = app.staticTexts["schedule.date.week.2.day.1"]
        XCTAssertTrue(nextMonday.waitForExistence(timeout: 4))
        XCTAssertEqual(nextMonday.label, "07-20")
        app.buttons["回到当前周"].tap()
        XCTAssertTrue(firstMonday.waitForExistence(timeout: 4))
        XCTAssertEqual(firstMonday.label, "07-13")
    }
}
