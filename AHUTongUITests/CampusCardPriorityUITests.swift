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
    @MainActor
    func testOpeningAndExplicitRetryRecoverFailedPrefetch() {
        let app = XCUIApplication()
        app.launchEnvironment["AHUTONG_CI_DISABLE_LIVE_PAYMENT"] = "1"
        app.launchArguments = ["--demo-consent", "--demo-session", "--demo-card-qr-fails-twice"]
        app.launch()
        let card = app.buttons["campus-card.balance"]
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        // A loaded balance proves the failed prefetch has completed first.
        expectation(for: NSPredicate(format: "label CONTAINS %@", "126.35"), evaluatedWith: card)
        waitForExpectations(timeout: 5)
        card.tap()
        let retry = app.buttons["campus-card.qr-retry"]
        XCTAssertTrue(retry.waitForExistence(timeout: 5))
        retry.tap()
        XCTAssertTrue(app.buttons["campus-card.qr-refresh"].waitForExistence(timeout: 5))
        XCTAssertFalse(retry.exists)
        app.buttons["campus-card.qr-collapse"].tap()
        XCTAssertTrue(card.waitForExistence(timeout: 3))
    }

}
