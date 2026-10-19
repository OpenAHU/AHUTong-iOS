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
        // SpringBoard sometimes exposes extra windows in physical pixels on CI.
        // Its application frame then exceeds the logical screen, so normalized
        // application coordinates can miss the island entirely. Target the
        // observed island element, with a logical-screen coordinate fallback.
        let island = springboard.descendants(matching: .any).matching(identifier: "regular.view").firstMatch
        if island.waitForExistence(timeout: 5) {
            island.press(forDuration: 1.5)
        } else {
            springboard.coordinate(withNormalizedOffset: .zero)
                .withOffset(CGVector(dx: screenFrame.midX, dy: screenFrame.height * 0.037))
                .press(forDuration: 1.5)
        }
        let startCountdown = springboard.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS %@", "距上课")).firstMatch
        XCTAssertTrue(startCountdown.waitForExistence(timeout: 8))
        capture("live-activity-before-start", springboard: springboard)
        let capturedAt = Date()
        let timers = try renderedCountdowns(springboard)
        XCTAssertGreaterThan(timers[0], 0)
        let deadline = capturedAt.addingTimeInterval(TimeInterval(timers[0]) + 8)
        XCTAssertTrue(startCountdown.waitForNonExistence(timeout: max(5, deadline.timeIntervalSinceNow)))
        XCTAssertFalse(springboard.staticTexts["距下课"].exists)
        capture("live-activity-dismissed-in-background", springboard: springboard)
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
        // The preclass countdown is below the status-bar clock in the expanded island.
        let timers = matches.sorted { $0.0.minY < $1.0.minY }.prefix(1).sorted { $0.0.midX < $1.0.midX }
        XCTAssertEqual(timers.count, 1, "Expanded island must render the preclass countdown")
        guard timers.count == 1 else { throw CountdownRecognitionError.missingTimers }
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
