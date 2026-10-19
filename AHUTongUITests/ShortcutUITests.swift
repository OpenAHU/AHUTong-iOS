import XCTest

@MainActor
final class ShortcutUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    func testSettingsExplainsBothShortcutsAndProvidesSystemLink() {
        let app = XCUIApplication()
        app.launchEnvironment["AHUTONG_CI_DISABLE_LIVE_PAYMENT"] = "1"
        app.launchArguments = ["--demo-consent", "--demo-session"]
        app.launch()
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 8))
        app.tabBars.buttons["设置"].tap()
        XCTAssertFalse(app.buttons["settings.shortcuts"].exists)
        app.buttons["settings.preferences"].tap()
        let entry = app.buttons["preferences.shortcuts"]
        if !entry.isHittable { app.swipeUp() }
        XCTAssertTrue(entry.waitForExistence(timeout: 4))
        let privacySection = app.otherElements["preferences.privacy-section"]
        XCTAssertTrue(privacySection.exists)
        XCTAssertEqual(entry.frame.minX, privacySection.frame.minX, accuracy: 1)
        XCTAssertEqual(entry.frame.width, privacySection.frame.width, accuracy: 1)
        attachScreenshot(app, "preferences-shortcuts-card-alignment")
        entry.press(forDuration: 0.5)
        XCTAssertTrue(app.staticTexts["先允许 Siri 调用"].waitForExistence(timeout: 4))
        XCTAssertTrue(app.buttons["shortcuts.siri-settings"].exists)
        XCTAssertTrue(app.buttons["shortcuts.open"].label.contains("安大通"))
        attachScreenshot(app, "preferences-shortcuts-permission")
        app.swipeUp()
        XCTAssertTrue(app.staticTexts["只说“打开校园码”"].waitForExistence(timeout: 4))
        attachScreenshot(app, "preferences-shortcuts-voice-phrases")
        app.swipeUp()
        XCTAssertTrue(app.staticTexts["shortcuts.discovery-help"].isHittable)
        XCTAssertTrue(app.staticTexts["查询指定日期课表"].exists)
        attachScreenshot(app, "preferences-shortcuts-guide-help")
    }

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
