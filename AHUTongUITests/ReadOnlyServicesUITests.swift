import XCTest
final class ReadOnlyServicesUITests: XCTestCase {
    @MainActor
    func testProgramAndBillingReadOnlyNavigation() {
        let app = XCUIApplication()
        app.launchEnvironment["AHUTONG_CI_DISABLE_LIVE_PAYMENT"] = "1"
        app.launchArguments = ["--demo-consent", "--demo-session"]
        app.launch()
        app.tabBars.buttons["小工具"].tap()
        app.revealTool("tools.program-completion").tap()
        XCTAssertTrue(app.otherElements["program-completion.screen"].waitForExistence(timeout: 5) || app.collectionViews["program-completion.screen"].exists)
        XCTAssertTrue(app.staticTexts["完成进度"].waitForExistence(timeout: 5))
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.revealTool("tools.card-billing").tap()
        XCTAssertTrue(app.staticTexts["榴园食堂"].waitForExistence(timeout: 5))
        app.buttons["billing.stats"].tap()
        XCTAssertTrue(app.staticTexts["总支出"].waitForExistence(timeout: 5))
        let attachment = XCTAttachment(screenshot: app.screenshot()); attachment.name = "read-only-billing-statistics"; attachment.lifetime = .keepAlways; add(attachment)
    }
}
