import XCTest

final class AppShellUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testPrimaryTabsAreReachable() {
        let app = XCUIApplication()
        app.launch()

        XCTAssertTrue(app.navigationBars["主页"].waitForExistence(timeout: 5))

        for title in ["课表", "小工具", "设置", "主页"] {
            let tab = app.tabBars.buttons[title]
            XCTAssertTrue(tab.exists)
            tab.tap()
            XCTAssertTrue(app.navigationBars[title].waitForExistence(timeout: 2))
        }
    }
}
