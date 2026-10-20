import XCTest

final class PhoneBookUITests: XCTestCase {
    @MainActor
    func testNativeSearchCampusConfirmationAndCancel() {
        let app = launchPhoneBook()
        defer { app.terminate() }
        let search = app.searchFields["搜索电话或部门"]
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        capture("phone-native-list", app: app)
        search.tap()
        search.typeText("财务处")
        let entry = app.buttons["phone.entry.师生综合服务大厅-财务处"]
        XCTAssertTrue(entry.waitForExistence(timeout: 5))
        entry.tap()
        let qingyuan = app.buttons["磬苑校区 0551-63861322"]
        let longhe = app.buttons["龙河校区 0551-65107303"]
        XCTAssertTrue(qingyuan.waitForExistence(timeout: 4))
        XCTAssertTrue(longhe.isHittable)
        XCTAssertLessThan(abs(longhe.frame.midY - qingyuan.frame.midY), 100)
        capture("phone-native-campus-confirmation", app: app)
        dismissConfirmation(app)
        XCTAssertTrue(qingyuan.waitForNonExistence(timeout: 3))
        XCTAssertTrue(entry.exists)
        search.tap()
        if let value = search.value as? String { search.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: value.count)) }
        search.typeText("不存在的部门")
        let emptyState = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "不存在的部门")).firstMatch
        XCTAssertTrue(emptyState.waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "phone.entry.")).count, 0)
        capture("phone-native-search-empty", app: app)
    }

    @MainActor
    func testNativeCategoryAndSingleNumberWithLargeText() {
        let app = launchPhoneBook(extraArguments: [
            "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"
        ])
        defer { app.terminate() }
        let category = app.buttons["phone.category"]
        XCTAssertTrue(category.waitForExistence(timeout: 5))
        category.tap()
        let library = app.buttons["图书馆"].firstMatch
        XCTAssertTrue(library.waitForExistence(timeout: 4))
        library.tap()
        let entry = app.buttons["phone.entry.图书馆-图书馆"]
        XCTAssertTrue(entry.waitForExistence(timeout: 4))
        capture("phone-native-large-text", app: app)
        entry.tap()
        let number = app.buttons["磬苑校区 0551-63861109"]
        XCTAssertTrue(number.waitForExistence(timeout: 4))
        XCTAssertTrue(number.isHittable)
        capture("phone-native-single-number-confirmation", app: app)
        dismissConfirmation(app)
        XCTAssertTrue(number.waitForNonExistence(timeout: 3))
    }

    @MainActor
    private func dismissConfirmation(_ app: XCUIApplication) {
        let cancel = app.buttons["取消"]
        if cancel.exists {
            cancel.tap()
        } else {
            // iOS 26 anchors confirmationDialog as a native popover. It omits
            // the cancel row and provides a system outside-tap dismissal area.
            XCTAssertTrue(app.otherElements["PopoverDismissRegion"].exists)
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.01, dy: 0.5)).tap()
        }
    }

    @MainActor
    private func launchPhoneBook(extraArguments: [String] = []) -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--reset-onboarding", "--demo-consent", "--demo-session", "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"] + extraArguments
        app.launch()
        let tools = app.tabBars.buttons["小工具"]
        XCTAssertTrue(tools.waitForExistence(timeout: 15))
        tools.tap()
        let phone = app.buttons["tools.phone-book"]
        XCTAssertTrue(phone.waitForExistence(timeout: 5))
        phone.tap()
        XCTAssertTrue(app.navigationBars["电话本"].waitForExistence(timeout: 5))
        return app
    }

    @MainActor
    private func capture(_ name: String, app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
