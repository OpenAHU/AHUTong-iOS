import XCTest
@testable import AHUTong

final class ScheduleWeekNavigationTests: XCTestCase {
    func testPagerExposesTheSameTwentyWeeksAsAndroid() {
        XCTAssertEqual(Array(ScheduleWeekNavigation.validWeeks), Array(1...20))
    }

    func testWeekSelectionIsClampedToPagerBounds() {
        XCTAssertEqual(ScheduleWeekNavigation.clamped(-1), 1)
        XCTAssertEqual(ScheduleWeekNavigation.clamped(1), 1)
        XCTAssertEqual(ScheduleWeekNavigation.clamped(12), 12)
        XCTAssertEqual(ScheduleWeekNavigation.clamped(20), 20)
        XCTAssertEqual(ScheduleWeekNavigation.clamped(21), 20)
    }
}
