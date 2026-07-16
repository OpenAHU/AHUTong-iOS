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

    func testOverviewGroupsSameTimeCoursesLikeAndroid() throws {
        let groups = ScheduleOverviewLayout.groups(for: [
            course(id: "late", name: "后半学期", startWeek: 9, endWeek: 16),
            course(id: "early", name: "前半学期", startWeek: 1, endWeek: 8),
            course(id: "other", name: "另一时间", startWeek: 1, endWeek: 16, startPeriod: 3)
        ])

        XCTAssertEqual(groups.count, 2)
        let sharedSlot = try XCTUnwrap(groups.first { $0.startPeriod == 1 })
        XCTAssertEqual(sharedSlot.courses.map(\.courseID), ["early", "late"])
    }

    func testOverviewRetainsCoursesOutsideSelectedWeek() {
        let future = course(id: "future", name: "未来课程", startWeek: 4, endWeek: 12)

        XCTAssertFalse(future.occurs(inWeek: 1))
        XCTAssertEqual(ScheduleOverviewLayout.groups(for: [future]).flatMap(\.courses), [future])
    }

    private func course(
        id: String,
        name: String,
        startWeek: Int,
        endWeek: Int,
        startPeriod: Int = 1
    ) -> Course {
        Course(
            weekday: 1,
            startWeek: startWeek,
            endWeek: endWeek,
            location: "教室",
            name: name,
            teacher: "老师",
            duration: 2,
            startPeriod: startPeriod,
            courseID: id,
            weekIndexes: Array(startWeek...endWeek)
        )
    }
}
