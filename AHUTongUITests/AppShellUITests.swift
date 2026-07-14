import XCTest

final class AppShellUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testAndroidParityPrimaryScreens() {
        let app = XCUIApplication()
        app.launchArguments.append("--reset-onboarding")
        app.launch()

        XCTAssertTrue(app.staticTexts["onboarding.title"].waitForExistence(timeout: 5))
        capture("01-disclaimer", app: app)

        app.buttons["onboarding.decline"].tap()
        XCTAssertTrue(app.alerts["需要你的同意"].waitForExistence(timeout: 2))
        app.alerts.buttons["继续查看"].tap()

        app.buttons["onboarding.continue"].tap()
        XCTAssertTrue(app.otherElements["agreement.dialog.privacy"].waitForExistence(timeout: 2))
        capture("02-privacy", app: app)
        app.buttons["onboarding.continue"].tap()
        XCTAssertTrue(app.otherElements["agreement.dialog.community"].waitForExistence(timeout: 2))
        capture("03-community", app: app)
        app.buttons["onboarding.decline"].tap()

        XCTAssertTrue(app.otherElements["screen.home"].waitForExistence(timeout: 5))
        capture("04-home", app: app)

        let tabs = [
            ("schedule", "screen.schedule", "05-schedule"),
            ("tools", "screen.tools", "06-tools"),
            ("settings", "screen.settings", "07-settings"),
            ("home", "screen.home", "08-home-return")
        ]
        for (tabID, screenID, screenshotName) in tabs {
            let tab = app.buttons["tab.\(tabID)"]
            XCTAssertTrue(tab.waitForExistence(timeout: 2))
            tab.tap()
            XCTAssertTrue(app.otherElements[screenID].waitForExistence(timeout: 3))
            capture(screenshotName, app: app)
        }

        app.buttons["tab.tools"].tap()
        let routes = [
            ("tools.phone-book", "screen.phone-book", "09-phone-book"),
            ("tools.school-calendar", "screen.school-calendar", "10-school-calendar"),
            ("tools.weather", "screen.weather", "11-weather"),
            ("tools.study-repository", "screen.study-repository", "12-study-repository")
        ]

        for (linkID, screenID, screenshotName) in routes {
            let link = app.buttons[linkID]
            XCTAssertTrue(link.waitForExistence(timeout: 4))
            link.tap()
            XCTAssertTrue(app.otherElements[screenID].waitForExistence(timeout: 5))
            capture(screenshotName, app: app)
            edgeSwipeBack(app)
            XCTAssertTrue(app.otherElements["screen.tools"].waitForExistence(timeout: 3))
        }
    }

    @MainActor
    private func capture(_ name: String, app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "android-parity-\(name)"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor
    private func edgeSwipeBack(_ app: XCUIApplication) {
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.01, dy: 0.5))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5))
        start.press(forDuration: 0.05, thenDragTo: end, withVelocity: .fast, thenHoldForDuration: 0)
    }
}
