import XCTest

@MainActor
final class CampusLifeUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }
    private func open(_ id: String, state: String = "normal") -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["AHUTONG_CI_DISABLE_LIVE_PAYMENT"] = "1"
        app.launchArguments = ["--demo-consent", "--demo-session", "--demo-state=\(state)"]
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["小工具"].waitForExistence(timeout: 8))
        app.tabBars.buttons["小工具"].tap()
        app.revealTool(id).tap()
        return app
    }

    func testAttendanceFiltersAndShowsActualAbsenceDetails() {
        let app = open("tools.attendance")
        defer { app.terminate() }
        let absent = app.segmentedControls["attendance.status"].buttons["缺勤"]
        XCTAssertTrue(absent.waitForExistence(timeout: 5))
        absent.tap()
        XCTAssertFalse(app.staticTexts["高等数学"].exists)
        app.staticTexts["大学英语"].tap()
        XCTAssertTrue(app.navigationBars["考勤详情"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@ AND label CONTAINS %@", "日期", "2026-10-23")).firstMatch.exists)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@ AND label CONTAINS %@", "打卡时间", "未记录")).firstMatch.exists)
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(absent.waitForExistence(timeout: 3))
    }

    func testAttendanceFailureOffersResponsiveRetry() {
        let app = open("tools.attendance", state: "error")
        defer { app.terminate() }
        let retry = app.buttons["attendance.retry"]
        XCTAssertTrue(retry.waitForExistence(timeout: 5))
        retry.tap()
        XCTAssertTrue(retry.waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["暂时无法连接考勤服务"].exists)
    }

    func testCanteenPeriodCampusAndWindowDetails() {
        let app = open("tools.canteen")
        defer { app.terminate() }
        let period = app.segmentedControls["canteen.period"]
        XCTAssertTrue(period.waitForExistence(timeout: 5))
        period.buttons["近30天"].tap()
        app.buttons["canteen.campus"].tap()
        let longhe = app.buttons["磬苑"]
        XCTAssertTrue(longhe.waitForExistence(timeout: 3))
        longhe.tap()
        XCTAssertTrue(app.staticTexts["磬苑 · 近30天热度榜"].waitForExistence(timeout: 3))
        app.staticTexts["风味小炒"].tap()
        XCTAssertTrue(app.navigationBars["窗口详情"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@ AND label CONTAINS %@", "平均每笔", "12.50")).firstMatch.exists)
        XCTAssertGreaterThan(app.navigationBars["窗口详情"].frame.minY, app.frame.height * 0.35)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Canteen native detail sheet"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        app.buttons["canteen.window.done"].tap()
        XCTAssertTrue(app.staticTexts["磬苑 · 近30天热度榜"].waitForExistence(timeout: 3))
    }

    func testCanteenIndividualCanteenFilterRemovesOtherWindows() {
        let app = open("tools.canteen")
        defer { app.terminate() }
        app.buttons["canteen.canteens"].tap()
        chooseOnlyMeiyuan(app)
        XCTAssertTrue(app.staticTexts["梅园 · 近7天热度榜"].waitForExistence(timeout: 4))
        XCTAssertTrue(app.staticTexts["面食窗口"].exists)
        XCTAssertFalse(app.staticTexts["风味小炒"].exists)
    }

    func testCanteenMultipleSelectionKeepsOnlySelectedCanteens() {
        let app = open("tools.canteen")
        defer { app.terminate() }
        app.buttons["canteen.canteens"].tap()
        XCTAssertTrue(app.buttons["canteen.clear-selection"].waitForExistence(timeout: 3))
        app.buttons["canteen.clear-selection"].tap()
        for name in ["梅园", "榴园"] {
            let toggle = app.switches["canteen.select.\(name)"]
            for _ in 0..<3 where !toggle.isHittable { app.swipeUp() }
            toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.88, dy: 0.5)).tap()
            XCTAssertEqual(toggle.value as? String, "1")
        }
        app.buttons["canteen.selection-done"].tap()
        XCTAssertTrue(app.staticTexts["梅园、榴园 · 近7天热度榜"].waitForExistence(timeout: 4))
        XCTAssertTrue(app.staticTexts["风味小炒"].exists)
        XCTAssertTrue(app.staticTexts["面食窗口"].exists)
        XCTAssertFalse(app.staticTexts["未命名窗口"].exists)
    }

    func testCanteenDrawRevealsRankAndAverageForSelectedCanteen() {
        let app = open("tools.canteen")
        defer { app.terminate() }
        app.buttons["canteen.draw"].tap()
        XCTAssertTrue(app.buttons["canteen.draw-canteens"].waitForExistence(timeout: 3))
        app.buttons["canteen.draw-canteens"].tap()
        chooseOnlyMeiyuan(app)
        let start = app.buttons["canteen.draw-start"]
        XCTAssertTrue(start.waitForExistence(timeout: 4))
        start.tap()
        XCTAssertTrue(app.staticTexts["正在挑选…"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.staticTexts["这次就吃它"].waitForExistence(timeout: 6))
        XCTAssertTrue(app.staticTexts["面食窗口"].firstMatch.exists)
        XCTAssertFalse(app.staticTexts["风味小炒"].exists)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@ AND label CONTAINS %@", "平均消费", "9.00")).firstMatch.waitForExistence(timeout: 4))
        app.buttons["canteen.draw.details"].tap()
        XCTAssertTrue(app.buttons["canteen.window.done"].waitForExistence(timeout: 3))
        app.buttons["canteen.window.done"].tap()
        XCTAssertTrue(app.staticTexts["这次就吃它"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["canteen.draw.details"].exists)
    }

    func testCanteenLeavingDuringDrawCancelsIt() {
        let app = open("tools.canteen")
        defer { app.terminate() }
        app.buttons["canteen.draw"].tap()
        let start = app.buttons["canteen.draw-start"]
        XCTAssertTrue(start.waitForExistence(timeout: 4))
        start.tap()
        app.navigationBars.buttons.firstMatch.tap()
        app.buttons["canteen.draw"].tap()
        XCTAssertTrue(start.waitForExistence(timeout: 4))
        XCTAssertTrue(start.isEnabled)
        XCTAssertFalse(app.staticTexts["这次就吃它"].exists)
    }

    func testCanteenPersonalRecordsPreviewRequiresConsentAndDisablesDemoUpload() {
        let app = open("tools.canteen")
        defer { app.terminate() }
        app.buttons["canteen.my-records"].tap()
        XCTAssertTrue(app.navigationBars["我的记录"].waitForExistence(timeout: 4))
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@ AND label CONTAINS %@", "正餐次数", "3 餐")).firstMatch.waitForExistence(timeout: 4))
        let preview = app.navigationBars.buttons["canteen.contribution-preview"]
        XCTAssertTrue(preview.isHittable)
        preview.tap()
        XCTAssertTrue(app.navigationBars["贡献预览"].waitForExistence(timeout: 3))
        let submit = app.navigationBars.buttons["canteen.contribution-submit"]
        XCTAssertTrue(submit.exists)
        XCTAssertFalse(submit.isEnabled)
        app.switches["canteen.contribution-consent"].tap()
        XCTAssertFalse(submit.isEnabled)
        XCTAssertTrue(app.staticTexts["演示数据不会提交"].exists)
    }

    func testCanteenPersonalEmptyStateIsExplicit() {
        let app = open("tools.canteen", state: "empty")
        defer { app.terminate() }
        app.buttons["canteen.my-records"].tap()
        XCTAssertTrue(app.staticTexts["暂无用餐记录"].waitForExistence(timeout: 4))
    }

    func testCanteenPersonalFailureCanRetry() {
        let app = open("tools.canteen", state: "error")
        defer { app.terminate() }
        app.buttons["canteen.my-records"].tap()
        let retry = app.buttons["canteen.records-retry"]
        XCTAssertTrue(retry.waitForExistence(timeout: 4))
        retry.tap()
        XCTAssertTrue(retry.waitForExistence(timeout: 3))
        XCTAssertFalse(app.staticTexts["暂无用餐记录"].exists)
    }

    private func chooseOnlyMeiyuan(_ app: XCUIApplication) {
        let clear = app.buttons["canteen.clear-selection"]
        XCTAssertTrue(clear.waitForExistence(timeout: 3))
        clear.tap()
        let meiyuan = app.switches["canteen.select.梅园"]
        for _ in 0..<3 where !meiyuan.isHittable { app.swipeUp() }
        XCTAssertTrue(meiyuan.isHittable)
        meiyuan.coordinate(withNormalizedOffset: CGVector(dx: 0.88, dy: 0.5)).tap()
        XCTAssertEqual(meiyuan.value as? String, "1")
        let done = app.buttons["canteen.selection-done"]
        XCTAssertTrue(done.isEnabled)
        done.tap()
        XCTAssertTrue(app.navigationBars["选择食堂"].waitForNonExistence(timeout: 3))
    }

    func testCanteenEmptyStateKeepsFiltersAvailable() {
        let app = open("tools.canteen", state: "empty")
        defer { app.terminate() }
        XCTAssertTrue(app.staticTexts["暂无榜单"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.segmentedControls["canteen.period"].isHittable)
    }

    func testCanteenFailureOffersResponsiveRetry() {
        let app = open("tools.canteen", state: "error")
        defer { app.terminate() }
        let retry = app.buttons["canteen.retry"]
        XCTAssertTrue(retry.waitForExistence(timeout: 5))
        retry.tap()
        XCTAssertTrue(retry.waitForExistence(timeout: 3))
        XCTAssertFalse(app.staticTexts["暂无榜单"].exists)
    }
}
