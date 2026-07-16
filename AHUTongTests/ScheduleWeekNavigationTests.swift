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

    func testOnlySelectedPageKeepsStableCourseIdentifier() {
        XCTAssertEqual(
            ScheduleWeekNavigation.courseIdentifier(courseID: "demo-3", week: 2, selectedWeek: 2),
            "schedule.course.demo-3"
        )
        XCTAssertEqual(
            ScheduleWeekNavigation.courseIdentifier(courseID: "demo-3", week: 3, selectedWeek: 2),
            "schedule.course.demo-3.week.3"
        )
    }
}
