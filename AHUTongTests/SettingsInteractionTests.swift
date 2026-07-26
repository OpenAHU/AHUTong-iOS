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

    @MainActor
    func testAccountPreferencesAndEvaluationPresetsDoNotCrossUsers() throws {
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

        let suite = "settings-isolation-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let firstStore = EvaluationPresetStore(defaults: defaults, userID: "student-a")
        let secondStore = EvaluationPresetStore(defaults: defaults, userID: "student-b")
        let firstPreset = EvaluationPreset(
            optionIndexes: ["question": 2],
            textAnswers: ["comment": "仅属于第一个账号"],
            isAnonymous: true
        )

        firstStore.save(firstPreset)

        XCTAssertEqual(firstStore.load(), firstPreset)
        XCTAssertEqual(secondStore.load(), EvaluationPreset())
    }
}
