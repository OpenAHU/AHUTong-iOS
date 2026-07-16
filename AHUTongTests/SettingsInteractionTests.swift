import XCTest
@testable import AHUTong

final class SettingsInteractionTests: XCTestCase {
    func testPressedStateIsVisiblyDistinctFromRestingState() {
        let resting = SettingsPressFeedbackState(isPressed: false, reduceMotion: false)
        let pressed = SettingsPressFeedbackState(isPressed: true, reduceMotion: false)

        XCTAssertEqual(resting.scale, 1)
        XCTAssertEqual(resting.opacity, 1)
        XCTAssertEqual(resting.highlightOpacity, 0)
        XCTAssertLessThan(pressed.scale, resting.scale)
        XCTAssertLessThan(pressed.opacity, resting.opacity)
        XCTAssertGreaterThan(pressed.highlightOpacity, resting.highlightOpacity)
    }

    func testReduceMotionKeepsGeometryWhileRetainingNonMotionFeedback() {
        let pressed = SettingsPressFeedbackState(isPressed: true, reduceMotion: true)

        XCTAssertEqual(pressed.scale, 1)
        XCTAssertLessThan(pressed.opacity, 1)
        XCTAssertGreaterThan(pressed.highlightOpacity, 0)
    }
}
