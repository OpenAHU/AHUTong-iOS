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

    func testRepeatedForegroundEntriesAreThrottled() async {
        let api = HomeRefreshFixture()
        let model = HomeViewModel(api: api, userID: "foreground-fixture", store: InMemoryDataStore())
        await model.refreshOnEntry(demo: false)
        await model.refreshOnEntry(demo: false)
        let calls = await api.scheduleRequests
        XCTAssertEqual(calls, 1)
    }
}

private actor HomeRefreshFixture: CampusCoreAPI {
    private(set) var scheduleRequests = 0
    private var fails = false
    func fail() { fails = true }
    func schedule() throws -> [Course] { scheduleRequests += 1; if fails { throw CampusCoreError.invalidResponse }; return [] }
    func currentWeek() -> Int { 7 }
    func initialize(cookiesJSON: String) {}
    func dumpCookies() -> String { "[]" }
    func cookiesFlat() -> String { "[]" }
    func exams() -> [CampusExam] { [] }
    func grades() -> CampusGradeReport { CampusGradeReport(grades: [], gradePointAverage: nil, rank: nil, studentProfiles: []) }
    func cardBalance() -> Double { 0 }
    func cardQRCode() -> String { "FIXTURE" }
}
