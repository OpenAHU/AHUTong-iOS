import XCTest
@testable import AHUTong

@MainActor
final class HomeRefreshTests: XCTestCase {
    func testManualRefreshBypassesCachedCoursesAndKeepsCacheIfNetworkFails() async throws {
        let store = InMemoryDataStore()
        let api = HomeRefreshFixture()
        let scoped = UserScopedStore(store: store, userID: "home-refresh-fixture")
        let semester = Semester.current()
        try await JSONStore<[Course]>(store: scoped, key: "schedule.\(semester.rawValue)").save(ScheduleViewModel.demoCourses)
        let model = HomeViewModel(api: api, userID: "home-refresh-fixture", store: store)
        await model.load(demo: false)
        let initialRequests = await api.scheduleRequests
        XCTAssertEqual(initialRequests, 0)
        await model.load(demo: false, refresh: true)
        XCTAssertEqual(model.courses, [])
        let refreshRequests = await api.scheduleRequests
        XCTAssertEqual(refreshRequests, 1)
        await api.fail()
        await model.load(demo: false, refresh: true)
        XCTAssertEqual(model.courses, [])
        XCTAssertNotNil(model.errorMessage)
    }

    func testAutomaticRefreshThrottlesFailedAttemptsAndRetriesAtInterval() async {
        let api = HomeRefreshFixture()
        await api.fail()
        let clock = MutableTestClock()
        let model = HomeViewModel(api: api, userID: "foreground-fixture", store: InMemoryDataStore(), now: { clock.now() })
        await model.refreshOnEntry(demo: false)
        clock.advance(seconds: 59)
        await model.refreshOnEntry(demo: false)
        let calls = await api.scheduleRequests
        XCTAssertEqual(calls, 1)
        clock.advance(seconds: 1)
        await model.refreshOnEntry(demo: false)
        let retriedCalls = await api.scheduleRequests
        XCTAssertEqual(retriedCalls, 2)
    }

    func testCountdownAdvancesWithoutAnotherNetworkRequest() async throws {
        let date = try XCTUnwrap(DateComponents(calendar: ScheduleCalendar.campus,
                                               year: 2026, month: 10, day: 27, hour: 5, minute: 52).date)
        let clock = MutableTestClock(date)
        let api = HomeRefreshFixture(courses: [course(weekday: 2)])
        let model = HomeViewModel(api: api, userID: "clock-fixture", store: InMemoryDataStore(), now: { clock.now() })
        await model.load(demo: false)
        XCTAssertEqual(model.summary.detail, "还有 2小时8分钟，在 教室")

        clock.advance(seconds: 60)
        model.advanceDate()

        XCTAssertEqual(model.summary.detail, "还有 2小时7分钟，在 教室")
        let calls = await api.scheduleRequests
        XCTAssertEqual(calls, 1)
    }

    func testLocalClockRollsTeachingWeekAndTodayCoursesOverAtMidnight() async throws {
        let date = try XCTUnwrap(DateComponents(calendar: ScheduleCalendar.campus,
                                               year: 2026, month: 10, day: 25, hour: 23, minute: 59).date)
        let clock = MutableTestClock(date)
        let monday = course(weekday: 1, week: 8)
        let model = HomeViewModel(api: HomeRefreshFixture(courses: [monday]), userID: "midnight-fixture",
                                  store: InMemoryDataStore(), now: { clock.now() })
        await model.load(demo: false)
        XCTAssertTrue(model.todayCourses.isEmpty)

        clock.advance(seconds: 120)
        model.advanceDate()

        XCTAssertEqual(model.currentWeek, 8)
        XCTAssertEqual(model.todayCourses, [monday])
    }

    private func course(weekday: Int, week: Int = 7) -> Course {
        Course(weekday: weekday, startWeek: week, endWeek: week, location: "教室", name: "软件工程",
               teacher: "老师", duration: 2, startPeriod: 1, courseID: "clock-course", weekIndexes: [week])
    }
}

private actor HomeRefreshFixture: CampusCoreAPI {
    private(set) var scheduleRequests = 0
    private var fails = false
    private let courses: [Course]
    init(courses: [Course] = []) { self.courses = courses }
    func fail() { fails = true }
    func schedule() throws -> [Course] { scheduleRequests += 1; if fails { throw CampusCoreError.invalidResponse }; return courses }
    func currentWeek() -> Int { 7 }
    func initialize(cookiesJSON: String) {}
    func dumpCookies() -> String { "[]" }
    func cookiesFlat() -> String { "[]" }
    func exams() -> [CampusExam] { [] }
    func grades() -> CampusGradeReport { CampusGradeReport(grades: [], gradePointAverage: nil, rank: nil, studentProfiles: []) }
    func cardBalance() -> Double { 0 }
    func cardQRCode() -> String { "FIXTURE" }
}
