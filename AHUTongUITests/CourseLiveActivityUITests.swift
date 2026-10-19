import XCTest
import Vision

final class CourseLiveActivityUITests: XCTestCase {
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
        let reminder = app.buttons["preferences.course-reminders"]
        XCTAssertTrue(reminder.waitForExistence(timeout: 5))
        if reminder.value as? String == "开启" {
            reminder.tap()
            waitForValue("关闭", element: reminder)
        }
        app.swipeUp()
        let liveActivity = app.buttons["preferences.island-reminder"]
        if !liveActivity.isHittable { app.swipeUp() }
        XCTAssertTrue(liveActivity.waitForExistence(timeout: 3))
        XCTAssertTrue(liveActivity.label.contains("课程倒计时岛卡"))
        let beforeToggle = XCTAttachment(screenshot: app.screenshot())
        beforeToggle.name = "live-activity-preference-before-toggle"
        beforeToggle.lifetime = .keepAlways
        add(beforeToggle)
        if liveActivity.value as? String == "开启" {
            liveActivity.tap()
            waitForValue("关闭", element: liveActivity)
        }
        liveActivity.tap()
        waitForValue("开启", element: liveActivity)
        XCTAssertEqual(liveActivity.value as? String, "开启")
        XCTAssertEqual(reminder.value as? String, "关闭")
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "live-activity-independent-preference"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor
    func testCourseCountdownContinuesInBackgroundAcrossClassStart() throws {
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
        XCUIDevice.shared.press(.home)
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        // Expand the island on the dedicated iPhone 17 Pro QA device.
        springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.06)).press(forDuration: 1.5)
        let endCountdown = springboard.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS %@", "距下课")).firstMatch
        XCTAssertTrue(endCountdown.waitForExistence(timeout: 8))
        capture("live-activity-before-start", springboard: springboard)
        // Widget accessibility labels are archived snapshots. Read the actual
        // rendered timer pixels rather than expecting those labels to tick.
        let initialTimers = try renderedCountdowns(springboard)
        Thread.sleep(forTimeInterval: 3)
        let backgroundCaptureTime = Date()
        let backgroundTimers = try renderedCountdowns(springboard)
        XCTAssertLessThan(backgroundTimers[0], initialTimers[0], "上课倒计时应在后台继续变化")
        XCTAssertLessThan(backgroundTimers[1], initialTimers[1], "下课倒计时应在后台继续变化")
        capture("live-activity-counting-in-background", springboard: springboard)
        // OCR can itself take tens of seconds on a hosted runner. Wait only
        // until the deadline observed in the screenshot, not a fixed delay
        // after recognition. Keep the fixture alive through slow captures.
        let classStart = backgroundCaptureTime.addingTimeInterval(TimeInterval(backgroundTimers[0]))
        Thread.sleep(forTimeInterval: max(0, classStart.timeIntervalSinceNow + 3))
        let startCountdown = springboard.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS %@", "距上课")).firstMatch
        XCTAssertTrue(startCountdown.exists)
        XCTAssertTrue(endCountdown.exists)
        let afterStartTimers = try renderedCountdowns(springboard)
        XCTAssertEqual(afterStartTimers[0], 0, "越过上课时间后，上课倒计时必须停在零")
        capture("live-activity-after-start", springboard: springboard)
        Thread.sleep(forTimeInterval: 3)
        let laterTimers = try renderedCountdowns(springboard)
        XCTAssertEqual(laterTimers[0], 0, "上课倒计时不能开始正向计时")
        XCTAssertLessThan(laterTimers[1], afterStartTimers[1], "上课后，下课倒计时必须继续变化")
        capture("live-activity-after-start-still-counting", springboard: springboard)
    }

    @MainActor
    private func renderedCountdowns(_ springboard: XCUIApplication) throws -> [Int] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["en-US"]
        request.usesLanguageCorrection = false
        request.regionOfInterest = CGRect(x: 0, y: 0.7, width: 1, height: 0.3)
        let image = try XCTUnwrap(springboard.screenshot().image.cgImage)
        try VNImageRequestHandler(cgImage: image).perform([request])
        let matches = (request.results ?? []).compactMap { observation -> (CGRect, String)? in
            guard let text = observation.topCandidates(1).first?.string,
                  text.range(of: #"^\d{1,2}:\d{2}(:\d{2})?$"#, options: .regularExpression) != nil else { return nil }
            return (observation.boundingBox, text)
        }
        // The two countdowns occupy the bottom numeric row of the expanded island.
        let timers = matches.sorted { $0.0.minY < $1.0.minY }.prefix(2).sorted { $0.0.midX < $1.0.midX }
        XCTAssertEqual(timers.count, 2, "Expanded island must render both countdowns")
        guard timers.count == 2 else { throw CountdownRecognitionError.missingTimers }
        return timers.map { value in
            value.1.split(separator: ":").reduce(0) { $0 * 60 + (Int($1) ?? 0) }
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
