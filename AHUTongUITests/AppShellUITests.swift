import XCTest

final class AppShellUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testPrimaryTabsAreReachable() {
        let app = XCUIApplication()
        app.launchArguments.append("--reset-onboarding")
        app.launch()

        XCTAssertTrue(app.staticTexts["onboarding.title"].waitForExistence(timeout: 5))
        app.buttons["onboarding.decline"].tap()
        XCTAssertTrue(app.alerts["需要你的同意"].waitForExistence(timeout: 2))
        app.alerts.buttons["继续查看"].tap()

        app.buttons["agreement.toggle.disclaimer"].tap()
        app.buttons["agreement.toggle.privacy"].tap()
        let continueButton = app.buttons["onboarding.continue"]
        expectation(
            for: NSPredicate(format: "isEnabled == true"),
            evaluatedWith: continueButton
        )
        waitForExpectations(timeout: 2)
        continueButton.tap()

        XCTAssertTrue(app.navigationBars["主页"].waitForExistence(timeout: 5))

        for title in ["课表", "小工具", "设置", "主页"] {
            let tab = app.tabBars.buttons[title]
            XCTAssertTrue(tab.exists)
            tab.tap()
            XCTAssertTrue(app.navigationBars[title].waitForExistence(timeout: 2))
        }

        app.tabBars.buttons["小工具"].tap()
        for route in [
            ("tools.phone-book", "校园电话本"),
            ("tools.school-calendar", "校历"),
            ("tools.weather", "天气"),
            ("tools.study-repository", "学习资料")
        ] {
            let link = app.buttons[route.0]
            XCTAssertTrue(link.waitForExistence(timeout: 2))
            link.tap()
            XCTAssertTrue(app.navigationBars[route.1].waitForExistence(timeout: 3))
            app.navigationBars.buttons.element(boundBy: 0).tap()
        }
    }
}
