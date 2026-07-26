import XCTest

final class PaymentLocalParityUITests: XCTestCase {
    @MainActor
    func testElectricityPasswordErrorAndChargeHistoryInteraction() {
        let app = XCUIApplication()
        app.launchArguments = ["--demo-consent", "--demo-session"]
        app.launch()
        XCTAssertTrue(app.staticTexts["screen.home"].waitForExistence(timeout: 5))

        let paymentEntry = app.buttons["home.payment.electricity"]
        if !paymentEntry.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(paymentEntry.waitForExistence(timeout: 4))
        paymentEntry.tap()
        XCTAssertTrue(
            app.descendants(matching: .any)["payment.electricity.screen"]
                .waitForExistence(timeout: 4)
        )

        choose("磬苑校区", from: "payment.electricity.campus", app: app)
        choose("竹园", from: "payment.electricity.building", app: app)
        choose("3 层", from: "payment.electricity.floor", app: app)
        choose("305", from: "payment.electricity.room", app: app)
        enter("20", into: app.textFields["payment.electricity.amount"], app: app)
        app.buttons["payment.electricity.state"].tap()

        let password = app.secureTextFields["payment.electricity.password"]
        enter("12345", into: password, app: app)
        app.buttons["payment.electricity.confirm"].tap()
        XCTAssertTrue(
            app.staticTexts["payment.electricity.password-error"]
                .waitForExistence(timeout: 3)
        )
        XCTAssertTrue(
            app.staticTexts["payment.electricity.password-dialog"].exists
        )

        password.tap()
        password.typeText("6")
        XCTAssertFalse(app.staticTexts["payment.electricity.password-error"].exists)
        app.swipeDown()
        app.buttons["payment.electricity.confirm"].tap()
        waitForPaymentSuccess("payment.electricity.state", app: app)

        let info = app.buttons["payment.electricity.info"]
        var scrollAttempts = 0
        while !info.isHittable && scrollAttempts < 4 {
            app.swipeDown()
            scrollAttempts += 1
        }
        XCTAssertTrue(info.isHittable)
        for _ in 0..<5 {
            info.tap()
        }

        let historyMessage = app.staticTexts[
            "payment.electricity.charge-history-message"
        ]
        XCTAssertTrue(historyMessage.waitForExistence(timeout: 3))
        XCTAssertTrue(historyMessage.label.contains("累计电费充值金额为"))

        info.press(forDuration: 1)
        let resetAlert = app.alerts["确认操作"]
        XCTAssertTrue(resetAlert.waitForExistence(timeout: 3))
        XCTAssertTrue(
            resetAlert.staticTexts[
                "您确定要将累计充值金额清零吗？此操作不可撤销。"
            ].exists
        )
        resetAlert.buttons["取消"].tap()
    }

    @MainActor
    private func enter(
        _ value: String,
        into field: XCUIElement,
        app: XCUIApplication
    ) {
        XCTAssertTrue(field.waitForExistence(timeout: 3))
        field.tap()
        field.typeText(value)
        app.swipeDown()
    }

    @MainActor
    private func choose(
        _ option: String,
        from identifier: String,
        app: XCUIApplication
    ) {
        let menu = app.buttons[identifier]
        XCTAssertTrue(menu.waitForExistence(timeout: 3))
        menu.tap()
        let choice = app.buttons[option]
        XCTAssertTrue(choice.waitForExistence(timeout: 3))
        choice.tap()
    }

    @MainActor
    private func waitForPaymentSuccess(
        _ identifier: String,
        app: XCUIApplication
    ) {
        let state = app.buttons[identifier]
        expectation(
            for: NSPredicate(format: "label CONTAINS %@", "支付成功"),
            evaluatedWith: state
        )
        waitForExpectations(timeout: 4)
    }
}
