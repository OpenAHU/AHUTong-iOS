import Foundation
import XCTest
@testable import AHUTong

final class ExperienceScheduleStoreTests: XCTestCase {
    func testImportsValidCurrentSemesterAndDeduplicatesCourses() async throws {
        let store = ExperienceScheduleStore(store: InMemoryDataStore())
        let semester = Semester.current()
        let course = Self.course()
        let data = try JSONEncoder().encode(
            ExperienceScheduleDocumentV1(
                version: 1,
                semester: semester,
                currentWeek: 3,
                courses: [course, course]
            )
        )

        let imported = try await store.importDocument(
            data,
            allowedSemesters: [semester, semester.next]
        )
        let snapshot = await store.snapshot()

        XCTAssertEqual(imported, semester)
        XCTAssertEqual(snapshot.currentWeek, 3)
        XCTAssertEqual(snapshot.coursesBySemester[semester.rawValue], [course])
    }

    func testInvalidImportDoesNotOverwriteExistingSchedule() async throws {
        let store = ExperienceScheduleStore(store: InMemoryDataStore())
        let semester = Semester.current()
        try await store.save(courses: [Self.course()], semester: semester, currentWeek: 2)
        let original = await store.snapshot()

        do {
            _ = try await store.importDocument(
                Data(#"{"version":2}"#.utf8),
                allowedSemesters: [semester, semester.next]
            )
            XCTFail("Expected invalid document")
        } catch {}

        let restored = await store.snapshot()
        XCTAssertEqual(restored, original)
    }

    func testRejectsUnrelatedSemester() async throws {
        let store = ExperienceScheduleStore(store: InMemoryDataStore())
        let current = Semester.current()
        let unrelated = current.next.next
        let data = try JSONEncoder().encode(
            ExperienceScheduleDocumentV1(
                version: 1,
                semester: unrelated,
                currentWeek: 1,
                courses: [Self.course()]
            )
        )

        await XCTAssertThrowsErrorAsync {
            _ = try await store.importDocument(data, allowedSemesters: [current, current.next])
        }
    }

    @MainActor
    func testExperienceViewModelNeverCallsCampusAPI() async throws {
        let dataStore = InMemoryDataStore()
        let experienceStore = ExperienceScheduleStore(store: dataStore)
        let semester = Semester.current()
        try await experienceStore.save(
            courses: [Self.course()],
            semester: semester,
            currentWeek: 4
        )
        let api = NoCallCampusAPI()
        let model = ScheduleViewModel(
            api: api,
            userID: AppModel.experienceUser.studentID,
            accessMode: .experience,
            experienceStore: experienceStore
        )

        await model.load()

        let callCount = await api.callCount()
        XCTAssertEqual(callCount, 0)
        XCTAssertEqual(model.currentWeek, 4)
        XCTAssertEqual(model.state.value, [Self.course()])
    }

    private static func course() -> Course {
        Course(
            weekday: 1,
            startWeek: 1,
            endWeek: 16,
            location: "博学南楼 A101",
            name: "课程名称",
            teacher: "教师",
            duration: 2,
            startPeriod: 1,
            courseID: "local-1",
            weekIndexes: Array(1...16)
        )
    }
}

private actor NoCallCampusAPI: CampusCoreAPI {
    private var calls = 0

    func initialize(cookiesJSON: String) throws { calls += 1; throw CampusCoreError.invalidResponse }
    func dumpCookies() throws -> String { calls += 1; throw CampusCoreError.invalidResponse }
    func cookiesFlat() throws -> String { calls += 1; throw CampusCoreError.invalidResponse }
    func schedule() throws -> [Course] { calls += 1; throw CampusCoreError.invalidResponse }
    func currentWeek() throws -> Int { calls += 1; throw CampusCoreError.invalidResponse }
    func exams() throws -> [CampusExam] { calls += 1; throw CampusCoreError.invalidResponse }
    func grades() throws -> CampusGradeReport { calls += 1; throw CampusCoreError.invalidResponse }
    func cardBalance() throws -> Double { calls += 1; throw CampusCoreError.invalidResponse }
    func cardQRCode() throws -> String { calls += 1; throw CampusCoreError.invalidResponse }
    func callCount() -> Int { calls }
}

private func XCTAssertThrowsErrorAsync(
    _ expression: () async throws -> Void,
    file: StaticString = #filePath,
    line: UInt = #line
) async {
    do {
        try await expression()
        XCTFail("Expected error", file: file, line: line)
    } catch {}
}
