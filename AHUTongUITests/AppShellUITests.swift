import XCTest

final class AppShellUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testOnboardingPrivacyDisclaimerAndCommunityReachHome() {
        let app = XCUIApplication()
        app.launchArguments.append("--reset-onboarding")
        app.launchArguments.append("--demo-session")
        app.launch()

        XCTAssertTrue(app.staticTexts["onboarding.title"].waitForExistence(timeout: 8))
        waitForRendering()
        XCTAssertTrue(app.staticTexts["隐私政策"].exists)
        capture("01-privacy", app: app)

        app.buttons["onboarding.decline"].tap()
        XCTAssertTrue(app.staticTexts["温馨提示与免责声明"].waitForExistence(timeout: 2))
        waitForRendering()
        capture("02-disclaimer", app: app)

        app.buttons["onboarding.continue"].tap()
        XCTAssertTrue(app.staticTexts["商业合作"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.buttons["onboarding.community.qq-group"].waitForExistence(timeout: 2))
        waitForRendering()
        capture("03-community", app: app)
        app.buttons["onboarding.decline"].tap()

        XCTAssertTrue(app.staticTexts["screen.home"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testSchoolCalendarFromTools() {
        let app = XCUIApplication()
        launchDemo(app)
        defer { app.terminate() }
        openTool("tools.school-calendar", app: app)
        XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@", "school-calendar.")).firstMatch.waitForExistence(timeout: 5))
        capture("route-SchoolCalendar", app: app)
    }

    @MainActor
    func testStudyRepositoryFromTools() {
        let app = XCUIApplication()
        launchDemo(app)
        defer { app.terminate() }
        openTool("tools.study-repository", app: app)
        XCTAssertTrue(app.buttons["repository.downloads"].waitForExistence(timeout: 5))
        capture("route-StudyRepository", app: app)
    }

    @MainActor
    func testGradesFromTools() {
        let app = XCUIApplication()
        launchDemo(app)
        defer { app.terminate() }
        openTool("tools.grade", app: app)
        XCTAssertTrue(app.descendants(matching: .any)["grades.screen"].waitForExistence(timeout: 5))
        capture("route-Grades", app: app)
    }

    @MainActor
    func testExamsFromTools() {
        let app = XCUIApplication()
        launchDemo(app)
        defer { app.terminate() }
        openTool("tools.exam", app: app)
        XCTAssertTrue(app.descendants(matching: .any)["exams.screen"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@", "exams.card.操作系统|")).firstMatch.waitForExistence(timeout: 4))
        capture("route-Exams", app: app)
    }

    @MainActor
    func testFreeClassroomsFromTools() {
        let app = XCUIApplication()
        launchDemo(app)
        defer { app.terminate() }
        openTool("tools.free-classroom", app: app)
        XCTAssertTrue(app.descendants(matching: .any)["free-classroom.screen"].waitForExistence(timeout: 5))
        app.buttons["free-classroom.search"].tap()
        XCTAssertTrue(app.staticTexts["201 教室"].waitForExistence(timeout: 4))
        capture("route-FreeClassrooms", app: app)
    }

    @MainActor
    func testLostFoundDetailFromTools() {
        let app = XCUIApplication()
        launchDemo(app)
        defer { app.terminate() }
        openTool("tools.lost-found", app: app)
        XCTAssertTrue(app.descendants(matching: .any)["lost-found.screen"].waitForExistence(timeout: 5))
        app.buttons["lost-found.item.demo-lost-1"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["lost-found.detail"].waitForExistence(timeout: 4))
        capture("route-LostFoundDetail", app: app)
    }

    @MainActor
    func testLostFoundPublishFromTools() {
        let app = XCUIApplication()
        launchDemo(app)
        defer { app.terminate() }
        openTool("tools.lost-found", app: app)
        XCTAssertTrue(app.descendants(matching: .any)["lost-found.screen"].waitForExistence(timeout: 5))
        app.buttons["lost-found.publish"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["lost-found.publish.sheet"].waitForExistence(timeout: 4))
        capture("route-LostFoundPublish", app: app)
    }


    @MainActor
    func testScheduleSupportsHorizontalWeekPaging() {
        let app = XCUIApplication()
        app.launchArguments = ["--demo-consent", "--demo-session"]
        app.launch()

        XCTAssertTrue(app.staticTexts["screen.home"].waitForExistence(timeout: 5))
        tabButton("schedule", app: app).tap()
        // Restore the fixture through the UI so persistent settings from a
        // previous run cannot select next-semester courses. Launch overrides
        // would also mask the setting changes tested below.
        app.buttons["schedule.settings"].tap()
        for identifier in ["schedule.settings.overview", "schedule.settings.next-semester"] {
            let toggle = app.switches[identifier]
            XCTAssertTrue(toggle.waitForExistence(timeout: 3))
            if toggle.value as? String == "1" { toggle.tapNativeSwitch() }
            XCTAssertEqual(toggle.value as? String, "0")
        }
        app.buttons["schedule.settings.done"].tap()

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
        let overview = app.switches["schedule.settings.overview"]
        XCTAssertTrue(overview.waitForExistence(timeout: 3))
        overview.tapNativeSwitch()
        expectation(for: NSPredicate(format: "value == %@", "1"), evaluatedWith: overview)
        waitForExpectations(timeout: 3)
        app.buttons["schedule.settings.done"].tap()
        XCTAssertTrue(app.buttons["schedule.course.demo-5"].waitForExistence(timeout: 4))

        app.buttons["schedule.settings"].tap()
        let nextSemester = app.switches["schedule.settings.next-semester"]
        XCTAssertTrue(nextSemester.waitForExistence(timeout: 3))
        nextSemester.tapNativeSwitch()
        expectation(for: NSPredicate(format: "value == %@", "1"), evaluatedWith: nextSemester)
        waitForExpectations(timeout: 3)
        app.buttons["schedule.settings.done"].tap()
        XCTAssertTrue(app.buttons["schedule.course.demo-next-1"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testAndroidParityLoginAndReminderSystemStates() {
        let app = XCUIApplication()
        app.launchArguments = ["--reset-onboarding", "--demo-consent"]
        app.launch()
        XCTAssertTrue(app.staticTexts["login.title"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["login.experience"].exists)
        waitForRendering()
        capture("00-login", app: app)

        app.buttons["login.experience"].tap()
        XCTAssertTrue(tabButton("schedule", app: app).waitForExistence(timeout: 5))
        XCTAssertTrue(tabButton("settings", app: app).exists)
        XCTAssertFalse(tabButton("home", app: app).exists)
        app.terminate()
        app.launchArguments = ["--demo-consent"]
        app.launch()
        XCTAssertTrue(tabButton("schedule", app: app).waitForExistence(timeout: 5))

        app.terminate()
        app.launchArguments = ["--reset-onboarding", "--demo-consent", "--demo-login-state=error"]
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
        let reminder = app.switches["preferences.course-reminders"]
        XCTAssertTrue(reminder.waitForExistence(timeout: 4))
        if reminder.value as? String == "1" {
            reminder.tapNativeSwitch()
            expectation(for: NSPredicate(format: "value == %@", "0"), evaluatedWith: reminder)
            waitForExpectations(timeout: 3)
        }
        reminder.tapNativeSwitch()
        expectation(for: NSPredicate(format: "value == %@", "1"), evaluatedWith: reminder)
        waitForExpectations(timeout: 3)
        XCTAssertEqual(reminder.value as? String, "1")
        waitForRendering()
        capture("23-course-reminder-enabled", app: app)
    }

    @MainActor
    func testDeclinedPrivacyUsesScheduleOnlyExperienceAccount() {
        let app = XCUIApplication()
        app.launchArguments = ["--reset-onboarding"]
        app.launch()

        XCTAssertTrue(app.staticTexts["隐私政策"].waitForExistence(timeout: 8))
        app.buttons["onboarding.decline"].tap()
        XCTAssertTrue(app.staticTexts["温馨提示与免责声明"].waitForExistence(timeout: 3))
        app.buttons["onboarding.continue"].tap()
        XCTAssertTrue(app.staticTexts["商业合作"].waitForExistence(timeout: 3))
        app.buttons["onboarding.decline"].tap()

        let login = app.buttons["login.submit"]
        XCTAssertTrue(login.waitForExistence(timeout: 5))
        login.tap()

        XCTAssertTrue(tabButton("schedule", app: app).waitForExistence(timeout: 5))
        XCTAssertTrue(tabButton("settings", app: app).exists)
        XCTAssertFalse(tabButton("home", app: app).exists)
        XCTAssertFalse(tabButton("tools", app: app).exists)
        XCTAssertTrue(app.buttons["schedule.settings"].waitForExistence(timeout: 4))
        tabButton("settings", app: app).tap()
        XCTAssertTrue(app.buttons["settings.preferences"].waitForExistence(timeout: 4))
        XCTAssertTrue(app.buttons["settings.account-login"].exists)
        app.buttons["settings.preferences"].tap()
        XCTAssertTrue(app.switches["preferences.privacy-consent"].waitForExistence(timeout: 4))
        XCTAssertTrue(app.buttons["preferences.privacy-policy"].exists)
        XCTAssertFalse(app.buttons["preferences.login"].exists)
        XCTAssertFalse(app.switches["preferences.cmb-card-recharge"].exists)
    }

    @MainActor
    func testScheduleLoadingEmptyAndErrorStates() {
        let app = XCUIApplication()
        defer { app.terminate() }
        for state in ["loading", "empty", "error"] {
            app.terminate()
            app.launchEnvironment["AHUTONG_CI_DISABLE_LIVE_PAYMENT"] = "1"
            app.launchArguments = ["--demo-session", "--demo-consent", "--demo-state=\(state)"]
            app.launch()
            XCTAssertTrue(app.staticTexts["screen.home"].waitForExistence(timeout: 5))
            tabButton("schedule", app: app).tap()
            XCTAssertTrue(app.descendants(matching: .any)["schedule.\(state)"].waitForExistence(timeout: 5))
            capture("state-\(state)-schedule", app: app)
        }
    }

    @MainActor
    func testGradesLoadingEmptyAndErrorStates() {
        let app = XCUIApplication()
        defer { app.terminate() }
        for state in ["loading", "empty", "error"] {
            app.terminate()
            app.launchEnvironment["AHUTONG_CI_DISABLE_LIVE_PAYMENT"] = "1"
            app.launchArguments = ["--demo-session", "--demo-consent", "--demo-state=\(state)"]
            app.launch()
            XCTAssertTrue(app.staticTexts["screen.home"].waitForExistence(timeout: 5))
            openTool("tools.grade", app: app)
            XCTAssertTrue(app.descendants(matching: .any)["grades.screen"].waitForExistence(timeout: 5))
            switch state {
            case "loading": XCTAssertTrue(app.activityIndicators.firstMatch.waitForExistence(timeout: 4))
            case "empty": XCTAssertTrue(app.staticTexts["该学期目前没有任何成绩"].waitForExistence(timeout: 4))
            default: XCTAssertTrue(app.buttons["重试"].waitForExistence(timeout: 4))
            }
            capture("state-\(state)-grades", app: app)
        }
    }

    @MainActor
    func testExamsLoadingEmptyAndErrorStates() {
        let app = XCUIApplication()
        defer { app.terminate() }
        for state in ["loading", "empty", "error"] {
            app.terminate()
            app.launchEnvironment["AHUTONG_CI_DISABLE_LIVE_PAYMENT"] = "1"
            app.launchArguments = ["--demo-session", "--demo-consent", "--demo-state=\(state)"]
            app.launch()
            XCTAssertTrue(app.staticTexts["screen.home"].waitForExistence(timeout: 5))
            openTool("tools.exam", app: app)
            XCTAssertTrue(app.descendants(matching: .any)["exams.screen"].waitForExistence(timeout: 5))
            switch state {
            case "loading": XCTAssertTrue(app.activityIndicators.firstMatch.waitForExistence(timeout: 4))
            case "empty": XCTAssertTrue(app.staticTexts["目前没有任何考试"].waitForExistence(timeout: 4))
            default: XCTAssertTrue(app.buttons["重试"].waitForExistence(timeout: 4))
            }
            capture("state-\(state)-exams", app: app)
        }
    }

    @MainActor
    func testFreeClassroomsLoadingEmptyAndErrorStates() {
        let app = XCUIApplication()
        defer { app.terminate() }
        for state in ["loading", "empty", "error"] {
            app.terminate()
            app.launchEnvironment["AHUTONG_CI_DISABLE_LIVE_PAYMENT"] = "1"
            app.launchArguments = ["--demo-session", "--demo-consent", "--demo-state=\(state)"]
            app.launch()
            XCTAssertTrue(app.staticTexts["screen.home"].waitForExistence(timeout: 5))
            openTool("tools.free-classroom", app: app)
            app.buttons["free-classroom.search"].tap()
            XCTAssertTrue(app.descendants(matching: .any)["free-classroom.\(state)"].waitForExistence(timeout: 5))
            capture("state-\(state)-freeclassrooms", app: app)
        }
    }

    @MainActor
    func testLostFoundLoadingEmptyAndErrorStates() {
        let app = XCUIApplication()
        defer { app.terminate() }
        for state in ["loading", "empty", "error"] {
            app.terminate()
            app.launchEnvironment["AHUTONG_CI_DISABLE_LIVE_PAYMENT"] = "1"
            app.launchArguments = ["--demo-session", "--demo-consent", "--demo-state=\(state)"]
            app.launch()
            XCTAssertTrue(app.staticTexts["screen.home"].waitForExistence(timeout: 5))
            openTool("tools.lost-found", app: app)
            XCTAssertTrue(app.descendants(matching: .any)["lost-found.\(state)"].waitForExistence(timeout: 5))
            capture("state-\(state)-lostfound", app: app)
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
            let link = app.revealTool("tools.phone-book")
            XCTAssertTrue(link.waitForExistence(timeout: 4))
            link.tap()
            XCTAssertTrue(app.searchFields["搜索电话或部门"].waitForExistence(timeout: 4))
            XCTAssertTrue(app.navigationBars.firstMatch.waitForExistence(timeout: 3))
            XCTAssertTrue(app.navigationBars.buttons.firstMatch.exists)
            XCTAssertTrue(app.tabBars.firstMatch.isHittable)
        }

        openPhoneBook()
        // Use a deliberate edge drag rather than a 50 ms flick on loaded CI
        // simulators. Both attempts must still exercise the native gesture;
        // never substitute the back button for this assertion.
        let window = app.windows.firstMatch
        for y in [0.5, 0.7] where !app.buttons["tools.phone-book"].exists {
            window.coordinate(withNormalizedOffset: CGVector(dx: 0.01, dy: y)).press(
                forDuration: 0.15,
                thenDragTo: window.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: y)),
                withVelocity: .slow,
                thenHoldForDuration: 0.1
            )
            _ = app.buttons["tools.phone-book"].waitForExistence(timeout: 3)
        }
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
    func testCMBOneTimeAndDefaultChoices() {
        let app = XCUIApplication()
        launchDemo(app)
        defer { app.terminate() }
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

    }

    @MainActor
    func testCampusCardDemoPaymentConfirmation() {
        let app = XCUIApplication()
        launchDemo(app)
        defer { app.terminate() }
        setCMBPreference(false, app: app)
        launchDemo(app)
        app.buttons["campus-card.recharge"].tap()
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

    }

    @MainActor
    func testBathroomDemoPaymentConfirmation() {
        let app = XCUIApplication()
        launchDemo(app)
        defer { app.terminate() }
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

    }

    @MainActor
    func testElectricityDemoPaymentConfirmation() {
        let app = XCUIApplication()
        launchDemo(app)
        defer { app.terminate() }
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

    }

    @MainActor
    func testSettingsHasNoHiddenDebugEntry() {
        let app = XCUIApplication()
        launchDemo(app)
        defer { app.terminate() }
        tabButton("settings", app: app).tap()
        XCTAssertFalse(app.buttons["settings.debug"].exists)
        XCTAssertFalse(app.staticTexts["Debug"].exists)
        let appCard = app.descendants(matching: .any)
            .matching(identifier: "settings.app-card")
            .firstMatch
        XCTAssertTrue(appCard.waitForExistence(timeout: 4))
        appCard.tap(withNumberOfTaps: 8, numberOfTouches: 1)
        XCTAssertFalse(app.descendants(matching: .any)["operations.debug.screen"].exists)
        waitForRendering()
        capture("33-settings", app: app)
    }


    @MainActor
    func testNetworkRechargeAndCMBPreference() {
        let app = XCUIApplication()
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
        let preference = app.switches["preferences.cmb-card-recharge"]
        XCTAssertTrue(preference.waitForExistence(timeout: 4))
        let initialValue = preference.value as? String
        let changedValue = initialValue == "1" ? "0" : "1"
        preference.tapNativeSwitch()
        expectation(
            for: NSPredicate(format: "value == %@", changedValue),
            evaluatedWith: preference
        )
        waitForExpectations(timeout: 3)
        waitForRendering()
        capture("36-cmb-preference", app: app)
        preference.tapNativeSwitch()
        expectation(
            for: NSPredicate(format: "value == %@", initialValue ?? "0"),
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
    private func launchDemo(_ app: XCUIApplication) {
        app.terminate()
        app.launchEnvironment["AHUTONG_CI_DISABLE_LIVE_PAYMENT"] = "1"
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
        let preference = app.switches["preferences.cmb-card-recharge"]
        XCTAssertTrue(preference.waitForExistence(timeout: 4))
        let expectedValue = enabled ? "1" : "0"
        if preference.value as? String != expectedValue {
            preference.tapNativeSwitch()
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

        XCTAssertTrue(waitForSelection(of: toolsTab, timeout: 5))
        app.revealTool(identifier).tap()
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
        let keyboardDone = app.buttons["payment.keyboard.done"]
        if keyboardDone.exists {
            keyboardDone.tap()
            XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 3))
        } else {
            app.swipeDown()
        }
    }

    @MainActor
    private func choose(_ option: String, from identifier: String, app: XCUIApplication) {
        let menu = app.buttons[identifier]
        XCTAssertTrue(menu.waitForExistence(timeout: 3))
        expectation(
            for: NSPredicate(format: "enabled == true AND hittable == true"),
            evaluatedWith: menu
        )
        waitForExpectations(timeout: 8)
        menu.tap()
        let choice = app.buttons[option]
        XCTAssertTrue(choice.waitForExistence(timeout: 3))
        choice.tap()
        expectation(
            for: NSPredicate(format: "label CONTAINS %@", option),
            evaluatedWith: menu
        )
        // Hosted snapshots have taken 8-14 seconds; allow fresh AX polls while
        // retaining the actual selected-value assertion.
        waitForExpectations(timeout: 30)
    }

    @MainActor
    private func waitForPaymentResult(_ identifier: String, app: XCUIApplication) {
        let state = app.buttons[identifier]
        let success = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label CONTAINS %@", "支付成功"),
            object: state
        )
        // Hosted AX snapshots can take 14 seconds and temporarily contain only
        // UIApplication with no windows. Allow several fresh snapshots without
        // resubmitting a payment; a persistent failure still fails this test.
        let result = XCTWaiter.wait(for: [success], timeout: 45)
        if result != .completed {
            capture("payment-result-timeout-\(identifier)", app: app)
        }
        XCTAssertEqual(result, .completed, "Mock 支付必须显示服务端确认的支付成功状态")
    }

    private func waitForRendering() {
        let rendered = expectation(description: "界面完成渲染")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            rendered.fulfill()
        }
        wait(for: [rendered], timeout: 2)
    }
}
