import XCTest

final class SettingsExperienceUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    @MainActor
    func testNativeTabsSettingsStructureAndConciseCopy() {
        let settings = XCUIApplication(bundleIdentifier: "com.apple.Preferences")
        setReduceMotion(false, control: openMotionSettings(settings))
        let app = XCUIApplication()
        app.launchEnvironment["AHUTONG_CI_DISABLE_LIVE_PAYMENT"] = "1"
        app.launchArguments = ["--demo-consent", "--demo-session", "-theme.color", "blue"]
        app.launch()
        XCTAssertTrue(app.staticTexts["screen.home"].waitForExistence(timeout: 5))
        let bar = app.tabBars.firstMatch
        XCTAssertTrue(bar.exists)
        XCTAssertEqual(bar.buttons.count, 4)
        let titles = ["主页", "课表", "小工具", "设置"]
        for (index, title) in titles.enumerated() {
            let button = bar.buttons.element(boundBy: index)
            XCTAssertEqual(button.label, title)
            button.tap()
            XCTAssertTrue(button.isSelected)
            capture("native-tab-\(index + 1)", app)
        }

        let appCard = app.descendants(matching: .any)["settings.app-card"].firstMatch
        XCTAssertTrue(appCard.waitForExistence(timeout: 3))
        appCard.tap(withNumberOfTaps: 8, numberOfTouches: 1)
        XCTAssertFalse(app.buttons["settings.debug"].exists)
        XCTAssertFalse(app.staticTexts["Debug"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["operations.debug.screen"].exists)
        XCTAssertTrue(app.buttons["settings.account-login"].exists)
        capture("settings-resting", app)

        // A long press gives the Simulator recording time to show the press
        // highlight and scale before the NavigationLink activates on release.
        app.buttons["settings.preferences"].press(forDuration: 3)
        XCTAssertTrue(app.buttons["preferences.privacy-consent"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["settings.account-login"].exists)
        XCTAssertFalse(app.buttons["preferences.login"].exists)
        XCTAssertFalse(app.buttons["preferences.liquid-glass"].exists)
        XCTAssertFalse(app.staticTexts["液态玻璃"].exists)
        XCTAssertFalse(app.staticTexts["Liquid Glass"].exists)
        capture("preferences-top", app)
        app.swipeUp()
        capture("preferences-bottom", app)

        app.terminate()
        app.launch()
        XCTAssertTrue(bar.waitForExistence(timeout: 5))
        bar.buttons["设置"].tap()
        let clear = app.buttons["settings.clear-data"]
        if !clear.isHittable { app.swipeUp() }
        XCTAssertTrue(clear.waitForExistence(timeout: 3))
        clear.tap()
        XCTAssertTrue(app.staticTexts["将退出登录，并清除课表、缓存和隐私选择。"].waitForExistence(timeout: 3))
        capture("clear-data-confirmation", app)
        // iOS may present this as a popover without a separate Cancel row.
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.1, dy: 0.2)).tap()
        XCTAssertTrue(app.staticTexts["将退出登录，并清除课表、缓存和隐私选择。"].waitForNonExistence(timeout: 3))
        app.buttons["settings.update-notes"].tap()
        XCTAssertTrue(app.staticTexts["新增 Siri 快捷指令和课程倒计时，改进登录续期、课表与小组件体验。"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "GitHub Actions")).firstMatch.exists)
        capture("update-notes", app)
        app.alerts.buttons["确定"].tap()

        bar.buttons["小工具"].tap()
        let add = app.buttons["tools.widget-add"]
        if !add.isHittable { app.swipeUp() }
        XCTAssertTrue(add.waitForExistence(timeout: 3))
        add.tap()
        XCTAssertTrue(app.buttons["tools.widget-guide.done"].waitForExistence(timeout: 3))
        capture("widget-guide", app)
        app.buttons["tools.widget-guide.done"].tap()
    }

    @MainActor
    func testPressFeedbackWithSystemReduceMotion() {
        let settings = XCUIApplication(bundleIdentifier: "com.apple.Preferences")
        var reduceMotion = openMotionSettings(settings)
        let app = XCUIApplication()
        app.launchEnvironment["AHUTONG_CI_DISABLE_LIVE_PAYMENT"] = "1"
        app.launchArguments = ["--demo-consent", "--demo-session", "-theme.color", "blue"]
        defer {
            reduceMotion = openMotionSettings(settings)
            setReduceMotion(false, control: reduceMotion)
            app.launch()
            XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 5))
            app.tabBars.buttons["设置"].tap()
        }
        for enabled in [false, true] {
            reduceMotion = openMotionSettings(settings)
            setReduceMotion(enabled, control: reduceMotion)
            capture("system-motion-\(enabled ? "on" : "off")", settings)
            app.terminate()
            app.launch()
            XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 5))
            app.tabBars.buttons["设置"].tap()
            capture("\(enabled ? "reduced" : "normal")-resting", app)
            // The capture helper watches these markers and screenshots the real
            // Simulator while the touch is held, without a test-only UI overlay.
            let marker = enabled ? "UX_PRESS_REDUCED" : "UX_PRESS_NORMAL"
            FileHandle.standardError.write(Data("\(marker)\n".utf8))
            app.buttons["settings.preferences"].press(forDuration: 6)
            XCTAssertTrue(app.buttons["preferences.privacy-consent"].waitForExistence(timeout: 3))
        }
    }

    @MainActor
    private func openMotionSettings(_ settings: XCUIApplication) -> XCUIElement {
        // Relaunching avoids a stale foreground application during cross-app
        // automation. Settings may reopen either its root or its previous page.
        settings.launch()
        let control = settings.switches["REDUCE_MOTION"]
        if !control.exists {
            for _ in 0..<3 {
                if settings.buttons["com.apple.settings.accessibility"].exists { break }
                let back = settings.navigationBars.buttons["BackButton"]
                guard back.exists else { break }
                back.tap()
            }
            settings.buttons["com.apple.settings.accessibility"].tap()
            let motion = settings.buttons.matching(NSPredicate(format: "label IN %@", ["动态效果", "Motion"])).firstMatch
            if !motion.isHittable { settings.swipeUp() }
            XCTAssertTrue(motion.waitForExistence(timeout: 3))
            motion.tap()
        }
        XCTAssertTrue(control.waitForExistence(timeout: 3))
        return control
    }

    @MainActor
    private func setReduceMotion(_ enabled: Bool, control: XCUIElement) {
        let target = enabled ? "1" : "0"
        if control.value as? String != target {
            let toggle = control.switches.firstMatch
            if toggle.exists { toggle.tap() } else { control.tap() }
        }
        expectation(for: NSPredicate(format: "value == %@", target), evaluatedWith: control)
        waitForExpectations(timeout: 3)
    }

    @MainActor
    func testSettingsAndWidgetGuideRemainReachable() {
        let app = XCUIApplication()
        app.launchEnvironment["AHUTONG_CI_DISABLE_LIVE_PAYMENT"] = "1"
        app.launchArguments = ["--demo-consent", "--demo-session"]
        app.launch()
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 5))
        app.tabBars.buttons["设置"].tap()
        capture("accessible-settings", app)
        let preferences = app.buttons["settings.preferences"]
        scrollTo(preferences, app: app)
        preferences.tap()
        XCTAssertTrue(app.buttons["preferences.privacy-policy"].waitForExistence(timeout: 3))
        capture("accessible-preferences", app)
        app.terminate()
        app.launch()
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 5))
        app.tabBars.buttons["小工具"].tap()
        let add = app.buttons["tools.widget-add"]
        scrollTo(add, app: app)
        add.tap()
        let done = app.buttons["tools.widget-guide.done"]
        XCTAssertTrue(done.waitForExistence(timeout: 3))
        capture("accessible-widget-guide", app)
        app.swipeUp()
        capture("accessible-widget-guide-expanded", app)
        XCTAssertTrue(done.isHittable)
        done.tap()
    }

    @MainActor
    private func scrollTo(_ element: XCUIElement, app: XCUIApplication) {
        for _ in 0..<5 {
            if element.isHittable { return }
            app.swipeUp()
        }
        XCTAssertTrue(element.isHittable)
    }

    @MainActor
    private func capture(_ name: String, _ app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "settings-ux-\(name)"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
