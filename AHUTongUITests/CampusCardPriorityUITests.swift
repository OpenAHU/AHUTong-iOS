import XCTest

final class CampusCardPriorityUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    @MainActor
    func testPaymentCodeAppearsBeforeSlowBalanceFinishes() {
        let app = XCUIApplication()
        app.launchEnvironment["AHUTONG_CI_DISABLE_LIVE_PAYMENT"] = "1"
        app.launchArguments = ["--demo-consent", "--demo-session", "--demo-slow-card-balance"]
        app.launch()
        let card = app.buttons["campus-card.balance"]
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        card.tap()
        XCTAssertTrue(app.buttons["campus-card.qr-refresh"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.staticTexts["¥ 126.35"].exists, "余额仍在等待时应先显示付款码")
        XCTAssertLessThan(app.otherElements["campus-card.qr-panel"].frame.height, 300)
        let preview = XCTAttachment(screenshot: app.screenshot())
        preview.name = "payment-code-before-slow-balance"
        preview.lifetime = .keepAlways
        add(preview)
        app.buttons["campus-card.qr-expand"].tap()
        XCTAssertTrue(app.buttons["campus-card.qr-refresh"].waitForExistence(timeout: 3))
    }
}
