import XCTest
@testable import AHUTong

final class SettingsInteractionTests: XCTestCase {
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

    func testRetiredDemoSwitchAndFixedClockAreRemovedWithoutTouchingSchedule() throws {
        let suite = "retired-demo-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(true, forKey: "debug.mock.enabled")
        defaults.set("loading", forKey: "debug.mock.scenario")
        defaults.set(1_784_023_200, forKey: "debug.mock.time")
        defaults.set("{}", forKey: "debug.mock.endpoint.schedule")
        defaults.set("enabled", forKey: "debug.gray.home_edit")
        defaults.set(true, forKey: "schedule.show-all")

        RetiredPreferenceCleaner.clean(defaults: defaults)

        XCTAssertFalse(defaults.dictionaryRepresentation().keys.contains { $0.hasPrefix("debug.") })
        XCTAssertTrue(defaults.bool(forKey: "schedule.show-all"))
    }
}
