import XCTest
import Vision

final class CourseLiveActivityUITests: XCTestCase {
    @MainActor
    func testCourseHoursAwayDoesNotCreateIsland() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--reset-onboarding", "--demo-consent", "--demo-session", "--demo-live-activity", "--demo-live-activity-too-early"]
        app.launch()
        defer { app.terminate() }
        // Wait for the completed fixture state, not the initially empty overlay.
        // A cold CI simulator can spend the entire short predicate timeout
        // resolving one AX snapshot. A labelled query also refreshes the match.
        let status = app.staticTexts.matching(identifier: "live-activity.fixture.status")
            .matching(NSPredicate(format: "label == %@", "未创建")).firstMatch
        XCTAssertTrue(status.waitForExistence(timeout: 30))
    }

    @MainActor
    func testExpandedIslandInsetsAndTenMinuteNativeCountdown() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--reset-onboarding", "--demo-consent", "--demo-session", "--demo-live-activity", "--demo-live-activity-ten-minutes"]
        app.launch()
        defer {
            app.terminate()
            app.launchArguments.append("--demo-live-activity-clear")
            app.launch()
            _ = app.staticTexts["live-activity.fixture.status"].waitForExistence(timeout: 5)
            app.terminate()
        }
        let status = app.staticTexts["live-activity.fixture.status"]
        XCTAssertTrue(status.waitForExistence(timeout: 15))
        XCTAssertEqual(status.label, "已创建")
        let screen = app.frame
        XCUIDevice.shared.press(.home)
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        expandIsland(springboard, screen: screen)
        let title = springboard.staticTexts["数据库原理与应用"]
        let location = springboard.staticTexts["博学南楼 B101"]
        let timer = springboard.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS %@", "距上课")).firstMatch
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        XCTAssertTrue(location.exists)
        XCTAssertTrue(timer.exists)
        XCTAssertGreaterThan(location.frame.minX, screen.minX + 24)
        capture("island-rounded-corner-safe-layout", springboard: springboard)
        // ActivityKit may expose the entire region as the combined AX frame.
        // Verify the actual timer glyphs stay inside the rounded island.
        let reading = try renderedTimerReadings(springboard)[0]
        XCTAssertLessThan(reading.0.maxX, 0.94)
        XCTAssertGreaterThan(reading.0.minX, 0.6)
        let initial = reading.1
        XCTAssertGreaterThan(initial, 540)
        XCTAssertLessThanOrEqual(initial, 600)
        Thread.sleep(forTimeInterval: 3)
        XCTAssertLessThan(try renderedCountdowns(springboard)[0], initial)
        capture("island-native-countdown-running", springboard: springboard)
    }

    @MainActor
    func testLiveActivityPreferenceDoesNotRequireCourseReminder() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--reset-onboarding", "--demo-consent", "--demo-session"]
        app.launch()
        defer { app.terminate() }
        let settingsTab = app.tabBars.buttons["设置"]
        XCTAssertTrue(settingsTab.waitForExistence(timeout: 10))
        settingsTab.tap()
        app.buttons["settings.preferences"].tap()
        let reminder = app.switches["preferences.course-reminders"]
        XCTAssertTrue(reminder.waitForExistence(timeout: 5))
        if reminder.value as? String == "1" {
            reminder.tapNativeSwitch()
            waitForValue("0", element: reminder)
        }
        app.swipeUp()
        let liveActivity = app.switches["preferences.island-reminder"]
        if !liveActivity.isHittable { app.swipeUp() }
        XCTAssertTrue(liveActivity.waitForExistence(timeout: 3))
        XCTAssertTrue(liveActivity.label.contains("课程倒计时岛卡"))
        let beforeToggle = XCTAttachment(screenshot: app.screenshot())
        beforeToggle.name = "live-activity-preference-before-toggle"
        beforeToggle.lifetime = .keepAlways
        add(beforeToggle)
        if liveActivity.value as? String == "1" {
            liveActivity.tapNativeSwitch()
            waitForValue("0", element: liveActivity)
        }
        liveActivity.tapNativeSwitch()
        waitForValue("1", element: liveActivity)
        XCTAssertEqual(liveActivity.value as? String, "1")
        XCTAssertEqual(reminder.value as? String, "0")
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "live-activity-independent-preference"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor
    func testPreclassActivityDisappearsByClassStartInBackground() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--reset-onboarding", "--demo-consent", "--demo-session", "--demo-live-activity"]
        app.launch()
        defer {
            app.terminate()
            app.launchArguments.append("--demo-live-activity-clear")
            app.launch()
            _ = app.staticTexts["live-activity.fixture.status"].waitForExistence(timeout: 5)
            app.terminate()
        }
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 15))
        let status = app.staticTexts["live-activity.fixture.status"]
        XCTAssertTrue(status.waitForExistence(timeout: 8))
        XCTAssertEqual(status.label, "已创建")
        let screenFrame = app.frame
        XCUIDevice.shared.press(.home)
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        capture("live-activity-collapsed", springboard: springboard)
        expandIsland(springboard, screen: screenFrame)
        let startCountdown = springboard.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS %@", "距上课")).firstMatch
        XCTAssertTrue(startCountdown.waitForExistence(timeout: 8))
        capture("live-activity-before-start", springboard: springboard)
        let capturedAt = Date()
        let timers = try renderedCountdowns(springboard)
        XCTAssertGreaterThan(timers[0], 0)
        let deadline = capturedAt.addingTimeInterval(TimeInterval(timers[0]) + 8)
        _ = startCountdown.waitForNonExistence(timeout: max(5, deadline.timeIntervalSinceNow))
        capture("live-activity-dismissed-in-background", springboard: springboard)
        // SpringBoard can retain an old AX subtree (including a frozen 0:00)
        // after removing the remote view. Check fresh rendered pixels as well;
        // an actually visible zero countdown must still fail this assertion.
        XCTAssertTrue(try renderedTimerReadings(springboard, requiresCountdown: false).isEmpty,
                      "The course countdown must no longer be visible by class start")
        XCTAssertFalse(springboard.staticTexts["距下课"].exists)
    }

    @MainActor
    func testPreclassActivityEndsAtStartWhileAppRemainsForeground() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--reset-onboarding", "--demo-consent", "--demo-session", "--demo-live-activity"]
        app.launch()
        defer { app.terminate() }
        let status = app.staticTexts["live-activity.fixture.status"]
        XCTAssertTrue(status.waitForExistence(timeout: 15))
        XCTAssertEqual(status.label, "已创建")
        expectation(for: NSPredicate(format: "label == %@", "已结束"), evaluatedWith: status)
        waitForExpectations(timeout: 110)
        capture("live-activity-ended-system-state", springboard: app)
        XCUIDevice.shared.press(.home)
        capture("live-activity-absent-after-class-start", springboard: XCUIApplication(bundleIdentifier: "com.apple.springboard"))
    }

    @MainActor
    private func expandIsland(_ springboard: XCUIApplication, screen: CGRect) {
        let title = springboard.staticTexts["数据库原理与应用"]
        let island = springboard.descendants(matching: .any).matching(identifier: "regular.view").firstMatch
        XCTAssertTrue(island.waitForExistence(timeout: 8))
        island.press(forDuration: 1.5)
        if title.waitForExistence(timeout: 5) { return }
        // SpringBoard can report a collapsed region before its remote view is
        // ready. Retry at a logical screen point only after checking expansion;
        // SpringBoard's own frame can include oversized physical-pixel windows.
        for _ in 0..<2 {
            springboard.coordinate(withNormalizedOffset: .zero)
                .withOffset(CGVector(dx: screen.midX, dy: screen.height * 0.037))
                .press(forDuration: 1.5)
            if title.waitForExistence(timeout: 5) { return }
        }
        XCTFail("Course Live Activity did not expand after its remote view became available")
    }

    @MainActor
    private func renderedCountdowns(_ springboard: XCUIApplication) throws -> [Int] {
        try renderedTimerReadings(springboard).map { $0.1 }
    }

    @MainActor
    private func renderedTimerReadings(_ springboard: XCUIApplication, requiresCountdown: Bool = true) throws -> [(CGRect, Int)] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["en-US"]
        request.usesLanguageCorrection = false
        request.regionOfInterest = CGRect(x: 0, y: 0.7, width: 1, height: 0.3)
        let image = try XCTUnwrap(springboard.screenshot().image.cgImage)
        try VNImageRequestHandler(cgImage: image).perform([request])
        let matches = (request.results ?? []).compactMap { observation -> (CGRect, String)? in
            guard let text = observation.topCandidates(1).first?.string,
                  observation.boundingBox.midX > 0.5,
                  text.range(of: #"^\d{1,2}:\d{2}(:\d{2})?$"#, options: .regularExpression) != nil else { return nil }
            return (observation.boundingBox, text)
        }
        // Keep only the right-side island timer, excluding the left status clock.
        // The expanded countdown is below a compact countdown if both appear.
        let timers = matches.sorted { $0.0.minY < $1.0.minY }.prefix(1).sorted { $0.0.midX < $1.0.midX }
        if requiresCountdown {
            XCTAssertEqual(timers.count, 1, "Expanded island must render the preclass countdown")
            guard timers.count == 1 else { throw CountdownRecognitionError.missingTimers }
        }
        return timers.map { value in
            (value.0, value.1.split(separator: ":").reduce(0) { $0 * 60 + (Int($1) ?? 0) })
        }
    }

    private enum CountdownRecognitionError: Error { case missingTimers }

    @MainActor
    private func waitForValue(_ value: String, element: XCUIElement) {
        let predicate = NSPredicate(format: "value == %@", value)
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 4), .completed)
    }

    @MainActor
    private func capture(_ name: String, springboard: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: springboard.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
