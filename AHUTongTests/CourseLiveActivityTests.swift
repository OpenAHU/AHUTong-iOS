import XCTest
@testable import AHUTong

final class CourseLiveActivityTests: XCTestCase {
    private let planner = CourseLiveActivityPlanner()

    func testSelectsOngoingCourseBeforeLaterCourse() throws {
        let plan = try XCTUnwrap(planner.nextCourse(
            courses: [course(id: "later", startPeriod: 3), course(id: "ongoing")],
            currentWeek: 1, now: date(hour: 8, minute: 30), calendar: calendar
        ))
        XCTAssertTrue(plan.courseID.hasPrefix("ongoing|"))
        XCTAssertEqual(plan.startDate, date(hour: 8))
        XCTAssertEqual(plan.endDate, date(hour: 9, minute: 35))
    }

    func testEndUsesLastPeriodIncludingLongBreaks() throws {
        let plan = try XCTUnwrap(planner.nextCourse(
            courses: [course(duration: 3)], currentWeek: 1,
            now: date(hour: 7), calendar: calendar
        ))
        XCTAssertEqual(plan.endDate, date(hour: 10, minute: 35))
    }

    func testDoesNotStartForTomorrowOrInactiveWeek() {
        XCTAssertNil(planner.nextCourse(
            courses: [course(weekday: 2), course(weeks: [2])],
            currentWeek: 1, now: date(hour: 7), calendar: calendar
        ))
    }

    func testSkipsFinishedCoursesAndInvalidPeriods() {
        XCTAssertNil(planner.nextCourse(
            courses: [course(), course(startPeriod: 13, duration: 2), course(duration: Int.max)],
            currentWeek: 1, now: date(hour: 9, minute: 35), calendar: calendar
        ))
    }

    func testDoesNotStartAnActivityThatExpiresBeforeClassEnds() {
        XCTAssertNil(planner.nextCourse(
            courses: [course(startPeriod: 11)], currentWeek: 1,
            now: date(hour: 7), calendar: calendar
        ))
        XCTAssertNotNil(planner.nextCourse(
            courses: [course(startPeriod: 11)], currentWeek: 1,
            now: date(hour: 13), calendar: calendar
        ))
    }

    func testWeekdayUsesSuppliedTimeZone() {
        // Sunday 23:30 UTC is already Monday morning in Shanghai.
        let now = ISO8601DateFormatter().date(from: "2026-07-12T23:30:00Z")!
        XCTAssertNotNil(planner.nextCourse(courses: [course()], currentWeek: 1, now: now, calendar: calendar))
        var utc = calendar
        utc.timeZone = TimeZone(secondsFromGMT: 0)!
        XCTAssertNil(planner.nextCourse(courses: [course()], currentWeek: 1, now: now, calendar: utc))
    }

    func testCountdownIntervalsPreserveBothDeadlinesAcrossCoding() throws {
        let state = CourseActivityAttributes.ContentState(
            courseName: "课程", location: "A101", startDate: date(hour: 8), endDate: date(hour: 9, minute: 35)
        )
        let restored = try JSONDecoder().decode(
            CourseActivityAttributes.ContentState.self, from: JSONEncoder().encode(state)
        )
        XCTAssertEqual(restored.countdownInterval(to: restored.startDate).upperBound, date(hour: 8))
        XCTAssertEqual(restored.countdownInterval(to: restored.endDate).upperBound, date(hour: 9, minute: 35))
        XCTAssertLessThan(restored.countdownInterval(to: restored.startDate).lowerBound, date(hour: 7))
    }

    func testEnablingWithoutEligibleCourseKeepsPreferenceAndClearsOldActivity() async throws {
        let manager = LiveActivityManagerStub(authorized: true)
        let enabled = try await CourseLiveActivityCoordinator(manager: manager).setEnabled(
            true, courses: [], currentWeek: 1, now: date(hour: 7), calendar: calendar
        )
        let plans = await manager.receivedPlans()
        XCTAssertTrue(enabled)
        XCTAssertEqual(plans.count, 1)
        XCTAssertNil(plans[0])
    }

