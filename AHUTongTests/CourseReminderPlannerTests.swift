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

    func testCoordinatorRequestsPermissionAndReplacesPendingCourses() async throws {
        let scheduler = NotificationSchedulerStub(status: .notDetermined, grantsPermission: true)
        let coordinator = CourseReminderCoordinator(scheduler: scheduler)
        let now = date(year: 2026, month: 7, day: 13, hour: 7)
        let enabled = try await coordinator.setEnabled(true, courses: [course()], currentWeek: 1, now: now, calendar: calendar())
        let authorizationRequests = await scheduler.authorizationRequests()
        let replacements = await scheduler.replacements()
        XCTAssertTrue(enabled)
        XCTAssertEqual(authorizationRequests, 1)
        XCTAssertEqual(replacements.first?.count, 1)
    }

    func testCoordinatorDoesNotScheduleWhenPermissionIsDenied() async throws {
        let scheduler = NotificationSchedulerStub(status: .denied, grantsPermission: false)
        let enabled = try await CourseReminderCoordinator(scheduler: scheduler)
            .setEnabled(true, courses: [course()], currentWeek: 1, now: date(year: 2026, month: 7, day: 13, hour: 7), calendar: calendar())
        let replacements = await scheduler.replacements()
        XCTAssertFalse(enabled)
        XCTAssertTrue(replacements.isEmpty)
    }

    func testCoordinatorDisablingClearsOnlyManagedReminderSet() async throws {
        let scheduler = NotificationSchedulerStub(status: .authorized, grantsPermission: true)
        let enabled = try await CourseReminderCoordinator(scheduler: scheduler)
            .setEnabled(false, courses: [course()], currentWeek: 1)
        let replacements = await scheduler.replacements()
        XCTAssertFalse(enabled)
        XCTAssertEqual(replacements, [[]])
    }

    private func course() -> Course {
        Course(weekday: 1, startWeek: 1, endWeek: 16, location: "博学南楼101", name: "高等数学", teacher: "李老师", duration: 2, startPeriod: 1, courseID: "42", weekIndexes: Array(1...16))
    }

    private func calendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return calendar
    }

    private func date(year: Int, month: Int, day: Int, hour: Int) -> Date {
        calendar().date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }
}

private actor NotificationSchedulerStub: NotificationScheduling {
    private let status: ReminderAuthorization
    private let grantsPermission: Bool
    private var requestCount = 0
    private var values: [[CourseReminderRequest]] = []

    init(status: ReminderAuthorization, grantsPermission: Bool) {
        self.status = status
        self.grantsPermission = grantsPermission
    }

    func authorization() -> ReminderAuthorization { status }
    func requestAuthorization() -> Bool {
        requestCount += 1
        return grantsPermission
    }
    func replaceCourseReminders(with requests: [CourseReminderRequest]) { values.append(requests) }
    func authorizationRequests() -> Int { requestCount }
    func replacements() -> [[CourseReminderRequest]] { values }
}
