import XCTest

@MainActor
final class ShortcutUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    func testPaymentCodeURLOnColdStart() {
        let app = XCUIApplication()
        app.terminate()
        app.launchArguments = ["--demo-consent", "--demo-session"]
        app.open(URL(string: "ahutong://payment-code")!)
        XCTAssertTrue(app.buttons["campus-card.qr-refresh"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["campus-card.qr-refresh"].isHittable)
        XCTAssertTrue(app.otherElements["campus-card.qr-panel"].exists)
        attachScreenshot(app, "shortcut-payment-code-cold")
    }

    func testPaymentCodeURLReturnsFromAnotherTabAndCanBeRepeated() {
        let app = XCUIApplication()
        app.launchArguments = ["--demo-consent", "--demo-session"]
        app.launch()
        let tools = app.tabBars.buttons["小工具"]
        XCTAssertTrue(tools.waitForExistence(timeout: 8))
        tools.tap()
        XCTAssertTrue(app.buttons["tools.phone-book"].waitForExistence(timeout: 5))
        app.open(URL(string: "ahutong://payment-code")!)
        XCTAssertTrue(app.buttons["campus-card.qr-refresh"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["campus-card.qr-refresh"].isHittable)
        tools.tap()
        app.buttons["tools.phone-book"].tap()
        app.open(URL(string: "ahutong://payment-code")!)
        XCTAssertTrue(app.buttons["campus-card.qr-refresh"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["campus-card.qr-refresh"].isHittable)
        attachScreenshot(app, "shortcut-payment-code-repeat")
    }

    func testExperienceAccountCannotOpenPaymentCode() {
        let app = XCUIApplication()
        app.launchArguments = ["--reset-onboarding", "--demo-consent"]
        app.launch()
        let experience = app.buttons["login.experience"]
        XCTAssertTrue(experience.waitForExistence(timeout: 8))
        experience.tap()
        XCTAssertTrue(app.buttons["回到当前周"].waitForExistence(timeout: 5))
        app.launchArguments = ["--demo-consent"]
        app.open(URL(string: "ahutong://payment-code")!)
        XCTAssertTrue(app.buttons["settings.account-login"].waitForExistence(timeout: 8))
        XCTAssertFalse(app.buttons["campus-card.qr-refresh"].exists)
        attachScreenshot(app, "shortcut-payment-code-requires-account")
    }

    private func attachScreenshot(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