    func testDeniedAuthorizationClearsExistingActivityAndReturnsDisabled() async throws {
        let manager = LiveActivityManagerStub(authorized: false)
        let enabled = try await CourseLiveActivityCoordinator(manager: manager).setEnabled(
            true, courses: [course()], currentWeek: 1, now: date(hour: 7), calendar: calendar
        )
        let plans = await manager.receivedPlans()
        XCTAssertFalse(enabled)
        XCTAssertEqual(plans.count, 1)
        XCTAssertNil(plans[0])
    }

    func testDisablingDoesNotRequireAuthorizationOrCourseData() async throws {
        let manager = LiveActivityManagerStub(authorized: false)
        let enabled = try await CourseLiveActivityCoordinator(manager: manager).setEnabled(
            false, courses: [], currentWeek: 0
        )
        let authorizationChecks = await manager.authorizationChecks()
        let plans = await manager.receivedPlans()
        XCTAssertFalse(enabled)
        XCTAssertEqual(authorizationChecks, 0)
        XCTAssertEqual(plans.count, 1)
        XCTAssertNil(plans[0])
    }

    func testEligibleCourseIsPassedToActivityManager() async throws {
        let manager = LiveActivityManagerStub(authorized: true)
        let enabled = try await CourseLiveActivityCoordinator(manager: manager).setEnabled(
            true, courses: [course()], currentWeek: 1, now: date(hour: 7), calendar: calendar
        )
        let plans = await manager.receivedPlans()
        XCTAssertTrue(enabled)
        let plan = try XCTUnwrap(plans.first ?? nil)
        XCTAssertEqual(plan.startDate, date(hour: 8))
        XCTAssertEqual(plan.endDate, date(hour: 9, minute: 35))
    }

    func testDelayedEnableDoesNotRestoreActivityAfterDisabling() async throws {
        let manager = DelayedAuthorizationActivityManager()
        let coordinator = CourseLiveActivityCoordinator(manager: manager)
        let pending = Task {
            try await coordinator.setEnabled(true, courses: [], currentWeek: 1)
        }
        await manager.waitForAuthorizationCheck()
        _ = try await coordinator.setEnabled(false, courses: [], currentWeek: 1)
        await manager.grantAuthorization()
        let enabled = try await pending.value
        let reconciliations = await manager.reconciliationCount()
        XCTAssertFalse(enabled)
        XCTAssertEqual(reconciliations, 1, "Only the newer disable operation may reconcile activities")
    }

    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return value
    }

    private func date(hour: Int, minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 7, day: 13, hour: hour, minute: minute))!
    }

    private func course(
        id: String = "course", weekday: Int = 1, startPeriod: Int = 1, duration: Int = 2, weeks: [Int] = [1]
    ) -> Course {
        Course(
            weekday: weekday, startWeek: 1, endWeek: 16, location: "博学南楼 A101", name: "高等数学",
            teacher: "教师", duration: duration, startPeriod: startPeriod, courseID: id, weekIndexes: weeks
        )
    }
}

private actor LiveActivityManagerStub: CourseLiveActivityManaging {
    private let authorized: Bool
    private var checks = 0
    private var plans: [CourseLiveActivityPlan?] = []

    init(authorized: Bool) { self.authorized = authorized }
    func activitiesEnabled() -> Bool { checks += 1; return authorized }
    func reconcile(_ plan: CourseLiveActivityPlan?) { plans.append(plan) }
    func authorizationChecks() -> Int { checks }
    func receivedPlans() -> [CourseLiveActivityPlan?] { plans }
}

private actor DelayedAuthorizationActivityManager: CourseLiveActivityManaging {
    private var authorization: CheckedContinuation<Bool, Never>?
    private var observer: CheckedContinuation<Void, Never>?
    private var reconciliations = 0

    func activitiesEnabled() async -> Bool {
        await withCheckedContinuation { continuation in
            authorization = continuation
            observer?.resume()
            observer = nil
        }
    }

    func waitForAuthorizationCheck() async {
        if authorization != nil { return }
        await withCheckedContinuation { observer = $0 }
    }

    func grantAuthorization() {
        authorization?.resume(returning: true)
        authorization = nil
    }

    func reconcile(_ plan: CourseLiveActivityPlan?) { reconciliations += 1 }
    func reconciliationCount() -> Int { reconciliations }
}
