import XCTest
@testable import AHUTong

@MainActor
final class GradeViewModelTests: XCTestCase {
    func testOneBrokenProfileDoesNotHideAnotherProfilesGrades() async throws {
        let api = GradeProfileCampusAPIStub()
        let model = GradeViewModel(
            api: api,
            userID: "grade-isolation-test",
            store: InMemoryDataStore()
        )

        await model.load()

        XCTAssertEqual(model.profiles.map(\.id), ["broken", "working"])
        XCTAssertEqual(model.selectedProfileID, "working")
        XCTAssertNotNil(model.profileErrors["broken"])
        guard case let .loaded(report) = model.state else {
            return XCTFail("The working profile should still be visible")
        }
        XCTAssertEqual(report.grades.map(\.courseName), ["编译原理"])

        model.selectProfile(model.profiles[0])
        guard case let .failed(error) = model.state else {
            return XCTFail("Selecting the failed profile should explain the isolated failure")
        }
        XCTAssertTrue(error.message.contains("加载失败"))
    }

    func testEvaluationGateRecognizesHTMLPayloadAndCleansNormalScore() {
        let gated = #"<a href="/student-summation">请先完成评教后查看</a>"#

        XCTAssertTrue(GradeEvaluationGate.isRequired(gated))
        XCTAssertEqual(GradeEvaluationGate.displayText("<b>优秀</b>&nbsp;"), "优秀")
        XCTAssertFalse(GradeEvaluationGate.isRequired("95"))
    }
}

private actor GradeProfileCampusAPIStub: CampusCoreAPI {
    enum Failure: LocalizedError {
        case unavailable

        var errorDescription: String? { "测试专业接口不可用" }
    }

    private let workingReport = CampusGradeReport(
        grades: [
            CampusGrade(
                courseName: "编译原理",
                courseCode: "COMP4001",
                credit: 3,
                score: "95",
                gradePoint: 4,
                courseProperty: "专业必修",
                semesterID: 202520261,
                semesterName: "2025-2026-1"
            )
        ],
        gradePointAverage: 4,
        rank: nil,
        studentProfiles: ["working"]
    )

    func initialize(cookiesJSON: String) {}
    func login(studentID: String, password: String) throws -> User {
        throw CampusCoreError.invalidResponse
    }
    func dumpCookies() -> String { "[]" }
    func cookiesFlat() -> String { "[]" }
    func schedule() throws -> [Course] { throw CampusCoreError.invalidResponse }
    func currentWeek() throws -> Int { throw CampusCoreError.invalidResponse }
    func exams() throws -> [CampusExam] { throw CampusCoreError.invalidResponse }
    func grades() throws -> CampusGradeReport { throw CampusCoreError.invalidResponse }

    func grades(studentID: String) throws -> CampusGradeReport {
        guard studentID == "working" else { throw Failure.unavailable }
        return workingReport
    }

    func gradeProfiles() -> [CampusGradeStudentProfile] {
        [
            CampusGradeStudentProfile(
                id: "broken",
                trainingType: "微专业",
                department: "创新学院",
                major: "人工智能"
            ),
            CampusGradeStudentProfile(
                id: "working",
                trainingType: "主修",
                department: "计算机科学与技术学院",
                major: "计算机科学与技术"
            )
        ]
    }

    func cardBalance() throws -> Double { throw CampusCoreError.invalidResponse }
    func cardQRCode() throws -> String { throw CampusCoreError.invalidResponse }
}
