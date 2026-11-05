import XCTest

@MainActor
final class ShortcutUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    func testSettingsExplainsShortcutsAndProvidesSystemLink() {
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
        // A native Form section exposes separate header/row/footer nodes.
        // Compare the actual containing cells, not an old custom-card container.
        let shortcutCell = app.cells.containing(.button, identifier: "preferences.shortcuts").firstMatch
        let privacyCell = app.cells.containing(.switch, identifier: "preferences.privacy-consent").firstMatch
        XCTAssertTrue(shortcutCell.exists)
        XCTAssertTrue(privacyCell.exists)
        XCTAssertEqual(shortcutCell.frame.minX, privacyCell.frame.minX, accuracy: 1)
        XCTAssertEqual(shortcutCell.frame.width, privacyCell.frame.width, accuracy: 1)
        attachScreenshot(app, "preferences-shortcuts-card-alignment")
        entry.tap()
        XCTAssertTrue(app.staticTexts["先允许 Siri 调用"].waitForExistence(timeout: 4))
        XCTAssertTrue(app.buttons["shortcuts.siri-settings"].exists)
        XCTAssertTrue(app.buttons["shortcuts.open"].label.contains("安大通"))
        attachScreenshot(app, "preferences-shortcuts-permission")
        app.swipeUp()
        XCTAssertTrue(app.staticTexts["打开扫一扫"].waitForExistence(timeout: 4))
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
        XCTAssertTrue(app.buttons["campus-card.fullscreen.qr-refresh"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["campus-card.fullscreen.qr-refresh"].wait(for: \.isHittable, toEqual: true, timeout: 15))
        assertFullPaymentCode(app)
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
        XCTAssertTrue(app.buttons["campus-card.fullscreen.qr-refresh"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["campus-card.fullscreen.qr-refresh"].wait(for: \.isHittable, toEqual: true, timeout: 15))
        assertFullPaymentCode(app)
        app.buttons["campus-card.qr-fullscreen-close"].tap()
        tools.tap()
        app.revealTool("tools.phone-book").tap()
        app.open(URL(string: "ahutong://payment-code")!)
        XCTAssertTrue(app.buttons["campus-card.fullscreen.qr-refresh"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["campus-card.fullscreen.qr-refresh"].wait(for: \.isHittable, toEqual: true, timeout: 15))
        assertFullPaymentCode(app)
        attachScreenshot(app, "shortcut-payment-code-repeat")
    }

    func testScannerURLOnColdStartUsesFullScreenWithoutTorchHardware() {
        let app = XCUIApplication()
        app.launchArguments = ["--demo-consent", "--demo-session"]
        app.open(URL(string: "ahutong://scan")!)
        XCTAssertTrue(app.navigationBars["扫一扫"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.tabBars.firstMatch.isHittable)
        XCTAssertTrue(app.buttons["scan.torch"].exists)
        XCTAssertFalse(app.buttons["scan.torch"].isEnabled)
        attachScreenshot(app, "shortcut-scanner-fullscreen")
        app.buttons["scan.close"].tap()
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 5))
    }

    func testScannerShortcutDoesNotRequireCampusLoginAfterConsent() {
        let app = XCUIApplication()
        app.launchArguments = ["--reset-onboarding", "--demo-consent"]
        app.open(URL(string: "ahutong://scan")!)
        XCTAssertTrue(app.buttons["scan.close"].waitForExistence(timeout: 10))
        app.buttons["scan.close"].tap()
        XCTAssertTrue(app.buttons["login.submit"].waitForExistence(timeout: 5))
    }

    func testScannerAndPaymentShortcutsReplaceEachOthersFullScreen() {
        let app = XCUIApplication()
        app.launchArguments = ["--demo-consent", "--demo-session"]
        app.launch()
        app.open(URL(string: "ahutong://payment-code")!)
        XCTAssertTrue(app.buttons["campus-card.qr-fullscreen-close"].waitForExistence(timeout: 10))
        app.open(URL(string: "ahutong://scan")!)
        XCTAssertTrue(app.buttons["scan.close"].waitForExistence(timeout: 8))
        XCTAssertFalse(app.buttons["campus-card.qr-fullscreen-close"].exists)
        app.open(URL(string: "ahutong://payment-code")!)
        XCTAssertTrue(app.buttons["campus-card.qr-fullscreen-close"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["campus-card.fullscreen.qr-refresh"].waitForExistence(timeout: 8))
        XCTAssertFalse(app.buttons["scan.close"].exists)
    }

    func testFullPaymentCodeReloadsWhenReturningFromBackground() {
        let app = XCUIApplication()
        app.launchArguments = ["--demo-consent", "--demo-session"]
        app.open(URL(string: "ahutong://payment-code")!)
        let code = app.buttons["campus-card.fullscreen.qr-refresh"]
        XCTAssertTrue(code.waitForExistence(timeout: 10))
        XCUIDevice.shared.press(.home)
        app.activate()
        XCTAssertTrue(code.waitForExistence(timeout: 8))
        XCTAssertTrue(code.isHittable)
        assertFullPaymentCode(app)
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
        XCTAssertFalse(app.buttons["campus-card.fullscreen.qr-refresh"].exists)
        attachScreenshot(app, "shortcut-payment-code-requires-account")
    }

    private func attachScreenshot(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func assertFullPaymentCode(_ app: XCUIApplication) {
        XCTAssertTrue(app.buttons["campus-card.qr-fullscreen-close"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.tabBars.firstMatch.isHittable)
        XCTAssertGreaterThan(app.buttons["campus-card.fullscreen.qr-refresh"].frame.width, 280)
    }
}
