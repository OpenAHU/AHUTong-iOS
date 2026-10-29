import XCTest

@MainActor
final class ToolsUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    private func launch(openTools: Bool = true, arguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["AHUTONG_CI_DISABLE_LIVE_PAYMENT"] = "1"
        app.launchArguments = ["--demo-consent", "--demo-session"] + arguments
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["小工具"].waitForExistence(timeout: 8))
        if openTools {
            app.tabBars.buttons["小工具"].tap()
            XCTAssertTrue(app.searchFields["搜索小工具"].waitForExistence(timeout: 4))
        }
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

    func testTabsStayVisibleInDetailAndToolsReturnsToRoot() {
        let app = launch()
        defer { app.terminate() }
        app.buttons["tools.bathroom"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["payment.bathroom.screen"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.tabBars.buttons["主页"].isHittable)
        XCTAssertTrue(app.tabBars.buttons["课表"].isHittable)
        XCTAssertTrue(app.tabBars.buttons["设置"].isHittable)
        app.tabBars.buttons["设置"].tap()
        XCTAssertTrue(app.buttons["settings.preferences"].waitForExistence(timeout: 4))
        app.tabBars.buttons["小工具"].tap()
        XCTAssertTrue(app.searchFields["搜索小工具"].waitForExistence(timeout: 4))
        XCTAssertTrue(app.buttons["tools.bathroom"].isHittable)
    }

    func testReturningToToolsClearsNativeSearch() {
        let app = launch()
        defer { app.terminate() }
        let search = app.searchFields["搜索小工具"]
        search.tap()
        search.typeText("校园邮箱")
        XCTAssertTrue(app.buttons["tools.student-mail"].waitForExistence(timeout: 3))
        app.buttons["tools.student-mail"].tap()
        XCTAssertTrue(app.switches["mail.unread-only"].waitForExistence(timeout: 4))
        app.tabBars.buttons["设置"].tap()
        app.tabBars.buttons["小工具"].tap()
        XCTAssertTrue(search.waitForExistence(timeout: 4))
        XCTAssertTrue(app.buttons["tools.bathroom"].waitForExistence(timeout: 3))
    }

    func testUnknownSearchShowsSystemEmptyState() {
        let app = launch()
        defer { app.terminate() }
        let search = app.searchFields["搜索小工具"]
        search.tap()
        search.typeText("不存在的工具")
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "不存在的工具")).firstMatch.waitForExistence(timeout: 3))
        XCTAssertEqual(app.buttons.matching(NSPredicate(
            format: "identifier BEGINSWITH %@ AND identifier != %@ AND identifier != %@", "tools.", "tools.edit-home", "tools.scan"
        )).count, 0)
    }

    func testHomeLibraryIncludesPreviouslyMissingToolTypes() {
        let app = launch()
        defer { app.terminate() }
        app.buttons["tools.edit-home"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["home.widget-library"].waitForExistence(timeout: 4))
        let available = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "home.widget-add."))
        let pinned = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "home.widget-remove."))
        XCTAssertEqual(available.count + pinned.count, 17)
        for id in ["network_recharge", "program_completion", "attendance", "student_mail", "canteen", "card_billing", "identity_code"] {
            XCTAssertTrue(app.buttons["home.widget-add.\(id)"].exists || app.buttons["home.widget-remove.\(id)"].exists,
                          "Missing home tool: \(id)")
        }
        capture(app, name: "home-all-tools-library")
    }

    func testHomeWidgetRemoveButtonPersistsAndAllowsAddingAgain() {
        let app = launch()
        defer { app.terminate() }
        openHomeEditor(app)
        let add = app.buttons["home.widget-add.bathroom"]
        if add.exists { add.tap() }
        let remove = app.buttons["home.widget-remove.bathroom"]
        XCTAssertTrue(remove.isHittable)
        remove.tap()
        XCTAssertTrue(add.waitForExistence(timeout: 3))
        XCTAssertFalse(remove.exists)
        app.buttons["home.widget-edit.done"].tap()

        app.terminate()
        app.launch()
        app.tabBars.buttons["小工具"].tap()
        openHomeEditor(app)
        XCTAssertTrue(add.waitForExistence(timeout: 3))
        XCTAssertFalse(remove.exists)
        add.tap()
        XCTAssertTrue(remove.waitForExistence(timeout: 3))
        app.buttons["home.widget-edit.done"].tap()
        app.buttons["home.payment.bathroom"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["payment.bathroom.screen"].waitForExistence(timeout: 5))
    }

    func testHomeWidgetDragToRemoveReturnsToolToLibrary() {
        let app = launch()
        defer { app.terminate() }
        openHomeEditor(app)
        let add = app.buttons["home.widget-add.bathroom"]
        if add.exists { add.tap() }
        let card = app.descendants(matching: .any)["home.payment.bathroom"].firstMatch
        let target = app.descendants(matching: .any)["home.widget-remove-target"].firstMatch
        XCTAssertTrue(card.isHittable && target.isHittable)
        card.press(forDuration: 0.8, thenDragTo: target)
        XCTAssertTrue(add.waitForExistence(timeout: 4))
        XCTAssertFalse(app.buttons["home.widget-remove.bathroom"].exists)
        capture(app, name: "home-drag-removal")
        add.tap()
    }

    func testHomeWidgetDragSwapsSlots() {
        let app = launch()
        defer { app.terminate() }
        openHomeEditor(app)
        for id in ["bathroom", "electricity"] {
            let add = app.buttons["home.widget-add.\(id)"]
            if add.exists { add.tap() }
        }
        let source = app.descendants(matching: .any)["home.payment.bathroom"].firstMatch
        let destination = app.descendants(matching: .any)["home.payment.electricity"].firstMatch
        let sourceY = source.frame.midY, destinationY = destination.frame.midY
        source.press(forDuration: 0.8, thenDragTo: destination)
        XCTAssertEqual(source.frame.midY, destinationY, accuracy: 2)
        XCTAssertEqual(destination.frame.midY, sourceY, accuracy: 2)
        capture(app, name: "home-drag-swap")
        source.press(forDuration: 0.8, thenDragTo: destination)
        XCTAssertEqual(source.frame.midY, sourceY, accuracy: 2)
    }

    func testHomeWidgetCancelledDragFromBrowsingKeepsAppUsable() {
        let app = launch(openTools: false)
        defer { app.terminate() }

        let card = app.buttons["home.payment.bathroom"]
        let originalFrame = card.frame
        card.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .press(forDuration: 0.8, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.15)))
        XCTAssertTrue(app.buttons["home.widget-edit.done"].waitForExistence(timeout: 5))
        app.buttons["home.widget-edit.done"].tap()
        XCTAssertEqual(card.frame.midY, originalFrame.midY, accuracy: 2)
        card.tap()
        XCTAssertTrue(app.descendants(matching: .any)["payment.bathroom.screen"].waitForExistence(timeout: 5))
        capture(app, name: "home-cancelled-browsing-drag")
    }

    func testHomeWidgetLongPressAndReleaseKeepsAppUsable() {
        let app = launch(openTools: false)
        defer { app.terminate() }
        let card = app.buttons["home.payment.bathroom"]
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        for _ in 0..<5 {
            card.press(forDuration: 1.2)
            XCTAssertTrue(app.buttons["home.widget-edit.done"].waitForExistence(timeout: 5))
            app.buttons["home.widget-edit.done"].tap()
            XCTAssertTrue(card.isHittable)
        }
        card.tap()
        XCTAssertTrue(app.descendants(matching: .any)["payment.bathroom.screen"].waitForExistence(timeout: 5))
        capture(app, name: "home-long-press-release")
    }

    func testHomeWidgetCancelledDragWhileEditingKeepsPlacement() {
        let app = launch()
        defer { app.terminate() }
        openHomeEditor(app)
        let add = app.buttons["home.widget-add.bathroom"]
        if add.exists { add.tap() }
        let card = app.descendants(matching: .any)["home.payment.bathroom"].firstMatch
        let originalFrame = card.frame
        card.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .press(forDuration: 0.8, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.15)))
        XCTAssertEqual(card.frame.midY, originalFrame.midY, accuracy: 2)
        XCTAssertTrue(app.buttons["home.widget-remove.bathroom"].exists)
        app.buttons["home.widget-edit.done"].tap()
    }

    func testHomeLibraryCancelledDragDoesNotAddTool() {
        let app = launch()
        defer { app.terminate() }
        openHomeEditor(app)
        let tool = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "home.widget-add.")).firstMatch
        let identifier = tool.identifier
        tool.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .press(forDuration: 0.8, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.15)))
        XCTAssertTrue(app.buttons[identifier].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons[identifier].isHittable)
        app.buttons["home.widget-edit.done"].tap()
    }

    func testScannerUnavailableOnSimulatorClosesWithoutLosingTools() {
        let app = launch()
        defer { app.terminate() }
        app.buttons["tools.scan"].tap()
        XCTAssertTrue(app.navigationBars["扫一扫"].waitForExistence(timeout: 4))
        XCTAssertTrue(app.staticTexts["暂时无法扫码"].waitForExistence(timeout: 4))
        capture(app, name: "native-scanner-unavailable")
        app.buttons["关闭"].tap()
        XCTAssertTrue(app.buttons["tools.edit-home"].waitForExistence(timeout: 4))
        XCTAssertTrue(app.tabBars.buttons["设置"].isHittable)
    }

    func testWeatherForecastAndSettingsUseNativeNavigation() {
        let app = launch(arguments: [#"--demo-endpoint-weather={"city":"合肥市","weather":"多云","temperature":23,"feels_like":24,"humidity":68,"wind_power":"2级","visibility":12,"temp_max":26,"temp_min":18,"aqi":36,"aqi_category":"优","report_time":"10分钟前更新","forecast":[{"date":"2026-10-30","week":"周五","temp_max":25,"temp_min":17,"weather_day":"晴"}],"hourly_forecast":[{"time":"2026-10-29 21:00:00","temperature":22,"weather":"多云"}]}"#])
        defer { app.terminate() }
        app.revealTool("tools.weather").tap()
        XCTAssertTrue(app.descendants(matching: .any)["weather.current"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["最高 26°   最低 18°"].exists)
        XCTAssertTrue(app.tabBars.buttons["小工具"].isHittable)
        capture(app, name: "weather-native-current")
        app.buttons["天气设置"].tap()
        XCTAssertTrue(app.navigationBars["天气设置"].waitForExistence(timeout: 4))
        app.buttons["完成"].tap()
        XCTAssertTrue(app.buttons["刷新天气"].waitForExistence(timeout: 4))
        app.swipeUp()
        XCTAssertTrue(app.staticTexts["空气质量"].waitForExistence(timeout: 4))
        capture(app, name: "weather-native-forecast")
    }

    private func openHomeEditor(_ app: XCUIApplication) {
        app.buttons["tools.edit-home"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["home.widget-library"].waitForExistence(timeout: 4))
    }

    private func capture(_ app: XCUIApplication, name: String) {
        let image = XCTAttachment(screenshot: app.screenshot())
        image.name = name
        image.lifetime = .keepAlways
        add(image)
    }
}
