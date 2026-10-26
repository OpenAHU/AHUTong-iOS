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
        let longhe = app.buttons["龙河"]
        XCTAssertTrue(longhe.waitForExistence(timeout: 3))
        longhe.tap()
        XCTAssertTrue(app.staticTexts["龙河 · 近30天热度榜"].waitForExistence(timeout: 3))
        app.staticTexts["风味小炒"].tap()
        XCTAssertTrue(app.navigationBars["窗口详情"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@ AND label CONTAINS %@", "平均每笔", "12.50")).firstMatch.exists)
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
