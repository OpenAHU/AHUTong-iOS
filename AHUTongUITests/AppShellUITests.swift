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

        XCTAssertTrue(app.staticTexts["onboarding.title"].waitForExistence(timeout: 8))
        capture("01-disclaimer", app: app)

        app.buttons["onboarding.decline"].tap()
        XCTAssertTrue(app.alerts["需要你的同意"].waitForExistence(timeout: 2))
        app.alerts.buttons["继续查看"].tap()

        app.buttons["onboarding.continue"].tap()
        XCTAssertTrue(app.staticTexts["隐私政策"].waitForExistence(timeout: 2))
        capture("02-privacy", app: app)
        app.buttons["onboarding.continue"].tap()
        XCTAssertTrue(app.staticTexts["商业合作"].waitForExistence(timeout: 2))
        capture("03-community", app: app)
        app.buttons["onboarding.decline"].tap()

        XCTAssertTrue(app.staticTexts["screen.home"].waitForExistence(timeout: 5))
        capture("04-home", app: app)

        let tabs = [
            ("schedule", "05-schedule"),
            ("tools", "06-tools"),
            ("settings", "07-settings"),
            ("home", "08-home-return")
        ]
        for (tabID, screenshotName) in tabs {
            let tab = app.buttons["tab.\(tabID)"]
            XCTAssertTrue(tab.waitForExistence(timeout: 2))
            tab.tap()
            switch tabID {
            case "schedule": XCTAssertTrue(app.buttons["回到当前周"].waitForExistence(timeout: 3))
            case "tools": XCTAssertTrue(app.buttons["tools.phone-book"].waitForExistence(timeout: 3))
            case "settings": XCTAssertTrue(app.buttons["settings.preferences"].waitForExistence(timeout: 3))
            default: XCTAssertTrue(app.staticTexts["screen.home"].waitForExistence(timeout: 3))
            }
            capture(screenshotName, app: app)
        }

        app.buttons["tab.tools"].tap()
        let routes = [
            ("tools.phone-book", "搜索电话或部门", "09-phone-book"),
            ("tools.school-calendar", "school-calendar.", "10-school-calendar"),
            ("tools.weather", "天气设置", "11-weather"),
            ("tools.study-repository", "repository.downloads", "12-study-repository")
        ]

        for (linkID, marker, screenshotName) in routes {
            let link = app.buttons[linkID]
            XCTAssertTrue(link.waitForExistence(timeout: 4))
            link.tap()
            if marker == "school-calendar." {
                let calendarState = app.descendants(matching: .any)
                    .matching(NSPredicate(format: "identifier BEGINSWITH %@", marker))
                    .firstMatch
                XCTAssertTrue(calendarState.waitForExistence(timeout: 5))
            } else {
                XCTAssertTrue(app.buttons[marker].waitForExistence(timeout: 5))
            }
            capture(screenshotName, app: app)
            edgeSwipeBack(app)
            XCTAssertTrue(app.buttons["tools.phone-book"].waitForExistence(timeout: 3))
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
