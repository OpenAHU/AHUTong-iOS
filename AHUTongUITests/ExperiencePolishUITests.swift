import XCTest

@MainActor
final class ExperiencePolishUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["AHUTONG_CI_DISABLE_LIVE_PAYMENT"] = "1"
        app.launchArguments = ["--demo-consent", "--demo-session", "-schedule.preview-next", "NO"]
        app.launch()
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 8))
        return app
    }

    func testSettingsTabReturnsToRootAfterLeavingDetailViaShortcut() {
        let app = launch()
        app.tabBars.buttons["设置"].tap()
        app.buttons["settings.preferences"].tap()
        XCTAssertTrue(app.switches["preferences.privacy-consent"].waitForExistence(timeout: 4))
        // Detail screens intentionally hide the tab bar; a shortcut can leave
        // their navigation stack alive while returning to a top-level tab.
        app.open(URL(string: "ahutong://schedule")!)
        XCTAssertTrue(app.buttons["回到当前周"].waitForExistence(timeout: 4))
        app.tabBars.buttons["设置"].tap()
        XCTAssertTrue(app.buttons["settings.account-login"].waitForExistence(timeout: 4))
        app.tabBars.buttons["设置"].tap()
        XCTAssertTrue(app.buttons["settings.account-login"].waitForExistence(timeout: 4))
        capture(app, "settings-tab-root")
    }

    func testWeekIndicatorsAreCirclesForSingleAndDoubleDigits() {
        let app = launch()
        app.tabBars.buttons["课表"].tap()
        let first = app.buttons["schedule.week.1"]
        XCTAssertTrue(first.waitForExistence(timeout: 4))
        XCTAssertEqual(first.frame.width, first.frame.height, accuracy: 1)
        capture(app, "schedule-circle-week-1")
        let tenth = app.buttons["schedule.week.10"]
        // Each selection centers its circle in the horizontal selector.
        for week in [5, 7, 9, 10] {
            let indicator = app.buttons["schedule.week.\(week)"]
            XCTAssertTrue(indicator.isHittable)
            indicator.tap()
        }
        XCTAssertTrue(tenth.isSelected)
        XCTAssertEqual(tenth.frame.width, tenth.frame.height, accuracy: 1)
        capture(app, "schedule-circle-week-10")
    }

    func testCampusCodeExpandsWithLargerSquareAndCollapses() {
        let app = launch()
        let balance = app.buttons["campus-card.balance"]
        XCTAssertTrue(balance.waitForExistence(timeout: 5))
        let collapsedHeight = balance.frame.height
        balance.tap()
        let code = app.buttons["campus-card.qr-refresh"]
        XCTAssertTrue(code.waitForExistence(timeout: 5))
        XCTAssertGreaterThan(code.frame.width, 138)
        XCTAssertEqual(code.frame.width, code.frame.height, accuracy: 1)
        XCTAssertGreaterThan(app.otherElements["campus-card.qr-panel"].frame.height, collapsedHeight)
        capture(app, "home-campus-code-expanded")
        app.buttons["campus-card.qr-collapse"].tap()
        XCTAssertTrue(balance.waitForExistence(timeout: 4))
        XCTAssertEqual(balance.frame.height, collapsedHeight, accuracy: 1)
    }

    func testDeveloperPopoverDismissalResumesItsRowAndDoubleTapOpensQQ() {
        let app = launch()
        app.tabBars.buttons["设置"].tap()
        let entry = app.buttons["settings.contributors"]
        if !entry.isHittable { app.swipeUp() }
        entry.tap()
        XCTAssertTrue(app.otherElements["contributors.row.0"].waitForExistence(timeout: 4))
        let row = app.otherElements["contributors.row.0"]
        let avatar = row.buttons.allElementsBoundByIndex.first { $0.isHittable }
        XCTAssertNotNil(avatar)
        avatar?.tap()
        XCTAssertTrue(app.otherElements["contributors.detail"].waitForExistence(timeout: 4))
        XCTAssertTrue(app.buttons["contributors.detail.close"].exists)
        XCTAssertEqual(row.value as? String, "已暂停")
        XCTAssertEqual(app.otherElements["contributors.row.1"].value as? String, "向右滚动")
        XCTAssertFalse(app.buttons["contributors.resume.0"].exists)
        XCTAssertFalse(app.buttons["contributors.resume.1"].exists)
        capture(app, "contributors-native-popover")
        app.buttons["contributors.detail.close"].tap()
        XCTAssertTrue(app.otherElements["contributors.detail"].waitForNonExistence(timeout: 4))
        expectation(for: NSPredicate(format: "value == %@", "向左滚动"), evaluatedWith: row)
        waitForExpectations(timeout: 4)
        XCTAssertEqual(app.otherElements["contributors.row.1"].value as? String, "向右滚动")
        let currentAvatar = row.buttons.allElementsBoundByIndex.first { $0.isHittable }
        XCTAssertNotNil(currentAvatar)
        currentAvatar?.doubleTap()
        XCTAssertTrue(app.alerts["打开 QQ"].waitForExistence(timeout: 4))
        app.alerts.buttons["知道了"].tap()
        capture(app, "contributors-two-rows")
    }

    private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
