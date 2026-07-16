import XCTest
@testable import AHUTong

final class CampusExamDecodingTests: XCTestCase {
    func testDecodesRustAndAndroidExamContract() throws {
        let data = Data(#"[{"course":"操作系统(期末)","time":"2026-07-20 09:00~11:00","seatNum":"18","location":"磬苑校区-博学南楼-A210","finished":false}]"#.utf8)

        let exam = try XCTUnwrap(JSONDecoder().decode([CampusExam].self, from: data).first)

        XCTAssertEqual(exam.course, "操作系统(期末)")
        XCTAssertEqual(exam.seatNumber, "18")
        XCTAssertEqual(exam.location, "磬苑校区-博学南楼-A210")
        XCTAssertFalse(exam.isFinished)
    }

    func testToleratesNumericSeatAndMissingOptionalFields() throws {
        let data = Data(#"[{"course":"计算机网络","time":"2026-07-21 14:00~16:00","seatNum":7,"location":null,"finished":1}]"#.utf8)

        let exam = try XCTUnwrap(JSONDecoder().decode([CampusExam].self, from: data).first)

        XCTAssertEqual(exam.seatNumber, "7")
        XCTAssertEqual(exam.location, "待公布")
        XCTAssertTrue(exam.isFinished)
    }
}
