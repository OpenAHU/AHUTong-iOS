import XCTest

final class AppShellUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testAndroidParityPrimaryScreens() {
        let app = XCUIApplication()
        app.launchArguments.append("--reset-onboarding")
        app.launchArguments.append("--demo-session")
        app.launch()

        XCTAssertTrue(app.staticTexts["onboarding.title"].waitForExistence(timeout: 8))
        waitForRendering()
        capture("01-community", app: app)

        app.buttons["onboarding.decline"].tap()
        XCTAssertTrue(app.staticTexts["隐私政策"].waitForExistence(timeout: 2))
        waitForRendering()
        capture("02-privacy", app: app)

        app.buttons["onboarding.decline"].tap()
        XCTAssertTrue(app.alerts["需要你的同意"].waitForExistence(timeout: 2))
        app.alerts.buttons["继续查看"].tap()

        app.buttons["onboarding.continue"].tap()
        XCTAssertTrue(app.staticTexts["温馨提示与免责声明"].waitForExistence(timeout: 2))
        waitForRendering()
        capture("03-disclaimer", app: app)
        app.buttons["onboarding.continue"].tap()

        XCTAssertTrue(app.staticTexts["screen.home"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["tab.home"].waitForExistence(timeout: 3))
        waitForRendering()
        capture("04-home", app: app)
        let campusCardBalance = app.buttons["campus-card.balance"]
        XCTAssertTrue(campusCardBalance.waitForExistence(timeout: 3))
        campusCardBalance.tap()
        XCTAssertTrue(app.images["campus-card.qr-image"].waitForExistence(timeout: 3))
        waitForRendering()
        capture("17-card-qrcode", app: app)

        let tabs = [
            ("schedule", "05-schedule"),
            ("tools", "06-tools"),
            ("settings", "07-settings"),
            ("home", "08-home-return")
        ]
        for (tabID, screenshotName) in tabs {
            let tab = app.buttons["tab.\(tabID)"]
            XCTAssertTrue(tab.waitForExistence(timeout: 2))
            tab.tap()
            switch tabID {
            case "schedule": XCTAssertTrue(app.buttons["回到当前周"].waitForExistence(timeout: 3))
            case "tools": XCTAssertTrue(app.buttons["tools.phone-book"].waitForExistence(timeout: 3))
            case "settings":
                XCTAssertTrue(app.buttons["settings.preferences"].waitForExistence(timeout: 3))
                XCTAssertTrue(app.buttons["settings.feedback"].waitForExistence(timeout: 3))
            default: XCTAssertTrue(app.staticTexts["screen.home"].waitForExistence(timeout: 3))
            }
            waitForRendering()
            capture(screenshotName, app: app)
        }

        app.buttons["tab.schedule"].tap()
        let demoCourse = app.buttons["schedule.course.demo-3"]
        XCTAssertTrue(demoCourse.waitForExistence(timeout: 4))
        demoCourse.tap()
        XCTAssertTrue(app.buttons["完成"].waitForExistence(timeout: 3))
        waitForRendering()
        capture("13-course-detail", app: app)
        app.terminate()
        app.launchArguments = ["--demo-session"]
        app.launch()
        XCTAssertTrue(app.staticTexts["screen.home"].waitForExistence(timeout: 5))

        app.buttons["tab.tools"].tap()
        let routes = [
            ("tools.phone-book", "搜索电话或部门", "09-phone-book"),
            ("tools.school-calendar", "school-calendar.", "10-school-calendar"),
            ("tools.weather", "天气设置", "11-weather"),
            ("tools.study-repository", "repository.downloads", "12-study-repository")
        ]

        for (linkID, marker, screenshotName) in routes {
            let link = app.buttons[linkID]
            XCTAssertTrue(link.waitForExistence(timeout: 4))
            link.tap()
            if marker == "school-calendar." {
                let calendarState = app.descendants(matching: .any)
                    .matching(NSPredicate(format: "identifier BEGINSWITH %@", marker))
                    .firstMatch
                XCTAssertTrue(calendarState.waitForExistence(timeout: 5))
            } else {
                XCTAssertTrue(app.buttons[marker].waitForExistence(timeout: 5))
            }
            waitForRendering()
            capture(screenshotName, app: app)
            restartAtTools(app)
        }


        let academicRoutes = [
            ("tools.grade", "grades.screen", "14-grades"),
            ("tools.exam", "exams.screen", "15-exams")
        ]
        for (linkID, marker, screenshotName) in academicRoutes {
            let link = app.buttons[linkID]
            XCTAssertTrue(link.waitForExistence(timeout: 4))
            link.tap()
            XCTAssertTrue(app.descendants(matching: .any)[marker].waitForExistence(timeout: 5))
            waitForRendering()
            capture(screenshotName, app: app)
            restartAtTools(app)
        }

        app.buttons["tab.settings"].tap()
        let contributors = app.buttons["settings.contributors"]
        XCTAssertTrue(contributors.waitForExistence(timeout: 4))
        contributors.tap()
        XCTAssertTrue(app.descendants(matching: .any)["contributors.screen"].waitForExistence(timeout: 4))
        XCTAssertTrue(app.staticTexts["加入我们"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["高玉灿（20级）"].waitForExistence(timeout: 3))
        waitForRendering()
        capture("16-contributors", app: app)

        app.terminate()
        app.launchArguments = ["--demo-session"]
        app.launch()
        XCTAssertTrue(app.staticTexts["screen.home"].waitForExistence(timeout: 5))
        app.buttons["tab.settings"].tap()
        app.buttons["settings.preferences"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["preferences.screen"].waitForExistence(timeout: 4))
        waitForRendering()
        capture("16-preferences", app: app)

        restartAtTools(app)
        app.buttons["tools.free-classroom"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["free-classroom.screen"].waitForExistence(timeout: 4))
        XCTAssertTrue(app.buttons["free-classroom.search"].waitForExistence(timeout: 4))
        app.buttons["free-classroom.search"].tap()
        XCTAssertTrue(app.staticTexts["201 教室"].waitForExistence(timeout: 4))
        waitForRendering()
        capture("18-free-classroom", app: app)

        restartAtTools(app)
        app.buttons["tools.lost-found"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["lost-found.screen"].waitForExistence(timeout: 4))
        XCTAssertTrue(app.buttons["lost-found.item.demo-lost-1"].waitForExistence(timeout: 4))
        waitForRendering()
        capture("19-lost-found", app: app)
        app.buttons["lost-found.item.demo-lost-1"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["lost-found.detail"].waitForExistence(timeout: 4))
        waitForRendering()
        capture("20-lost-found-detail", app: app)

        // The detail sheet contains its own ScrollView, so a downward gesture can
        // scroll instead of dismissing on some Simulator versions. Re-entering
        // the route makes the publish evidence independent of sheet physics.
        restartAtTools(app)
        app.buttons["tools.lost-found"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["lost-found.screen"].waitForExistence(timeout: 4))
        let publish = app.buttons["lost-found.publish"]
        XCTAssertTrue(publish.waitForExistence(timeout: 4))
        publish.tap()
        XCTAssertTrue(app.descendants(matching: .any)["lost-found.publish.sheet"].waitForExistence(timeout: 4))
        waitForRendering()
        capture("21-lost-found-publish", app: app)

        app.terminate()
        app.launchArguments = ["--demo-session"]
        app.launch()
        XCTAssertTrue(app.staticTexts["screen.home"].waitForExistence(timeout: 5))
        app.buttons["tab.tools"].tap()
        app.swipeUp()
        XCTAssertTrue(app.staticTexts["添加桌面课表微件"].waitForExistence(timeout: 4))
        waitForRendering()
        capture("22-widget-preview", app: app)
    }

    @MainActor
    func testAndroidParityLoginAndReminderSystemStates() {
        let app = XCUIApplication()
        app.launchArguments = ["--demo-consent"]
        app.launch()
        XCTAssertTrue(app.staticTexts["login.title"].waitForExistence(timeout: 5))
        waitForRendering()
        capture("00-login", app: app)

        app.terminate()
        app.launchArguments = ["--demo-consent", "--demo-login-state=error"]
        app.launch()
        XCTAssertTrue(app.buttons["login.submit"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["账号或密码错误"].waitForExistence(timeout: 3))
        waitForRendering()
        capture("state-error-login", app: app)

        app.terminate()
        app.launchArguments = ["--demo-consent", "--demo-session"]
        app.launch()
        XCTAssertTrue(app.staticTexts["screen.home"].waitForExistence(timeout: 5))
        app.buttons["tab.settings"].tap()
        app.buttons["settings.preferences"].tap()
        let reminder = app.buttons["preferences.course-reminders"]
        XCTAssertTrue(reminder.waitForExistence(timeout: 4))
        reminder.tap()
        expectation(for: NSPredicate(format: "value == %@", "开启"), evaluatedWith: reminder)
        waitForExpectations(timeout: 3)
        XCTAssertEqual(reminder.value as? String, "开启")
        waitForRendering()
        capture("23-course-reminder-enabled", app: app)
    }

    @MainActor
    func testAndroidParityLoadingEmptyAndErrorStates() {
        let app = XCUIApplication()
        for state in ["loading", "empty", "error"] {
            let arguments = ["--demo-session", "--demo-consent", "--demo-state=\(state)"]
            app.launchArguments = arguments
            app.launch()
            XCTAssertTrue(app.staticTexts["screen.home"].waitForExistence(timeout: 5))
            waitForRendering()
            capture("state-\(state)-home", app: app)

            app.buttons["tab.schedule"].tap()
            XCTAssertTrue(app.buttons["回到当前周"].waitForExistence(timeout: 6))
            waitForRendering()
            capture("state-\(state)-schedule", app: app)

            app.terminate()
            app.launchArguments = arguments
            app.launch()
            XCTAssertTrue(app.staticTexts["screen.home"].waitForExistence(timeout: 5))
            app.buttons["tab.tools"].tap()
            app.buttons["tools.grade"].tap()
            XCTAssertTrue(app.descendants(matching: .any)["grades.screen"].waitForExistence(timeout: 4))
            waitForRendering()
            capture("state-\(state)-grades", app: app)

            app.terminate()
            app.launchArguments = arguments
            app.launch()
            XCTAssertTrue(app.staticTexts["screen.home"].waitForExistence(timeout: 5))
            app.buttons["tab.tools"].tap()
            app.buttons["tools.exam"].tap()
            XCTAssertTrue(app.descendants(matching: .any)["exams.screen"].waitForExistence(timeout: 4))
            waitForRendering()
            capture("state-\(state)-exams", app: app)

            app.terminate()
            app.launchArguments = arguments
            app.launch()
            XCTAssertTrue(app.staticTexts["screen.home"].waitForExistence(timeout: 5))
            app.buttons["tab.tools"].tap()
            app.buttons["tools.free-classroom"].tap()
            XCTAssertTrue(app.buttons["free-classroom.search"].waitForExistence(timeout: 4))
            app.buttons["free-classroom.search"].tap()
            let classroomState = app.descendants(matching: .any)["free-classroom.\(state)"]
            XCTAssertTrue(classroomState.waitForExistence(timeout: 4))
            waitForRendering()
            capture("state-\(state)-free-classroom", app: app)

            app.terminate()
            app.launchArguments = arguments
            app.launch()
            XCTAssertTrue(app.staticTexts["screen.home"].waitForExistence(timeout: 5))
            app.buttons["tab.tools"].tap()
            app.buttons["tools.lost-found"].tap()
            let lostFoundState = app.descendants(matching: .any)["lost-found.\(state)"]
            XCTAssertTrue(lostFoundState.waitForExistence(timeout: 4))
            waitForRendering()
            capture("state-\(state)-lost-found", app: app)
            app.terminate()
        }
    }

    @MainActor
    func testNativeNavigationBarEdgeAndContentPopGestures() {
        let app = XCUIApplication()
        app.launchArguments = ["--demo-consent", "--demo-session"]
        app.launch()
        XCTAssertTrue(app.staticTexts["screen.home"].waitForExistence(timeout: 5))
        app.buttons["tab.tools"].tap()

        func openPhoneBook() {
            let link = app.buttons["tools.phone-book"]
            XCTAssertTrue(link.waitForExistence(timeout: 4))
            link.tap()
            XCTAssertTrue(app.buttons["搜索电话或部门"].waitForExistence(timeout: 4))
            XCTAssertTrue(app.navigationBars.firstMatch.waitForExistence(timeout: 3))
            XCTAssertTrue(app.navigationBars.buttons.firstMatch.exists)
        }

        openPhoneBook()
        let leftEdge = app.coordinate(withNormalizedOffset: CGVector(dx: 0.01, dy: 0.5))
        leftEdge.press(
            forDuration: 0.05,
            thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)),
            withVelocity: .fast,
            thenHoldForDuration: 0
        )
        XCTAssertTrue(app.buttons["tools.phone-book"].waitForExistence(timeout: 4))

        openPhoneBook()
        let content = app.coordinate(withNormalizedOffset: CGVector(dx: 0.42, dy: 0.55))
        content.press(
            forDuration: 0.05,
            thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.55)),
            withVelocity: .fast,
            thenHoldForDuration: 0
        )
        XCTAssertTrue(app.buttons["tools.phone-book"].waitForExistence(timeout: 4))
    }

    @MainActor
    func testAndroidParityPaymentsAndOperations() {
        let app = XCUIApplication()
        launchDemo(app)

        let recharge = app.buttons["campus-card.recharge"]
        XCTAssertTrue(recharge.waitForExistence(timeout: 5))
        recharge.tap()
        XCTAssertTrue(app.descendants(matching: .any)["payment.card.screen"].waitForExistence(timeout: 4))
        waitForRendering()
        capture("24-card-recharge", app: app)
        enter("10", into: app.textFields["payment.card.amount"], app: app)
        app.buttons["payment.card.state"].tap()
        XCTAssertTrue(app.staticTexts["确认支付"].waitForExistence(timeout: 3))
        waitForRendering()
        capture("25-card-recharge-dialog", app: app)
        app.buttons["payment.card.bank"].tap()
        waitForPaymentResult("payment.card.state", app: app)
        waitForRendering()
        capture("26-card-recharge-success", app: app)

        launchDemo(app)
        openHomePayment("home.payment.bathroom", marker: "payment.bathroom.screen", app: app)
        waitForRendering()
        capture("27-bathroom-payment", app: app)
        enter("13800000000", into: app.textFields["payment.bathroom.phone"], app: app)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "现金金额")).firstMatch.waitForExistence(timeout: 3))
        enter("8", into: app.textFields["payment.bathroom.amount"], app: app)
        app.buttons["payment.bathroom.state"].tap()
        XCTAssertTrue(app.staticTexts["请输入校园卡密码"].waitForExistence(timeout: 3))
        waitForRendering()
        capture("28-bathroom-payment-dialog", app: app)
        enter("123456", into: app.secureTextFields["payment.bathroom.password"], app: app)
        app.buttons["payment.bathroom.confirm"].tap()
        waitForPaymentResult("payment.bathroom.state", app: app)
        waitForRendering()
        capture("29-bathroom-payment-success", app: app)

        launchDemo(app)
        openHomePayment("home.payment.electricity", marker: "payment.electricity.screen", app: app)
        waitForRendering()
        capture("30-electricity-payment", app: app)
        choose("磬苑校区", from: "payment.electricity.campus", app: app)
        choose("竹园", from: "payment.electricity.building", app: app)
        choose("3 层", from: "payment.electricity.floor", app: app)
        choose("305", from: "payment.electricity.room", app: app)
        enter("20", into: app.textFields["payment.electricity.amount"], app: app)
        app.buttons["payment.electricity.state"].tap()
        XCTAssertTrue(app.staticTexts["请输入校园卡密码"].waitForExistence(timeout: 3))
        waitForRendering()
        capture("31-electricity-payment-dialog", app: app)
        enter("123456", into: app.secureTextFields["payment.electricity.password"], app: app)
        app.buttons["payment.electricity.confirm"].tap()
        waitForPaymentResult("payment.electricity.state", app: app)
        waitForRendering()
        capture("32-electricity-payment-success", app: app)

        launchDemo(app)
        app.buttons["tab.settings"].tap()
        let debug = app.buttons["settings.debug"]
        XCTAssertTrue(debug.waitForExistence(timeout: 4))
        debug.tap()
        XCTAssertTrue(app.descendants(matching: .any)["operations.debug.screen"].waitForExistence(timeout: 5))
        waitForRendering()
        capture("33-operations-debug", app: app)
    }

    @MainActor
    private func capture(_ name: String, app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "android-parity-\(name)"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor
    private func restartAtTools(_ app: XCUIApplication) {
        app.terminate()
        app.launchArguments = ["--demo-session"]
        app.launch()
        XCTAssertTrue(app.staticTexts["screen.home"].waitForExistence(timeout: 5))
        let toolsTab = app.buttons["tab.tools"]
        XCTAssertTrue(toolsTab.waitForExistence(timeout: 3))
        toolsTab.tap()
        XCTAssertTrue(app.buttons["tools.phone-book"].waitForExistence(timeout: 3))
    }

    @MainActor
    private func launchDemo(_ app: XCUIApplication) {
        app.terminate()
        app.launchArguments = ["--demo-consent", "--demo-session"]
        app.launch()
        XCTAssertTrue(app.staticTexts["screen.home"].waitForExistence(timeout: 5))
    }

    @MainActor
    private func openHomePayment(_ identifier: String, marker: String, app: XCUIApplication) {
        let link = app.buttons[identifier]
        if !link.isHittable { app.swipeUp() }
        XCTAssertTrue(link.waitForExistence(timeout: 4))
        link.tap()
        XCTAssertTrue(app.descendants(matching: .any)[marker].waitForExistence(timeout: 4))
    }

    @MainActor
    private func enter(_ value: String, into field: XCUIElement, app: XCUIApplication) {
        XCTAssertTrue(field.waitForExistence(timeout: 3))
        field.tap()
        field.typeText(value)
        app.swipeDown()
    }

    @MainActor
    private func choose(_ option: String, from identifier: String, app: XCUIApplication) {
        let menu = app.buttons[identifier]
        XCTAssertTrue(menu.waitForExistence(timeout: 3))
        menu.tap()
        let choice = app.buttons[option]
        XCTAssertTrue(choice.waitForExistence(timeout: 3))
        choice.tap()
    }

    @MainActor
    private func waitForPaymentResult(_ identifier: String, app: XCUIApplication) {
        let state = app.buttons[identifier]
        expectation(
            for: NSPredicate(format: "label CONTAINS %@", "支付成功"),
            evaluatedWith: state
        )
        waitForExpectations(timeout: 4)
    }

    private func waitForRendering() {
        let rendered = expectation(description: "界面完成渲染")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            rendered.fulfill()
        }
        wait(for: [rendered], timeout: 2)
    }
}
