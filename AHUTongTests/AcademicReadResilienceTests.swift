import XCTest
@testable import AHUTong

@MainActor
final class AcademicReadResilienceTests: XCTestCase {
    func testCachedGradesExplainRefreshFailureAndClearWarningAfterRecovery() async {
        let api = AcademicReadAPIStub()
        let store = InMemoryDataStore()
        let model = GradeViewModel(api: api, userID: "student-a", store: store)
        await model.load()
        await api.setOffline(true)

        await model.load()

        XCTAssertEqual(model.state.value?.grades.first?.courseName, "高等数学")
        XCTAssertTrue(model.refreshMessage?.contains("上次保存") == true)
        let other = GradeViewModel(api: api, userID: "student-b", store: store)
        await other.load()
        XCTAssertNil(other.state.value)
        await api.setOffline(false)
        await model.load()
        XCTAssertNil(model.refreshMessage)
    }

    func testCachedExamsExplainRefreshFailureAndRemainAccountIsolated() async {
        let api = AcademicReadAPIStub()
        let store = InMemoryDataStore()
        let model = ExamViewModel(api: api, userID: "student-a", store: store)
        await model.load()
        await api.setOffline(true)

        await model.load()

        XCTAssertEqual(model.state.value?.first?.course, "操作系统")
        XCTAssertTrue(model.refreshMessage?.contains("上次保存") == true)
        let other = ExamViewModel(api: api, userID: "student-b", store: store)
        await other.load()
        XCTAssertNil(other.state.value)
        await api.setOffline(false)
        await model.load()
        XCTAssertNil(model.refreshMessage)
    }
}

private actor AcademicReadAPIStub: CampusCoreAPI {
    private var offline = false
    func setOffline(_ value: Bool) { offline = value }
    func initialize(cookiesJSON: String) {}
    func dumpCookies() -> String { "[]" }
    func cookiesFlat() -> String { "[]" }
    func schedule() -> [Course] { [] }
    func currentWeek() -> Int { 6 }
    func cardBalance() -> Double { 0 }
    func cardQRCode() -> String { "test-only" }
    func gradeProfiles() throws -> [CampusGradeStudentProfile] {
        if offline { throw CampusCoreError.sessionRefreshDeferred }
        return []
    }
    func grades() throws -> CampusGradeReport {
        if offline { throw CampusCoreError.sessionRefreshDeferred }
        return CampusGradeReport(
            grades: [CampusGrade(courseName: "高等数学", courseCode: "MATH1001", credit: 5,
                                 score: "92", gradePoint: 4.2, courseProperty: "基础课",
                                 semesterID: 202601, semesterName: "2025-2026-1")],
            gradePointAverage: 3.92, rank: nil, studentProfiles: []
        )
    }
    func exams() throws -> [CampusExam] {
        if offline { throw CampusCoreError.sessionRefreshDeferred }
        return [CampusExam(course: "操作系统", time: "2026-10-20 09:00~11:00", seatNumber: "18", location: "A210", isFinished: false)]
    }
}
