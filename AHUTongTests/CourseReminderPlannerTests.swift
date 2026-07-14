import XCTest
@testable import AHUTong

final class CourseReminderPlannerTests: XCTestCase {
    func testPlansTenMinutesBeforeActiveCourseInCurrentTimeZone() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        let now = calendar.date(from: DateComponents(year: 2026, month: 7, day: 13, hour: 7))!
        let course = Course(
            weekday: 1, startWeek: 1, endWeek: 16, location: "博学南楼101",
            name: "高等数学", teacher: "李老师", duration: 2, startPeriod: 1,
            courseID: "42", weekIndexes: Array(1...16)
        )

        let requests = CourseReminderPlanner().requests(courses: [course], currentWeek: 2, now: now, calendar: calendar)

        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(calendar.component(.hour, from: requests[0].date), 7)
        XCTAssertEqual(calendar.component(.minute, from: requests[0].date), 50)
        XCTAssertEqual(requests[0].body, "高等数学 · 博学南楼101")
    }

    func testSkipsInactiveAndPastCourses() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = calendar.date(from: DateComponents(year: 2026, month: 7, day: 13, hour: 9))!
        let course = Course(
            weekday: 1, startWeek: 1, endWeek: 1, location: "A101",
            name: "课程", teacher: "教师", duration: 1, startPeriod: 1,
            courseID: "1", weekIndexes: [1]
        )
        XCTAssertTrue(CourseReminderPlanner().requests(courses: [course], currentWeek: 2, now: now, calendar: calendar).isEmpty)
        XCTAssertTrue(CourseReminderPlanner().requests(courses: [course], currentWeek: 1, now: now, calendar: calendar).isEmpty)
    }
}
