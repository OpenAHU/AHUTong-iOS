import XCTest
@testable import AHUTong

@MainActor
final class PreferencesNotificationTests: XCTestCase {
    func testDisablingBothFeaturesNeverRequestsSchoolData() async {
        let api = PreferenceFixtureAPI()
        let scheduler = PreferenceScheduler()
        let activities = PreferenceActivities()
        let model = PreferencesModel(
            api: api, demo: false, store: InMemoryDataStore(),
            reminder: CourseReminderCoordinator(scheduler: scheduler),
            liveActivity: CourseLiveActivityCoordinator(manager: activities)
        )
        let reminders = await model.setReminders(false)
        let live = await model.setLiveActivity(false)
        XCTAssertFalse(reminders)
        XCTAssertFalse(live)
        let requests = await api.requests
        XCTAssertEqual(requests, [], "关闭提醒必须在离线时也能立即清理")
        let replacements = await scheduler.replacements
        XCTAssertEqual(replacements, [[]])
        let reconciled = await activities.reconciled
        XCTAssertEqual(reconciled, 1)
        XCTAssertNil(model.errorMessage)
    }

    func testEnablingUsesCachedCoursesAndKnownWeekWithoutNetwork() async throws {
        let api = PreferenceFixtureAPI()
        let scheduler = PreferenceScheduler()
        let store = InMemoryDataStore()
        let scoped = UserScopedStore(store: store, userID: "preference-fixture")
        let semester = Semester.current()
        try await JSONStore<[Course]>(store: scoped, key: "schedule.\(semester.rawValue)").save(ScheduleViewModel.demoCourses)
        try await JSONStore<ScheduleWeekSnapshot>(store: scoped, key: "schedule.week.\(semester.rawValue)")
            .save(ScheduleWeekSnapshot(week: 7, referenceDate: Date()))
        let model = PreferencesModel(api: api, userID: "preference-fixture", demo: false, store: store,
                                     reminder: CourseReminderCoordinator(scheduler: scheduler))
        let result = await model.setReminders(true)
        XCTAssertTrue(result)
        let requests = await api.requests
        XCTAssertEqual(requests, [])
        let replacements = await scheduler.replacements
        XCTAssertEqual(replacements.count, 1)
        XCTAssertFalse(model.isUpdatingReminders)
    }

    func testDeniedPermissionRollsBackWithoutRequestingSchoolData() async {
        let api = PreferenceFixtureAPI()
        let scheduler = PreferenceScheduler(authorized: false)
        let model = PreferencesModel(api: api, demo: false, store: InMemoryDataStore(),
                                     reminder: CourseReminderCoordinator(scheduler: scheduler))
        let result = await model.setReminders(true)
        XCTAssertFalse(result)
        XCTAssertNotNil(model.errorMessage)
        XCTAssertFalse(model.isUpdatingReminders)
        let requests = await api.requests
        XCTAssertEqual(requests, [])
        let replacements = await scheduler.replacements
        XCTAssertTrue(replacements.isEmpty)
    }
}

private actor PreferenceScheduler: NotificationScheduling {
    let authorized: Bool
    private(set) var replacements: [[CourseReminderRequest]] = []
    init(authorized: Bool = true) { self.authorized = authorized }
    func authorization() -> ReminderAuthorization { authorized ? .authorized : .denied }
    func requestAuthorization() -> Bool { authorized }
    func replaceCourseReminders(with requests: [CourseReminderRequest]) { replacements.append(requests) }
}

private actor PreferenceActivities: CourseLiveActivityManaging {
    private(set) var reconciled = 0
    func activitiesEnabled() -> Bool { true }
    func reconcile(_ plan: CourseLiveActivityPlan?) { reconciled += 1 }
}

private actor PreferenceFixtureAPI: CampusCoreAPI {
    private(set) var requests: [String] = []
    func schedule() -> [Course] { requests.append("schedule"); return [] }
    func currentWeek() -> Int { requests.append("week"); return 7 }
    func initialize(cookiesJSON: String) {}
    func dumpCookies() -> String { "[]" }
    func cookiesFlat() -> String { "[]" }
    func exams() -> [CampusExam] { [] }
    func grades() -> CampusGradeReport { CampusGradeReport(grades: [], gradePointAverage: nil, rank: nil, studentProfiles: []) }
    func cardBalance() -> Double { 0 }
    func cardQRCode() -> String { "FIXTURE" }
}
