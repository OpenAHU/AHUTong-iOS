import XCTest

@MainActor
final class ExperiencePolishUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    private func launch(additionalArguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["AHUTONG_CI_DISABLE_LIVE_PAYMENT"] = "1"
        app.launchArguments = ["--demo-consent", "--demo-session", "-schedule.preview-next", "NO"] + additionalArguments
        app.launch()
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 8))
        return app
    }

    func testSettingsTabReturnsToRootAfterLeavingDetailViaShortcut() {
        let app = launch()
        app.tabBars.buttons["设置"].tap()
        app.buttons["settings.preferences"].tap()
        XCTAssertTrue(app.switches["preferences.privacy-consent"].waitForExistence(timeout: 4))
        // Detail screens intentionally hide the tab bar; a shortcut can leave
        // their navigation stack alive while returning to a top-level tab.
        app.open(URL(string: "ahutong://schedule")!)
        XCTAssertTrue(app.buttons["回到当前周"].waitForExistence(timeout: 4))
        app.tabBars.buttons["设置"].tap()
        XCTAssertTrue(app.buttons["settings.account-login"].waitForExistence(timeout: 4))
        app.tabBars.buttons["设置"].tap()
        XCTAssertTrue(app.buttons["settings.account-login"].waitForExistence(timeout: 4))
        capture(app, "settings-tab-root")
    }

    func testWeekIndicatorsAreCirclesForSingleAndDoubleDigits() {
        let app = launch()
        app.tabBars.buttons["课表"].tap()
        let first = app.buttons["schedule.week.1"]
        XCTAssertTrue(first.waitForExistence(timeout: 4))
        XCTAssertEqual(first.frame.width, first.frame.height, accuracy: 1)
        capture(app, "schedule-circle-week-1")
        let tenth = app.buttons["schedule.week.10"]
        // Advance through visible weeks instead of assuming week 5 fits initially.
        for week in 2...10 {
            let indicator = app.buttons["schedule.week.\(week)"]
            XCTAssertTrue(indicator.isHittable)
            indicator.tap()
        }
        XCTAssertTrue(tenth.isSelected)
        XCTAssertEqual(tenth.frame.width, tenth.frame.height, accuracy: 1)
        capture(app, "schedule-circle-week-10")
    }

    func testCampusCodeExpandsWithLargerSquareAndCollapses() {
        let app = launch()
        let balance = app.buttons["campus-card.balance"]
        XCTAssertTrue(balance.waitForExistence(timeout: 5))
        let collapsedHeight = balance.frame.height
        balance.tap()
        let code = app.buttons["campus-card.qr-refresh"]
        XCTAssertTrue(code.waitForExistence(timeout: 5))
        XCTAssertGreaterThan(code.frame.width, 138)
        XCTAssertEqual(code.frame.width, code.frame.height, accuracy: 1)
        XCTAssertGreaterThan(app.otherElements["campus-card.qr-panel"].frame.height, collapsedHeight)
        capture(app, "home-campus-code-expanded")
        app.buttons["campus-card.qr-collapse"].tap()
        XCTAssertTrue(balance.waitForExistence(timeout: 4))
        XCTAssertEqual(balance.frame.height, collapsedHeight, accuracy: 1)
    }

    func testHeaderActionsRemainUsableWithNativeMaterials() {
        let app = launch(additionalArguments: ["-debug.gray.home_edit", "enabled"])
        app.tabBars.buttons["课表"].tap()
        let currentWeek = app.buttons["回到当前周"]
        let settings = app.buttons["schedule.settings"]
        let refresh = app.buttons["schedule.refresh"]
        for button in [currentWeek, settings, refresh] {
            XCTAssertTrue(button.waitForExistence(timeout: 4))
            XCTAssertTrue(button.isHittable)
            XCTAssertGreaterThanOrEqual(button.frame.width, 44)
            XCTAssertGreaterThanOrEqual(button.frame.height, 44)
        }
        // Native ControlGroup keeps 8-point gaps inside the shared surface.
        XCTAssertLessThanOrEqual(settings.frame.minX - currentWeek.frame.maxX, 8)
        XCTAssertLessThanOrEqual(refresh.frame.minX - settings.frame.maxX, 8)
        capture(app, "schedule-native-header-buttons")
        app.buttons["schedule.week.2"].tap()
        currentWeek.tap()
        XCTAssertTrue(app.buttons["schedule.week.1"].isSelected)
        refresh.tap()
        XCTAssertTrue(app.buttons["schedule.course.demo-3"].waitForExistence(timeout: 4))
        settings.tap()
        XCTAssertTrue(app.switches["schedule.settings.overview"].waitForExistence(timeout: 4))
        app.buttons["schedule.settings.done"].tap()

        app.tabBars.buttons["小工具"].tap()
        let edit = app.buttons["tools.edit-home"]
        XCTAssertTrue(edit.waitForExistence(timeout: 4))
        XCTAssertTrue(edit.isHittable)
        XCTAssertGreaterThanOrEqual(edit.frame.width, 44)
        XCTAssertGreaterThanOrEqual(edit.frame.height, 44)
        capture(app, "tools-native-header-button")
        edit.tap()
        XCTAssertTrue(app.staticTexts["添加小工具"].waitForExistence(timeout: 4))
        app.buttons["完成"].tap()
    }

    func testCourseDetailFitsShortContentWithoutTallMetadata() {
        let app = launch()
        app.tabBars.buttons["课表"].tap()
        app.buttons["schedule.course.demo-3"].tap()
        let weeks = app.staticTexts["schedule.course-detail.weeks"]
        XCTAssertTrue(weeks.waitForExistence(timeout: 4))
        XCTAssertEqual(weeks.label, "第1–12周")
        let sheet = app.scrollViews["schedule.course-detail"].firstMatch
        XCTAssertLessThan(sheet.frame.height, 300)
        for field in ["location", "teacher"] {
            let element = app.descendants(matching: .any)
                .matching(identifier: "schedule.course-detail.\(field)").firstMatch
            XCTAssertTrue(element.isHittable)
            XCTAssertLessThan(element.frame.height, 50)
        }
        capture(app, "course-detail-compact")
        app.buttons["完成"].tap()
        XCTAssertTrue(weeks.waitForNonExistence(timeout: 4))
    }

    func testCourseDetailShowsAllIrregularWeeksAndLongMetadata() throws {
        try checkLongCourseDetail(accessibilitySize: false)
    }

    func testCourseDetailScrollsWithAccessibilityTextSize() throws {
        try checkLongCourseDetail(accessibilitySize: true)
    }

    private func checkLongCourseDetail(accessibilitySize: Bool) throws {
        let weeks = (1...60).filter { !$0.isMultiple(of: 3) }
        let location = "龙河校区博学北楼计算机网络综合实验室 B402（东侧入口）"
        let teacher = "王老师、李老师、张老师（联合授课）"
        let fixture: [[String: Any]] = [[
            "courseId": "long-detail", "name": "计算机网络综合实验与实践", "weekday": 2,
            "startWeek": 1, "endWeek": 60, "weekIndexes": weeks,
            "startTime": 3, "length": 2, "location": location, "teacher": teacher
        ]]
        let data = try JSONSerialization.data(withJSONObject: fixture)
        var arguments = ["--demo-endpoint-schedule=\(String(decoding: data, as: UTF8.self))"]
        if accessibilitySize {
            arguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        }
        let app = launch(additionalArguments: arguments)
        app.tabBars.buttons["课表"].tap()
        let course = app.buttons["schedule.course.long-detail"]
        XCTAssertTrue(course.waitForExistence(timeout: 4))
        course.tap()
        let weekText = app.staticTexts["schedule.course-detail.weeks"]
        XCTAssertTrue(weekText.waitForExistence(timeout: 4))
        XCTAssertEqual(weekText.label, "第\(weeks.map(String.init).joined(separator: "、"))周")
        XCTAssertGreaterThan(weekText.frame.height, 60, "The complete week list must occupy more than two lines")
        let sheet = app.scrollViews["schedule.course-detail"].firstMatch
        for (field, expected) in [("location", "地点：\(location)"), ("teacher", "授课老师：\(teacher)")] {
            let element = app.descendants(matching: .any)
                .matching(identifier: "schedule.course-detail.\(field)").firstMatch
            for _ in 0..<6 where !element.isHittable { sheet.swipeUp() }
            XCTAssertTrue(element.isHittable)
            XCTAssertEqual(element.label, expected)
            XCTAssertGreaterThanOrEqual(element.frame.minY, weekText.frame.maxY)
        }
        capture(app, accessibilitySize ? "course-detail-accessibility" : "course-detail-full-weeks")
    }

    func testDeveloperPopoverDismissalResumesItsRowAndDoubleTapOpensQQ() {
        let app = launch()
        app.tabBars.buttons["设置"].tap()
        let entry = app.buttons["settings.contributors"]
        if !entry.isHittable { app.swipeUp() }
        entry.tap()
        XCTAssertTrue(app.otherElements["contributors.row.0"].waitForExistence(timeout: 4))
        let addedMaintainer = app.buttons["contributors.avatar.1793838025"].firstMatch
        XCTAssertTrue(addedMaintainer.exists)
        XCTAssertEqual(addedMaintainer.label, "zirui.xu（24级）")
        XCTAssertEqual(app.buttons["contributors.avatar.1705945565"].firstMatch.label, "Himekawa（24级）")
        let row = app.otherElements["contributors.row.0"]
        let avatar = row.buttons.allElementsBoundByIndex.first { $0.isHittable }
        XCTAssertNotNil(avatar)
        avatar?.tap()
        XCTAssertTrue(app.otherElements["contributors.detail"].waitForExistence(timeout: 4))
        XCTAssertTrue(app.buttons["contributors.detail.close"].exists)
        XCTAssertEqual(row.value as? String, "已暂停")
        XCTAssertEqual(app.otherElements["contributors.row.1"].value as? String, "向右滚动")
        XCTAssertFalse(app.buttons["contributors.resume.0"].exists)
        XCTAssertFalse(app.buttons["contributors.resume.1"].exists)
        capture(app, "contributors-native-popover")
        app.buttons["contributors.detail.close"].tap()
        XCTAssertTrue(app.otherElements["contributors.detail"].waitForNonExistence(timeout: 4))
        expectation(for: NSPredicate(format: "value == %@", "向左滚动"), evaluatedWith: row)
        waitForExpectations(timeout: 4)
        XCTAssertEqual(app.otherElements["contributors.row.1"].value as? String, "向右滚动")
        let currentAvatar = row.buttons.allElementsBoundByIndex.first { $0.isHittable }
        XCTAssertNotNil(currentAvatar)
        currentAvatar?.doubleTap()
        XCTAssertTrue(app.alerts["打开 QQ"].waitForExistence(timeout: 4))
        app.alerts.buttons["知道了"].tap()
        capture(app, "contributors-two-rows")
    }

    private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
