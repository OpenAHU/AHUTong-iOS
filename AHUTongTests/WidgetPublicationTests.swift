import XCTest
@testable import AHUTong

@MainActor
final class WidgetPublicationTests: XCTestCase {
    func testHomePublishesCachedCoursesBeforeSlowWeekRequestFinishes() async throws {
        let fixture = try await makeFixture(knownWeek: 7)
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let model = HomeViewModel(api: fixture.api, userID: "widget-fixture", store: fixture.store,
                                  widgetStore: fixture.widget, now: { DemoDataState.referenceDate })
        let loading = Task { await model.load(demo: false) }
        await fixture.api.waitForWeekRequest()
        let cached = await fixture.widget.load()
        XCTAssertEqual(cached.status, .ready)
        XCTAssertEqual(cached.currentWeek, 7)
        XCTAssertFalse(cached.courses.isEmpty)
        await fixture.api.releaseWeekRequest()
        await loading.value
        let refreshed = await fixture.widget.load()
        XCTAssertEqual(refreshed.currentWeek, 8)
    }

    func testSchedulePublishesCachedCoursesBeforeSlowWeekRequestFinishes() async throws {
        let fixture = try await makeFixture(knownWeek: 7)
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let model = ScheduleViewModel(api: fixture.api, userID: "widget-fixture",
                                      experienceStore: ExperienceScheduleStore(store: fixture.store), store: fixture.store,
                                      widgetStore: fixture.widget, now: { DemoDataState.referenceDate })
        let loading = Task { await model.load() }
        await fixture.api.waitForWeekRequest()
        let cached = await fixture.widget.load()
        XCTAssertEqual(cached.status, .ready)
        XCTAssertEqual(cached.currentWeek, 7)
        XCTAssertFalse(cached.courses.isEmpty)
        await fixture.api.releaseWeekRequest()
        await loading.value
        let refreshed = await fixture.widget.load()
        XCTAssertEqual(refreshed.currentWeek, 8)
    }

    func testUnknownWeekDoesNotPublishInventedWeekBeforeNetworkCompletes() async throws {
        let fixture = try await makeFixture(knownWeek: nil)
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let model = HomeViewModel(api: fixture.api, userID: "widget-fixture", store: fixture.store,
                                  widgetStore: fixture.widget, now: { DemoDataState.referenceDate })
        let loading = Task { await model.load(demo: false) }
        await fixture.api.waitForWeekRequest()
        let before = await fixture.widget.load()
        XCTAssertEqual(before.status, .signedOut)
        await fixture.api.releaseWeekRequest()
        await loading.value
        let after = await fixture.widget.load()
        XCTAssertEqual(after.status, .ready)
        XCTAssertEqual(after.currentWeek, 8)
    }

    func testSyncDiagnosticsContainCountsWithoutCourseDetails() {
        let course = Course(weekday: 1, startWeek: 1, endWeek: 20, location: "PRIVATE-LOCATION",
            name: "PRIVATE-TITLE", teacher: "PRIVATE-TEACHER", duration: 2, startPeriod: 1,
            courseID: "PRIVATE-ID", weekIndexes: [7])
        let snapshot = ScheduleWidgetSnapshot.make(courses: [course], currentWeek: 7)
        XCTAssertEqual(snapshot.synchronizationSummary, "已同步第 7 周，共 1 门课程")
        XCTAssertTrue(snapshot.diagnosticSummary.contains("Snapshot active courses: 1"))
        XCTAssertFalse(snapshot.diagnosticSummary.contains("PRIVATE"))
    }

    private func makeFixture(knownWeek: Int?) async throws -> (
        root: URL, api: SlowWidgetWeekAPI, store: InMemoryDataStore, widget: ScheduleWidgetSnapshotStore
    ) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = InMemoryDataStore()
        let cache = UserScopedStore(store: store, userID: "widget-fixture")
        let semester = Semester.current(date: DemoDataState.referenceDate, calendar: ScheduleCalendar.campus)
        try await JSONStore<[Course]>(store: cache, key: "schedule.\(semester.rawValue)")
            .save(ScheduleViewModel.demoCourses)
        if let knownWeek {
            try await JSONStore<ScheduleWeekSnapshot>(store: cache, key: "schedule.week.\(semester.rawValue)")
                .save(ScheduleWeekSnapshot(week: knownWeek, referenceDate: DemoDataState.referenceDate))
        }
        return (root, SlowWidgetWeekAPI(), store,
                ScheduleWidgetSnapshotStore(fileURL: root.appendingPathComponent("widget.json")))
    }
}

private actor SlowWidgetWeekAPI: CampusCoreAPI {
    private var requested = false
    private var waiter: CheckedContinuation<Void, Never>?
    private var gate: CheckedContinuation<Int, Never>?
    func currentWeek() async -> Int {
        requested = true
        waiter?.resume()
        waiter = nil
        return await withCheckedContinuation { gate = $0 }
    }
    func waitForWeekRequest() async {
        if !requested { await withCheckedContinuation { waiter = $0 } }
    }
    func releaseWeekRequest() { gate?.resume(returning: 8); gate = nil }
    func schedule() -> [Course] { [] }
    func initialize(cookiesJSON: String) {}
    func dumpCookies() -> String { "[]" }
    func cookiesFlat() -> String { "[]" }
    func exams() -> [CampusExam] { [] }
    func grades() -> CampusGradeReport { CampusGradeReport(grades: [], gradePointAverage: nil, rank: nil, studentProfiles: []) }
    func cardBalance() -> Double { 0 }
    func cardQRCode() -> String { "FIXTURE" }
}
