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

    func testAccountPreferenceKeysDoNotExposeOrCrossUsers() {
        let firstKey = AccountPreferenceKey.make(
            "payment.cmb-card-recharge-preferred",
            userID: "student-a"
        )
        let secondKey = AccountPreferenceKey.make(
            "payment.cmb-card-recharge-preferred",
            userID: "student-b"
        )
        XCTAssertNotEqual(firstKey, secondKey)
        XCTAssertFalse(firstKey.contains("student-a"))
    }

    func testRetiredEvaluationPreferencesAreRemoved() throws {
        let suite = "retired-preferences-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let scopedKey = AccountPreferenceKey.make("evaluation.preset.v1", userID: "student-a")
        defaults.set(Data("legacy".utf8), forKey: scopedKey)
        defaults.set(Data("legacy".utf8), forKey: "evaluation.preset.v1")
        defaults.set(true, forKey: "unrelated")

        RetiredPreferenceCleaner.clean(defaults: defaults)

        XCTAssertNil(defaults.data(forKey: scopedKey))
        XCTAssertNil(defaults.data(forKey: "evaluation.preset.v1"))
        XCTAssertTrue(defaults.bool(forKey: "unrelated"))
    }
}
