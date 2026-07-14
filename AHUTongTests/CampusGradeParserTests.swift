import XCTest
@testable import AHUTong

final class CampusGradeParserTests: XCTestCase {
    func testParsesNestedGradeResponseAndSummary() throws {
        let data = Data(#"{
          "student": {"studentName":"张同学","majorName":"计算机科学与技术"},
          "gpa": 3.92,
          "majorRank": "8 / 120",
          "semesterId2studentGrades": {
            "202601": [{
              "courseName":"高等数学", "courseCode":"MATH1001", "credit":"5",
              "grade":"92", "gradePoint":"4.2", "courseProperty":"学科基础",
              "semesterId":202601, "semesterName":"2025-2026-1"
            }]
          }
        }"#.utf8)

        let report = try CampusGradeParser().parse(data)

        XCTAssertEqual(report.grades.count, 1)
        XCTAssertEqual(report.grades.first?.courseName, "高等数学")
        XCTAssertEqual(report.grades.first?.credit, 5)
        XCTAssertEqual(report.gradePointAverage, 3.92)
        XCTAssertEqual(report.rank, "8 / 120")
        XCTAssertTrue(report.studentProfiles.contains("计算机科学与技术"))
    }

    func testIgnoresObjectsThatAreNotGrades() throws {
        let report = try CampusGradeParser().parse(Data(#"{"message":"ok","items":[{"courseName":"无成绩课程"}]}"#.utf8))
        XCTAssertTrue(report.grades.isEmpty)
    }
}
