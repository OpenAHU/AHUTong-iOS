import XCTest
@testable import AHUTong

final class ScheduleRepositoryTests: XCTestCase {
    @MainActor
    func testCacheFirstFetchesOnceThenUsesUserCache() async throws {
        let remote = ScheduleRemoteStub(courses: [Self.course])
        let repository = ScheduleRepository(
            remote: remote,
            cache: UserScopedStore(store: InMemoryDataStore(), userID: "AB220001")
        )

        let first = try await repository.load(semester: Self.semester)
        let second = try await repository.load(semester: Self.semester)
        let fetchCount = await remote.fetchCount()

        XCTAssertEqual(first.source, .remote)
        XCTAssertEqual(second.source, .cache)
        XCTAssertEqual(fetchCount, 1)
    }

    @MainActor
    func testRefreshFailureFallsBackToStaleCache() async throws {
        let remote = ScheduleRemoteStub(courses: [Self.course])
        let repository = ScheduleRepository(
            remote: remote,
            cache: UserScopedStore(store: InMemoryDataStore(), userID: "AB220001")
        )
        _ = try await repository.load(semester: Self.semester)
        await remote.setShouldFail(true)

        let snapshot = try await repository.load(semester: Self.semester, policy: .refresh)

        XCTAssertEqual(snapshot.source, .staleCache)
        XCTAssertEqual(snapshot.courses, [Self.course])
    }

    @MainActor
    func testCacheDoesNotLeakAcrossUsers() async throws {
        let dataStore = InMemoryDataStore()
        let firstRemote = ScheduleRemoteStub(courses: [Self.course])
        let firstRepository = ScheduleRepository(
            remote: firstRemote,
            cache: UserScopedStore(store: dataStore, userID: "AB220001")
        )
        _ = try await firstRepository.load(semester: Self.semester)

        let secondRemote = ScheduleRemoteStub(courses: [], shouldFail: true)
        let secondRepository = ScheduleRepository(
            remote: secondRemote,
            cache: UserScopedStore(store: dataStore, userID: "AB230001")
        )

        do {
            _ = try await secondRepository.load(semester: Self.semester)
            XCTFail("Expected remote failure without another user's cache")
        } catch is ScheduleRemoteStub.Failure {
            let fetchCount = await secondRemote.fetchCount()
            XCTAssertEqual(fetchCount, 1)
        }
    }

    private static let semester = Semester(schoolYear: "2025-2026", term: "1")!
    private static let course = Course(
        weekday: 1,
        startWeek: 1,
        endWeek: 16,
        location: "博学南楼101",
        name: "高等数学",
        teacher: "李老师",
        duration: 2,
        startPeriod: 1,
        courseID: "42",
        weekIndexes: [1, 3, 5]
    )
}

private actor ScheduleRemoteStub: ScheduleRemoteDataSource {
    enum Failure: Error {
        case unavailable
    }

    private let courses: [Course]
    private var shouldFail: Bool
    private var count = 0

    init(courses: [Course], shouldFail: Bool = false) {
        self.courses = courses
        self.shouldFail = shouldFail
    }

    func fetchCourses(for semester: Semester) async throws -> [Course] {
        count += 1
        if shouldFail {
            throw Failure.unavailable
        }
        return courses
    }

    func setShouldFail(_ shouldFail: Bool) {
        self.shouldFail = shouldFail
    }

    func fetchCount() -> Int {
        count
    }
}
