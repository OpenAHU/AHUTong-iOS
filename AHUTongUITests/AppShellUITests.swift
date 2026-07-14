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
            case "settings": XCTAssertTrue(app.buttons["settings.preferences"].waitForExistence(timeout: 3))
            default: XCTAssertTrue(app.staticTexts["screen.home"].waitForExistence(timeout: 3))
            }
            waitForRendering()
            capture(screenshotName, app: app)
        }

        app.buttons["tab.schedule"].tap()
        let demoCourse = app.buttons["schedule.course.demo-1"]
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
        app.buttons["settings.preferences"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["preferences.screen"].waitForExistence(timeout: 4))
        waitForRendering()
        capture("16-preferences", app: app)
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
            XCTAssertTrue(app.buttons["回到当前周"].waitForExistence(timeout: 3))
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
        }
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

    private func waitForRendering() {
        let rendered = expectation(description: "界面完成渲染")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            rendered.fulfill()
        }
        wait(for: [rendered], timeout: 1)
    }
}
