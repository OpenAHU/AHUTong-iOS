import XCTest

final class OperationsPaymentProbeUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testHiddenOperationsRunsDeterministicNoDebitProbe() {
        let app = XCUIApplication()
        app.launchArguments = [
            "--demo-consent",
            "--demo-session",
            "--demo-payment-probe=success"
        ]
        app.launch()

        XCTAssertTrue(
            app.staticTexts["screen.home"].waitForExistence(timeout: 6)
        )
        app.tabBars.buttons["设置"].tap()

        XCTAssertFalse(app.buttons["settings.debug"].exists)
        XCTAssertFalse(app.staticTexts["Debug"].exists)
        XCTAssertFalse(
            app.descendants(matching: .any)[
                "operations.payment-probe.entry"
            ].exists
        )

        let appCard = app.descendants(matching: .any)
            .matching(identifier: "settings.app-card")
            .firstMatch
        XCTAssertTrue(appCard.waitForExistence(timeout: 4))
        appCard.tap(withNumberOfTaps: 8, numberOfTouches: 1)

        XCTAssertTrue(
            app.descendants(matching: .any)["operations.debug.screen"]
                .waitForExistence(timeout: 5)
        )

        let probeEntry = app.buttons[
            "operations.payment-probe.entry"
        ]
        scrollUntilHittable(probeEntry, app: app)
        XCTAssertTrue(
            app.buttons["operations.cmb-acceptance.entry"].exists
        )
        probeEntry.tap()

        XCTAssertTrue(
            app.descendants(matching: .any)[
                "operations.payment-probe.screen"
            ].waitForExistence(timeout: 4)
        )
        let run = app.buttons["operations.payment-probe.run"]
        XCTAssertTrue(run.waitForExistence(timeout: 3))
        run.tap()

        let result = app.descendants(matching: .any)[
            "operations.payment-probe.result"
        ]
        XCTAssertTrue(result.waitForExistence(timeout: 4))
        let value = result.value as? String ?? ""
        XCTAssertTrue(value.contains("通过"))
        XCTAssertTrue(value.contains("HTTP 302"))
        XCTAssertTrue(value.contains("未发起扣款请求"))

        let openOfficial = app.buttons[
            "operations.payment-probe.open-official"
        ]
        scrollUntilHittable(openOfficial, app: app)
        openOfficial.tap()

        let confirmation = app.alerts["确认打开学校官方页面？"]
        XCTAssertTrue(confirmation.waitForExistence(timeout: 3))
        // System alerts do not guarantee that SwiftUI button identifiers are
        // bridged through UIAlertController. Scope the stable localized labels
        // to this exact alert so similarly named buttons elsewhere cannot match.
        let cancel = confirmation.buttons["取消"]
        let confirm = confirmation.buttons["继续打开"]
        XCTAssertTrue(cancel.waitForExistence(timeout: 2))
        XCTAssertTrue(confirm.exists)
        cancel.tap()
        XCTAssertTrue(confirmation.waitForNonExistence(timeout: 2))
        XCTAssertTrue(result.exists)
    }

    @MainActor
    private func scrollUntilHittable(
        _ element: XCUIElement,
        app: XCUIApplication,
        maximumAttempts: Int = 6
    ) {
        var attempts = 0
        while !element.isHittable && attempts < maximumAttempts {
            app.swipeUp()
            attempts += 1
        }
        XCTAssertTrue(element.isHittable)
    }
}
