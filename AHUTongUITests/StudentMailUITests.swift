import XCTest

@MainActor
final class StudentMailUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    private func launch(_ extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["AHUTONG_CI_DISABLE_LIVE_PAYMENT"] = "1"
        app.launchArguments = ["--demo-consent", "--demo-session", "-theme.color", "default",
            "-schedule.preview-next", "NO"] + extra
        app.launch()
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 8))
        return app
    }

    func testNativeMailboxReadComposeAndContactsWithoutSending() {
        let app = launch()
        app.tabBars.buttons["小工具"].tap()
        let mail = app.buttons["tools.student-mail"]
        reveal(mail, in: app)
        mail.tap()
        let unread = app.switches["mail.unread-only"]
        XCTAssertTrue(unread.waitForExistence(timeout: 6))
        XCTAssertTrue(app.buttons["mail.compose"].isHittable)
        app.buttons["mail.message.fixture-unread"].tap()
        XCTAssertTrue(app.staticTexts["mail.detail.body"].waitForExistence(timeout: 5))
        capture(app, "student-mail-native-detail")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.buttons["mail.compose"].tap()
        let to = app.textFields["mail.compose.to"]
        XCTAssertTrue(to.waitForExistence(timeout: 4))
        app.buttons["mail.compose.contacts"].tap()
        let contact = app.buttons["mail.contact.reader@example.test"]
        XCTAssertTrue(contact.waitForExistence(timeout: 4))
        contact.tap()
        XCTAssertEqual(to.value as? String, "reader@example.test")
        capture(app, "student-mail-native-compose")
        app.buttons["取消"].tap()
        app.buttons["放弃更改"].tap()
        XCTAssertTrue(app.switches["mail.unread-only"].waitForExistence(timeout: 4))
        unread.switches.firstMatch.exists ? unread.switches.firstMatch.tap() : unread.tap()
        XCTAssertFalse(app.buttons["mail.message.fixture-read"].exists)
        capture(app, "student-mail-native-inbox")
        app.buttons["mail.folders"].tap()
        let drafts = app.buttons["草稿箱"]
        XCTAssertTrue(drafts.waitForExistence(timeout: 4))
        drafts.tap()
        XCTAssertTrue(app.staticTexts["暂无邮件"].waitForExistence(timeout: 4))
    }

    func testMailboxErrorHasExplicitRetry() {
        let app = launch(["--demo-state=error"])
        app.tabBars.buttons["小工具"].tap()
        let mail = app.buttons["tools.student-mail"]
        reveal(mail, in: app)
        mail.tap()
        let retry = app.buttons["mail.retry"]
        XCTAssertTrue(retry.waitForExistence(timeout: 5))
        retry.tap()
        XCTAssertTrue(retry.waitForExistence(timeout: 5))
        capture(app, "student-mail-error-retry")
    }

    func testToolsBackHistoryNamesItsRoot() {
        let app = launch([#"--demo-endpoint-weather={"city":"合肥市","weather":"晴","temperature":28}"#])
        app.tabBars.buttons["小工具"].tap()
        app.revealTool("tools.weather").tap()
        XCTAssertTrue(app.buttons["天气设置"].waitForExistence(timeout: 5))
        let back = app.navigationBars.buttons.element(boundBy: 0)
        XCTAssertEqual(back.label, "小工具")
        back.press(forDuration: 3)
        let root = app.buttons["小工具"].firstMatch
        XCTAssertTrue(root.waitForExistence(timeout: 4))
        XCTAssertTrue(root.isHittable)
        capture(app, "tools-native-back-history-root")
        root.tap()
        XCTAssertTrue(app.scrollViews["tools.grid"].waitForExistence(timeout: 4))
        XCTAssertFalse(app.buttons["天气设置"].exists)
    }

    func testToolsAndSettingsReturnToRootAfterExternalNavigationAndForegroundReturn() {
        let app = launch([#"--demo-endpoint-weather={"city":"合肥市","weather":"晴","temperature":28}"#])
        app.tabBars.buttons["小工具"].tap()
        let weather = app.buttons["tools.weather"]
        reveal(weather, in: app)
        weather.tap()
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "weather.current").firstMatch.waitForExistence(timeout: 6))
        XCTAssertTrue(app.buttons["天气设置"].isHittable)
        XCUIDevice.shared.press(.home)
        app.open(URL(string: "ahutong://schedule")!)
        XCTAssertTrue(app.tabBars.buttons["小工具"].waitForExistence(timeout: 5))
        app.tabBars.buttons["小工具"].tap()
        XCTAssertTrue(app.scrollViews["tools.grid"].waitForExistence(timeout: 4))
        XCTAssertFalse(app.buttons["天气设置"].exists)
        capture(app, "tools-returned-to-root")
        app.tabBars.buttons["设置"].tap()
        app.buttons["settings.preferences"].tap()
        XCTAssertTrue(app.buttons["preferences.shortcuts"].waitForExistence(timeout: 4))
        XCUIDevice.shared.press(.home)
        app.open(URL(string: "ahutong://payment-code")!)
        XCTAssertTrue(app.buttons["campus-card.qr-collapse"].waitForExistence(timeout: 6))
        app.tabBars.buttons["设置"].tap()
        XCTAssertTrue(app.buttons["settings.preferences"].waitForExistence(timeout: 4))
        app.tabBars.buttons["设置"].tap()
        XCTAssertTrue(app.buttons["settings.preferences"].waitForExistence(timeout: 4))
        capture(app, "settings-returned-to-root")
    }

    func testOverviewOverlappingCoursesHaveSeparateConsistentCardFrames() {
        let fixture = #"[{"weekday":1,"startWeek":1,"endWeek":1,"location":"A301","name":"本周课程","teacher":"测试","length":2,"startTime":1,"courseId":"overlap-current","weekIndexes":[1]},{"weekday":1,"startWeek":2,"endWeek":2,"location":"A302","name":"下周课程","teacher":"测试","length":2,"startTime":1,"courseId":"overlap-future","weekIndexes":[2]}]"#
        let app = launch(["-schedule.show-all", "YES", "--demo-endpoint-schedule=\(fixture)"])
        app.tabBars.buttons["课表"].tap()
        let first = app.buttons["schedule.course.overlap-current"]
        let second = app.buttons["schedule.course.overlap-future"]
        XCTAssertTrue(first.waitForExistence(timeout: 5))
        XCTAssertTrue(second.exists)
        XCTAssertEqual(first.value as? String, "本周")
        XCTAssertEqual(second.value as? String, "非本周")
        XCTAssertEqual(first.frame.width, second.frame.width, accuracy: 1)
        XCTAssertEqual(first.frame.height, second.frame.height, accuracy: 1)
        let frames = [first.frame, second.frame].sorted { $0.minY < $1.minY }
        XCTAssertLessThanOrEqual(frames[0].maxY, frames[1].minY + 1)
        capture(app, "overview-overlapping-independent-rounded-cards")
    }

    func testOverviewDistinguishesInactiveCoursesAndDefaultThemeIsBlue() {
        let app = launch(["-schedule.show-all", "YES"])
        app.tabBars.buttons["课表"].tap()
        let current = app.buttons["schedule.course.demo-1"]
        XCTAssertTrue(current.waitForExistence(timeout: 5))
        XCTAssertEqual(current.value as? String, "本周")
        let future = app.buttons["schedule.course.demo-5"]
        reveal(future, in: app)
        XCTAssertEqual(future.value as? String, "非本周")
        capture(app, "overview-gray-rounded-course-cards")
        app.tabBars.buttons["设置"].tap()
        app.buttons["settings.preferences"].tap()
        let blue = app.buttons["preferences.theme.default"]
        reveal(blue, in: app)
        XCTAssertEqual(blue.label, "极光蓝")
        XCTAssertEqual(blue.value as? String, "已选中")
        let purple = app.buttons["preferences.theme.#FF6750A4"]
        if !purple.isHittable {
            app.scrollViews.containing(.button, identifier: "preferences.theme.default").firstMatch.swipeLeft()
        }
        XCTAssertTrue(purple.isHittable)
        XCTAssertEqual(purple.label, "鸢尾紫")
        capture(app, "aurora-blue-default-and-iris-purple")
    }

    func testSundayFirstKeepsCourseDatesAndPersistsUntilSwitchedOff() {
        let fixture = #"[{"weekday":7,"startWeek":1,"endWeek":1,"location":"A301","name":"周日课程","teacher":"测试","length":2,"startTime":1,"courseId":"sunday-fixture","weekIndexes":[1]},{"weekday":1,"startWeek":1,"endWeek":2,"location":"A302","name":"周一课程","teacher":"测试","length":2,"startTime":1,"courseId":"monday-fixture","weekIndexes":[1,2]}]"#
        let app = launch(["-schedule.show-all", "NO", "--demo-endpoint-schedule=\(fixture)"])
        app.tabBars.buttons["课表"].tap()
        app.buttons["schedule.settings"].tap()
        let toggle = app.switches["schedule.settings.sunday-first"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 4))
        if toggle.value as? String == "1" { toggle.tap() }
        app.buttons["schedule.settings.done"].tap()
        let monday = app.staticTexts["schedule.date.week.1.day.1"]
        let sunday = app.staticTexts["schedule.date.week.1.day.7"]
        XCTAssertTrue(monday.waitForExistence(timeout: 4))
        XCTAssertEqual(sunday.label, "07-19")
        XCTAssertLessThan(monday.frame.midX, sunday.frame.midX)

        app.buttons["schedule.settings"].tap()
        toggle.tap()
        capture(app, "schedule-sunday-first-setting")
        app.buttons["schedule.settings.done"].tap()
        XCTAssertEqual(sunday.label, "07-12")
        XCTAssertEqual(monday.label, "07-13")
        XCTAssertLessThan(sunday.frame.midX, monday.frame.midX)
        XCTAssertFalse(app.buttons["schedule.course.sunday-fixture"].exists)
        app.buttons["schedule.week.2"].tap()
        let nextSunday = app.staticTexts["schedule.date.week.2.day.7"]
        XCTAssertTrue(nextSunday.waitForExistence(timeout: 4))
        XCTAssertEqual(nextSunday.label, "07-19")
        XCTAssertEqual(app.staticTexts["schedule.date.week.2.day.1"].label, "07-20")
        let sundayCourse = app.buttons["schedule.course.sunday-fixture"]
        XCTAssertTrue(sundayCourse.exists)
        XCTAssertEqual(sundayCourse.frame.midX, nextSunday.frame.midX, accuracy: 2)
        XCTAssertTrue(app.buttons["schedule.course.monday-fixture"].exists)
        // The next page is accessible slightly before its slide finishes.
        Thread.sleep(forTimeInterval: 0.35)
        capture(app, "schedule-sunday-first-consecutive-dates")

        app.terminate()
        app.launch()
        app.tabBars.buttons["课表"].tap()
        app.buttons["schedule.settings"].tap()
        XCTAssertTrue(toggle.waitForExistence(timeout: 4))
        XCTAssertEqual(toggle.value as? String, "1")
        toggle.tap()
        app.buttons["schedule.settings.done"].tap()
        XCTAssertTrue(monday.waitForExistence(timeout: 4))
        XCTAssertEqual(sunday.label, "07-19")
        XCTAssertLessThan(monday.frame.midX, sunday.frame.midX)
    }

    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<5 {
            if element.isHittable { return }
            app.swipeUp()
        }
        XCTAssertTrue(element.isHittable)
    }

    private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
