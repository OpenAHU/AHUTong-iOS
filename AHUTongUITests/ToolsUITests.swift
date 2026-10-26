import XCTest

@MainActor
final class ToolsUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["AHUTONG_CI_DISABLE_LIVE_PAYMENT"] = "1"
        app.launchArguments = ["--demo-consent", "--demo-session"]
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["小工具"].waitForExistence(timeout: 8))
        app.tabBars.buttons["小工具"].tap()
        return app
    }

    func testCategoryCardsUseTwoColumnsAndLearningRemainsReachable() {
        let app = launch()
        defer { app.terminate() }
        let bathroom = app.buttons["tools.bathroom"], electricity = app.buttons["tools.electricity"]
        XCTAssertTrue(app.staticTexts["缴费充值"].exists)
        XCTAssertTrue(bathroom.isHittable && electricity.isHittable)
        XCTAssertEqual(bathroom.frame.midY, electricity.frame.midY, accuracy: 1)
        XCTAssertLessThan(bathroom.frame.maxX, electricity.frame.minX)
        capture(app, name: "tools-categories-top")
        let learning = app.revealTool("tools.study-repository")
        capture(app, name: "tools-categories-bottom")
        learning.tap()
        XCTAssertTrue(app.buttons["repository.downloads"].waitForExistence(timeout: 5))
    }

    func testHomePinnedPaymentRemainsInToolsGrid() {
        let app = launch()
        defer { app.terminate() }
        let bathroom = app.buttons["tools.bathroom"]
        XCTAssertTrue(bathroom.isHittable)
        bathroom.tap()
        XCTAssertTrue(app.descendants(matching: .any)["payment.bathroom.screen"].waitForExistence(timeout: 5))
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(bathroom.waitForExistence(timeout: 3))
        XCTAssertTrue(app.tabBars.buttons["小工具"].isSelected)
    }

    func testNativeSearchFindsMailboxAndRestoresNavigation() {
        let app = launch()
        defer { app.terminate() }
        let search = app.searchFields["搜索小工具"]
        XCTAssertTrue(search.isHittable)
        search.tap()
        search.typeText("校园邮箱")
        let mail = app.buttons["tools.student-mail"]
        XCTAssertTrue(mail.waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["tools.bathroom"].exists)
        mail.tap()
        XCTAssertTrue(app.switches["mail.unread-only"].waitForExistence(timeout: 5))
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(mail.waitForExistence(timeout: 3))
    }

    func testUnknownSearchShowsSystemEmptyState() {
        let app = launch()
        defer { app.terminate() }
        let search = app.searchFields["搜索小工具"]
        search.tap()
        search.typeText("不存在的工具")
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "不存在的工具")).firstMatch.waitForExistence(timeout: 3))
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "tools.")).count, 0)
    }

    private func capture(_ app: XCUIApplication, name: String) {
        let image = XCTAttachment(screenshot: app.screenshot())
        image.name = name
        image.lifetime = .keepAlways
        add(image)
    }
}
