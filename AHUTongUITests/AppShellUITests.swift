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
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 3), "四入口必须由系统 Tab Bar 承载")
        XCTAssertTrue(tabButton("home", app: app).waitForExistence(timeout: 3))
        waitForRendering()
        capture("04-home", app: app)
        let campusCardBalance = app.buttons["campus-card.balance"]
        XCTAssertTrue(campusCardBalance.waitForExistence(timeout: 3))
        campusCardBalance.tap()
        XCTAssertTrue(app.images["campus-card.qr-image"].waitForExistence(timeout: 3))
        let campusCardQRPanel = app.otherElements["campus-card.qr-panel"]
        XCTAssertTrue(campusCardQRPanel.waitForExistence(timeout: 3))
        XCTAssertLessThan(campusCardQRPanel.frame.height, 300, "二维码面板应按内容收紧，而不是保留固定大高度")
        waitForRendering()
        capture("17-card-qrcode", app: app)

        let tabs = [
            ("schedule", "05-schedule"),
            ("tools", "06-tools"),
            ("settings", "07-settings"),
            ("home", "08-home-return")
        ]
        for (tabID, screenshotName) in tabs {
            let tab = tabButton(tabID, app: app)
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

        tabButton("schedule", app: app).tap()
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

        tabButton("tools", app: app).tap()
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
            if marker == "exams.screen" {
                let examCard = app.descendants(matching: .any)
                    .matching(NSPredicate(format: "identifier BEGINSWITH %@", "exams.card.操作系统|"))
                    .firstMatch
                XCTAssertTrue(examCard.waitForExistence(timeout: 4))
            }
            waitForRendering()
            capture(screenshotName, app: app)
            restartAtTools(app)
        }

        tabButton("settings", app: app).tap()
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
        tabButton("settings", app: app).tap()
        app.buttons["settings.preferences"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["preferences.screen"].waitForExistence(timeout: 4))
        XCTAssertFalse(app.staticTexts["液态玻璃"].exists)
        XCTAssertFalse(app.buttons["preferences.liquid-glass"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["preferences.native-tab-bar"].exists)
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
        tabButton("tools", app: app).tap()
        app.swipeUp()
        XCTAssertTrue(app.staticTexts["添加桌面课表微件"].waitForExistence(timeout: 4))
        waitForRendering()
        capture("22-widget-preview", app: app)
    }

    @MainActor
    func testScheduleSupportsHorizontalWeekPaging() {
        let app = XCUIApplication()
        app.launchArguments = ["--demo-consent", "--demo-session"]
        app.launch()

        XCTAssertTrue(app.staticTexts["screen.home"].waitForExistence(timeout: 5))
        tabButton("schedule", app: app).tap()

        let pager = app.descendants(matching: .any)["schedule.week-pager"]
        let firstWeek = app.buttons["schedule.week.1"]
        let secondWeek = app.buttons["schedule.week.2"]
        let demoCourse = app.buttons["schedule.course.demo-3"]
        XCTAssertTrue(pager.waitForExistence(timeout: 4))
        XCTAssertTrue(firstWeek.waitForExistence(timeout: 2))
        XCTAssertTrue(demoCourse.waitForExistence(timeout: 4))
        XCTAssertTrue(firstWeek.isSelected)

        pager.swipeLeft()
        expectation(for: NSPredicate(format: "selected == true"), evaluatedWith: secondWeek)
        waitForExpectations(timeout: 3)
        XCTAssertEqual(pager.value as? String, "第2周")

        pager.swipeRight()
        expectation(for: NSPredicate(format: "selected == true"), evaluatedWith: firstWeek)
        waitForExpectations(timeout: 3)
        XCTAssertEqual(pager.value as? String, "第1周")
        XCTAssertTrue(demoCourse.waitForExistence(timeout: 3))

        app.buttons["schedule.settings"].tap()
        let overview = app.buttons["schedule.settings.overview"]
        XCTAssertTrue(overview.waitForExistence(timeout: 3))
        overview.tap()
        expectation(for: NSPredicate(format: "value == %@", "开启"), evaluatedWith: overview)
        waitForExpectations(timeout: 3)
        app.buttons["schedule.settings.done"].tap()
        XCTAssertTrue(app.buttons["schedule.course.demo-5"].waitForExistence(timeout: 4))

        app.buttons["schedule.settings"].tap()
        let nextSemester = app.buttons["schedule.settings.next-semester"]
        XCTAssertTrue(nextSemester.waitForExistence(timeout: 3))
        nextSemester.tap()
        expectation(for: NSPredicate(format: "value == %@", "开启"), evaluatedWith: nextSemester)
        waitForExpectations(timeout: 3)
        app.buttons["schedule.settings.done"].tap()
        XCTAssertTrue(app.buttons["schedule.course.demo-next-1"].waitForExistence(timeout: 5))
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
        tabButton("settings", app: app).tap()
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

            tabButton("schedule", app: app).tap()
            XCTAssertTrue(app.buttons["回到当前周"].waitForExistence(timeout: 6))
            waitForRendering()
            capture("state-\(state)-schedule", app: app)

            app.terminate()
            app.launchArguments = arguments
            app.launch()
            XCTAssertTrue(app.staticTexts["screen.home"].waitForExistence(timeout: 5))
            openTool("tools.grade", app: app)
            XCTAssertTrue(app.descendants(matching: .any)["grades.screen"].waitForExistence(timeout: 4))
            waitForRendering()
            capture("state-\(state)-grades", app: app)

            app.terminate()
            app.launchArguments = arguments
            app.launch()
            XCTAssertTrue(app.staticTexts["screen.home"].waitForExistence(timeout: 5))
            tabButton("tools", app: app).tap()
            let toolsExam = app.buttons["tools.exam"]
            if toolsExam.waitForExistence(timeout: 2) {
                toolsExam.tap()
            } else {
                tabButton("home", app: app).tap()
                let homeExam = app.buttons["home.widget.exam"]
                XCTAssertTrue(homeExam.waitForExistence(timeout: 4))
                homeExam.tap()
            }
            XCTAssertTrue(app.descendants(matching: .any)["exams.screen"].waitForExistence(timeout: 4))
            waitForRendering()
            capture("state-\(state)-exams", app: app)

            app.terminate()
            app.launchArguments = arguments
            app.launch()
            XCTAssertTrue(app.staticTexts["screen.home"].waitForExistence(timeout: 5))
            openTool("tools.free-classroom", app: app)
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
            openTool("tools.lost-found", app: app)
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
        tabButton("tools", app: app).tap()

        func openPhoneBook() {
            let link = app.buttons["tools.phone-book"]
            XCTAssertTrue(link.waitForExistence(timeout: 4))
            link.tap()
            XCTAssertTrue(app.buttons["搜索电话或部门"].waitForExistence(timeout: 4))
            XCTAssertTrue(app.navigationBars.firstMatch.waitForExistence(timeout: 3))
            XCTAssertTrue(app.navigationBars.buttons.firstMatch.exists)
            XCTAssertFalse(app.tabBars.firstMatch.isHittable)
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
        XCTAssertTrue(tabButton("tools", app: app).waitForExistence(timeout: 3))

        openPhoneBook()
        for y in [0.68, 0.82] where !app.buttons["tools.phone-book"].exists {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: y)).press(
                forDuration: 0.12,
                thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.96, dy: y)),
                withVelocity: .slow,
                thenHoldForDuration: 0.05
            )
            _ = app.buttons["tools.phone-book"].waitForExistence(timeout: 2)
        }
        XCTAssertTrue(app.buttons["tools.phone-book"].waitForExistence(timeout: 4))
        XCTAssertTrue(tabButton("tools", app: app).waitForExistence(timeout: 3))
    }

    @MainActor
    func testAndroidParityPaymentsAndOperations() {
        let app = XCUIApplication()
        launchDemo(app)
        setCMBPreference(false, app: app)
        launchDemo(app)

        let recharge = app.buttons["campus-card.recharge"]
        XCTAssertTrue(recharge.waitForExistence(timeout: 5))
        recharge.tap()
        XCTAssertTrue(app.descendants(matching: .any)["payment.card.screen"].waitForExistence(timeout: 4))
        let cmbEntry = app.buttons["payment.card.cmb-entry"]
        XCTAssertTrue(cmbEntry.waitForExistence(timeout: 4))
        cmbEntry.tap()
        XCTAssertTrue(app.staticTexts["使用招商银行充值"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["是否以后都默认使用招商银行充值？"].exists)
        XCTAssertTrue(app.buttons["payment.card.cmb-cancel"].exists)
        XCTAssertTrue(app.buttons["payment.card.cmb-once"].exists)
        XCTAssertTrue(app.buttons["payment.card.cmb-always"].exists)
        app.buttons["payment.card.cmb-cancel"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["payment.card.screen"].waitForExistence(timeout: 3))
        cmbEntry.tap()
        app.buttons["payment.card.cmb-once"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["payment.cmb.screen"].waitForExistence(timeout: 4))

        launchDemo(app)
        let rechargeAfterOneTimeChoice = app.buttons["campus-card.recharge"]
        XCTAssertTrue(rechargeAfterOneTimeChoice.waitForExistence(timeout: 5))
        rechargeAfterOneTimeChoice.tap()
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
        app.buttons["campus-card.recharge"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["payment.card.screen"].waitForExistence(timeout: 4))
        app.buttons["payment.card.cmb-entry"].tap()
        app.buttons["payment.card.cmb-always"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["payment.cmb.screen"].waitForExistence(timeout: 4))
        launchDemo(app)
        app.buttons["campus-card.recharge"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["payment.cmb.screen"].waitForExistence(timeout: 4))
        launchDemo(app)
        setCMBPreference(false, app: app)

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
        tabButton("settings", app: app).tap()
        XCTAssertFalse(app.buttons["settings.debug"].exists)
        XCTAssertFalse(app.staticTexts["Debug"].exists)
        let appCard = app.descendants(matching: .any)
            .matching(identifier: "settings.app-card")
            .firstMatch
        XCTAssertTrue(appCard.waitForExistence(timeout: 4))
        appCard.tap(withNumberOfTaps: 8, numberOfTouches: 1)
        XCTAssertTrue(app.descendants(matching: .any)["operations.debug.screen"].waitForExistence(timeout: 5))
        waitForRendering()
        capture("33-operations-debug", app: app)
    }

    @MainActor
    func testEvaluationNetworkRechargeAndCMBPreference() {
        let app = XCUIApplication()
        launchDemo(app)
        tabButton("tools", app: app).tap()

        let evaluation = app.buttons["tools.evaluation"]
        XCTAssertTrue(evaluation.waitForExistence(timeout: 4))
        evaluation.tap()
        XCTAssertTrue(app.descendants(matching: .any)["evaluation.screen"].waitForExistence(timeout: 4))
        let evaluationTarget = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH %@", "evaluation.target."))
            .firstMatch
        XCTAssertTrue(evaluationTarget.waitForExistence(timeout: 4))
        waitForRendering()
        capture("34-evaluation", app: app)

        launchDemo(app)
        tabButton("tools", app: app).tap()
        let networkRecharge = app.buttons["tools.network-recharge"]
        XCTAssertTrue(networkRecharge.waitForExistence(timeout: 4))
        scrollUpUntilHittable(networkRecharge, app: app)
        networkRecharge.tap()
        XCTAssertTrue(app.descendants(matching: .any)["payment.network.screen"].waitForExistence(timeout: 4))
        XCTAssertTrue(app.descendants(matching: .any)["payment.network.account"].waitForExistence(timeout: 4))
        let quickAmount = app.buttons["payment.network.quick-amount"].firstMatch
        XCTAssertTrue(quickAmount.waitForExistence(timeout: 4))
        scrollUpUntilHittable(quickAmount, app: app)
        quickAmount.tap()
        let continueButton = app.buttons["payment.network.continue"]
        XCTAssertTrue(continueButton.waitForExistence(timeout: 4))
        scrollUpUntilHittable(continueButton, app: app)
        continueButton.tap()
        let networkPassword = app.secureTextFields["payment.network.password"]
        XCTAssertTrue(networkPassword.waitForExistence(timeout: 3))
        enter("123456", into: networkPassword, app: app)
        app.buttons["payment.network.confirm"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["payment.network.demo-success"].waitForExistence(timeout: 4))
        waitForRendering()
        capture("35-network-recharge", app: app)

        launchDemo(app)
        tabButton("settings", app: app).tap()
        app.buttons["settings.preferences"].tap()
        let preference = app.buttons["preferences.cmb-card-recharge"]
        XCTAssertTrue(preference.waitForExistence(timeout: 4))
        let initialValue = preference.value as? String
        let changedValue = initialValue == "开启" ? "关闭" : "开启"
        preference.tap()
        expectation(
            for: NSPredicate(format: "value == %@", changedValue),
            evaluatedWith: preference
        )
        waitForExpectations(timeout: 3)
        waitForRendering()
        capture("36-cmb-preference", app: app)
        preference.tap()
        expectation(
            for: NSPredicate(format: "value == %@", initialValue ?? "关闭"),
            evaluatedWith: preference
        )
        waitForExpectations(timeout: 3)
    }

    @MainActor
    func testCompactHomeWeatherOpensWeatherInsteadOfSchedule() {
        let app = XCUIApplication()
        app.launchArguments = [
            "--demo-consent",
            "--demo-session",
            "--demo-weather-compact",
            #"--demo-endpoint-weather={"city":"合肥市","weather":"晴","weather_code":"100","temperature":28,"humidity":65,"uv":6}"#
        ]
        app.launch()

        XCTAssertTrue(app.staticTexts["screen.home"].waitForExistence(timeout: 5))
        let compactWeather = app.buttons["home.weather.compact"]
        XCTAssertTrue(compactWeather.waitForExistence(timeout: 5))
        compactWeather.tap()

        XCTAssertTrue(app.buttons["天气设置"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["回到当前周"].exists)
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
        let toolsTab = tabButton("tools", app: app)
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
    private func setCMBPreference(_ enabled: Bool, app: XCUIApplication) {
        tabButton("settings", app: app).tap()
        let preferences = app.buttons["settings.preferences"]
        XCTAssertTrue(preferences.waitForExistence(timeout: 4))
        preferences.tap()
        let preference = app.buttons["preferences.cmb-card-recharge"]
        XCTAssertTrue(preference.waitForExistence(timeout: 4))
        let expectedValue = enabled ? "开启" : "关闭"
        if preference.value as? String != expectedValue {
            preference.tap()
            expectation(
                for: NSPredicate(format: "value == %@", expectedValue),
                evaluatedWith: preference
            )
            waitForExpectations(timeout: 3)
        }
    }

    @MainActor
    private func scrollUpUntilHittable(
        _ element: XCUIElement,
        app: XCUIApplication,
        maximumAttempts: Int = 4
    ) {
        var attempts = 0
        while !element.isHittable && attempts < maximumAttempts {
            app.swipeUp()
            attempts += 1
        }
        XCTAssertTrue(element.isHittable)
    }

    @MainActor
    private func tabButton(_ identifier: String, app: XCUIApplication) -> XCUIElement {
        let titles = [
            "home": "主页",
            "schedule": "课表",
            "tools": "小工具",
            "settings": "设置"
        ]
        return app.tabBars.buttons[titles[identifier] ?? identifier]
    }

    @MainActor
    private func openTool(_ identifier: String, app: XCUIApplication) {
        let toolsTab = tabButton("tools", app: app)
        XCTAssertTrue(toolsTab.waitForExistence(timeout: 2))
        if !toolsTab.isSelected {
            toolsTab.tap()
        }

        // In the long loading/empty/error chain, the first synthesized tap can
        // complete without changing TabView selection. Verify the selected
        // state and retry only that local transition instead of sleeping.
        if !waitForSelection(of: toolsTab, timeout: 2) {
            toolsTab.tap()
        }
        XCTAssertTrue(
            waitForSelection(of: toolsTab, timeout: 2),
            "The tools tab must be selected before looking up \(identifier)"
        )

        let tool = app.buttons[identifier]
        var attempts = 0
        while !tool.waitForExistence(timeout: 1) && attempts < 3 {
            app.swipeUp()
            attempts += 1
        }
        XCTAssertTrue(
            tool.exists,
            "Expected \(identifier) in the selected tools screen"
        )
        if !tool.isHittable {
            scrollUpUntilHittable(tool, app: app, maximumAttempts: 3)
        }
        tool.tap()
    }

    @MainActor
    private func waitForSelection(
        of element: XCUIElement,
        timeout: TimeInterval
    ) -> Bool {
        if element.isSelected { return true }
        let selected = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "selected == true"),
            object: element
        )
        return XCTWaiter.wait(for: [selected], timeout: timeout) == .completed
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
