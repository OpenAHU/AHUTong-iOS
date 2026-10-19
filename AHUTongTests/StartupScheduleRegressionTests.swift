import XCTest
@testable import AHUTong

final class StartupScheduleRegressionTests: XCTestCase {
    @MainActor
    func testStartupShowsCachedIdentityWhileNetworkValidationIsSuspended() async throws {
        let secure = InMemorySecureStore()
        let store = CampusSessionStore(secureStore: secure)
        let user = User(name: "离线同学", studentID: "startup-fixture")
        try await store.save(CampusSessionSnapshot(user: user, cookiesJSON: "[]"))
        let api = DeferredScheduleAPI(suspendsWeek: true)
        let suite = "startup-identity-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = AppModel(campusAPI: api, sessionStore: store,
                             credentialStore: CredentialStore(secureStore: secure), defaults: defaults)
        let restore = Task { await model.restore() }

        await api.waitForWeekRequest()
        XCTAssertEqual(model.sessionState, .authenticated(user))
        await api.resumeWeekRequest()
        await restore.value
    }

    @MainActor
    func testSigningOutWhileStartupValidationIsSuspendedDoesNotRestoreOldUser() async throws {
        let secure = InMemorySecureStore()
        let store = CampusSessionStore(secureStore: secure)
        let user = User(name: "离线同学", studentID: "startup-fixture")
        try await store.save(CampusSessionSnapshot(user: user, cookiesJSON: "[]"))
        let api = DeferredScheduleAPI(suspendsWeek: true)
        let suite = "startup-signout-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = AppModel(campusAPI: api, sessionStore: store,
                             credentialStore: CredentialStore(secureStore: secure), defaults: defaults)
        let restore = Task { await model.restore() }
        await api.waitForWeekRequest()

        await model.signOut()
        await api.resumeWeekRequest()
        await restore.value

        XCTAssertEqual(model.sessionState, .signedOut)
        let snapshot = try await store.load()
        XCTAssertNil(snapshot)
    }

    @MainActor
    func testCachedCoursesAndOctoberDatesAreVisibleBeforeSlowWeekRequestFinishes() async throws {
        let store = InMemoryDataStore()
        let now = try date(2026, 10, 14)
        try await seed(store, week: 7, at: now)
        let api = DeferredScheduleAPI(suspendsWeek: true)
        let model = scheduleModel(api: api, store: store, now: now)
        let load = Task { await model.load() }
        await api.waitForWeekRequest()

        XCTAssertEqual(model.state.value, [Self.course])
        XCTAssertEqual(model.currentWeek, 7)
        XCTAssertEqual(model.date(weekday: 3, week: 7), now)
        XCTAssertEqual(model.date(weekday: 1, week: 7), try date(2026, 10, 12))
        XCTAssertEqual(model.date(weekday: 1, week: 8), try date(2026, 10, 19))
        await api.resumeWeekRequest()
        await load.value
    }

    @MainActor
    func testOfflineWeekAdvancesFromCachedAnchorInsteadOfResettingToOne() async throws {
        let store = InMemoryDataStore()
        let now = try date(2026, 10, 14)
        try await seed(store, week: 9, at: date(2026, 10, 7))
        let api = DeferredScheduleAPI(week: .failure(.invalidResponse))
        let model = scheduleModel(api: api, store: store, now: now)

        await model.load()

        XCTAssertEqual(model.currentWeek, 10)
        XCTAssertEqual(model.date(weekday: 3, week: 10), now)
        XCTAssertEqual(model.state.value, [Self.course])
        let home = HomeViewModel(api: api, userID: "schedule-fixture", store: store, now: { now })
        await home.load(demo: false)
        XCTAssertEqual(home.currentWeek, 10)
        XCTAssertEqual(home.todayCourses, [Self.course])
        let shortcut = try await ScheduleShortcutStore(userID: "schedule-fixture", dataStore: store).load()
        XCTAssertEqual(shortcut?.courses, [Self.course])
        XCTAssertEqual(shortcut?.semesterStart, try date(2026, 8, 10))
    }

    @MainActor
    func testMissingTeachingWeekDoesNotInventDatesOrTodayCourses() async throws {
        let store = InMemoryDataStore()
        let now = try date(2026, 10, 14)
        try await seed(store, week: 7, at: now)
        let scoped = UserScopedStore(store: store, userID: "schedule-fixture")
        let semester = Semester.current(date: now)
        try await scoped.removeValue(forKey: "schedule.week.\(semester.rawValue)")
        let api = DeferredScheduleAPI(week: .failure(.invalidResponse))
        let model = scheduleModel(api: api, store: store, now: now)

        await model.load()

        XCTAssertEqual(model.state.value, [Self.course])
        XCTAssertFalse(model.currentWeekIsKnown)
        XCTAssertNil(model.date(weekday: 3, week: 1))
        model.advanceDate()
        XCTAssertFalse(model.currentWeekIsKnown)
        let home = HomeViewModel(api: api, userID: "schedule-fixture", store: store, now: { now })
        await home.load(demo: false)
        XCTAssertTrue(home.todayCourses.isEmpty)
        let shortcut = try await ScheduleShortcutStore(userID: "schedule-fixture", dataStore: store).load()
        XCTAssertNil(shortcut, "A failed week lookup must not publish a fabricated shortcut anchor")
    }

    @MainActor
    func testLateCurrentSemesterRequestCannotOverwriteNextSemesterPreview() async throws {
        let store = InMemoryDataStore()
        let now = try date(2026, 10, 14)
        try await seed(store, week: 7, at: now)
        let semester = Semester.current(date: now)
        let scoped = UserScopedStore(store: store, userID: "schedule-fixture")
        try await JSONStore<[Course]>(store: scoped, key: "schedule.\(semester.next.rawValue)").save([])
        let api = DeferredScheduleAPI(suspendsWeek: true)
        let model = scheduleModel(api: api, store: store, now: now)
        let load = Task { await model.load() }
        await api.waitForWeekRequest()

        await model.load(previewNext: true)
        await api.resumeWeekRequest()
        await load.value

        XCTAssertEqual(model.state, .empty)
        XCTAssertEqual(model.currentWeek, 1)
        XCTAssertNil(model.date(weekday: 1, week: 1))
    }

    func testTeachingWeekUsesExplicitWeekIndexAndIgnoresSemesterID() throws {
        let data = Data(#"{"id":3217,"semester":{"id":2026},"weekIndex":7}"#.utf8)
        XCTAssertEqual(try TeachingWeekParser.parse(data), 7)
        XCTAssertEqual(try TeachingWeekParser.parse(Data(#"{"data":{"currentWeek":" 8 "},"code":200}"#.utf8)), 8)
        XCTAssertEqual(try TeachingWeekParser.parse(Data("9".utf8)), 9)
        XCTAssertEqual(try TeachingWeekParser.parse(Data(#""10""#.utf8)), 10)
    }

    func testTeachingWeekRejectsUnrelatedNumbersBooleanAndMalformedWeek() {
        for fixture in [#"{"id":7,"code":200}"#, #"{"weekIndex":true}"#,
                        #"{"weekIndex":7.5}"#, #"{"weekIndex":0}"#,
                        #"{"weekIndex":2026}"#, #"{"weekIndex":null}"#] {
            XCTAssertThrowsError(try TeachingWeekParser.parse(Data(fixture.utf8)), fixture)
        }
    }

    func testSundayDoesNotAdvanceExperienceOrWidgetEvenWithSundayFirstLocale() throws {
        var calendar = ScheduleCalendar.campus
        calendar.firstWeekday = 1
        let friday = try date(2026, 10, 9)
        let sunday = try date(2026, 10, 11)
        let monday = try date(2026, 10, 12)
        var experience = ExperienceScheduleSnapshot()
        experience.currentWeek = 6
        experience.updatedAt = friday
        let widget = ScheduleWidgetSnapshot.make(courses: [Self.course], currentWeek: 6, updatedAt: friday)

        XCTAssertEqual(experience.resolvedCurrentWeek(at: sunday, calendar: calendar), 6)
        XCTAssertEqual(widget.resolved(at: sunday, calendar: calendar).currentWeek, 6)
        XCTAssertEqual(experience.resolvedCurrentWeek(at: monday, calendar: calendar), 7)
        XCTAssertEqual(widget.resolved(at: monday, calendar: calendar).currentWeek, 7)
    }

    func testWeekDateCrossesYearBoundaryWithoutLosingWeekday() throws {
        let reference = try date(2026, 12, 31)
        XCTAssertEqual(ScheduleCalendar.date(week: 17, weekday: 7, currentWeek: 17, referenceDate: reference),
                       try date(2027, 1, 3))
        XCTAssertEqual(ScheduleCalendar.date(week: 18, weekday: 1, currentWeek: 17, referenceDate: reference),
                       try date(2027, 1, 4))
    }

    @MainActor
    func testCachedWeekIsIsolatedByStudentAndSemester() async throws {
        let store = InMemoryDataStore()
        let now = try date(2026, 10, 14)
        try await seed(store, week: 7, at: now)
        let api = DeferredScheduleAPI()
        let semester = Semester.current(date: now)
        let otherUser = ScheduleWeekRepository(api: api, cache: UserScopedStore(store: store, userID: "other"),
                                               semester: semester, now: { now })
        let otherTerm = ScheduleWeekRepository(api: api, cache: UserScopedStore(store: store, userID: "schedule-fixture"),
                                               semester: semester.next, now: { now })
        let userWeek = await otherUser.cached()
        let termWeek = await otherTerm.cached()
        XCTAssertEqual(userWeek.week, 1)
        XCTAssertEqual(termWeek.week, 1)
    }

    @MainActor
    private func scheduleModel(api: DeferredScheduleAPI, store: InMemoryDataStore, now: Date) -> ScheduleViewModel {
        ScheduleViewModel(api: api, userID: "schedule-fixture",
                          experienceStore: ExperienceScheduleStore(store: InMemoryDataStore()),
                          store: store, now: { now })
    }

    @MainActor
    private func seed(_ store: InMemoryDataStore, week: Int, at date: Date) async throws {
        let semester = Semester.current(date: date)
        let scoped = UserScopedStore(store: store, userID: "schedule-fixture")
        try await JSONStore<[Course]>(store: scoped, key: "schedule.\(semester.rawValue)").save([Self.course])
        try await JSONStore<ScheduleWeekSnapshot>(store: scoped, key: "schedule.week.\(semester.rawValue)")
            .save(ScheduleWeekSnapshot(week: week, referenceDate: date))
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) throws -> Date {
        try XCTUnwrap(ScheduleCalendar.campus.date(from: DateComponents(year: year, month: month, day: day)))
    }

    private static let course = Course(weekday: 3, startWeek: 1, endWeek: 16, location: "A301",
        name: "离线课表", teacher: "老师", duration: 2, startPeriod: 1, courseID: "fixture", weekIndexes: Array(1...16))
}

private actor DeferredScheduleAPI: CampusCoreAPI {
    private let result: Result<Int, CampusCoreError>
    private var suspendsWeek: Bool
    private var requested = false
    private var startWaiters: [CheckedContinuation<Void, Never>] = []
    private var weekWaiter: CheckedContinuation<Void, Never>?

    init(week: Result<Int, CampusCoreError> = .success(7), suspendsWeek: Bool = false) {
        result = week
        self.suspendsWeek = suspendsWeek
    }

    func currentWeek() async throws -> Int {
        requested = true
        startWaiters.forEach { $0.resume() }
        startWaiters = []
        if suspendsWeek { await withCheckedContinuation { weekWaiter = $0 } }
        return try result.get()
    }
    func waitForWeekRequest() async {
        if !requested { await withCheckedContinuation { startWaiters.append($0) } }
    }
    func resumeWeekRequest() {
        suspendsWeek = false
        weekWaiter?.resume()
        weekWaiter = nil
    }
    func initialize(cookiesJSON: String) {}
    func dumpCookies() -> String { "[]" }
    func cookiesFlat() -> String { "[]" }
    func schedule() throws -> [Course] { throw CampusCoreError.invalidResponse }
    func exams() -> [CampusExam] { [] }
    func grades() -> CampusGradeReport { CampusGradeReport(grades: [], gradePointAverage: nil, rank: nil, studentProfiles: []) }
    func cardBalance() -> Double { 0 }
    func cardQRCode() -> String { "fixture" }
}
