import XCTest
@testable import AHUTong

final class CampusExamDisplayStatusTests: XCTestCase {
    func testResolvesOngoingFutureAndFinishedExamStates() throws {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        let now = try XCTUnwrap(formatter.date(from: "2026-07-14 10:00"))

        XCTAssertEqual(CampusExamDisplayStatus.resolve(time: "2026-07-14 09:00~11:00", isFinished: false, now: now), .ongoing)
        XCTAssertEqual(CampusExamDisplayStatus.resolve(time: "2026-07-14 11:01~12:00", isFinished: false, now: now), .notStarted)
        XCTAssertEqual(CampusExamDisplayStatus.resolve(time: "2026-07-14 08:00~09:59", isFinished: false, now: now), .finished)
    }

    func testUsesFinishedFlagForInvalidLegacyTime() {
        XCTAssertEqual(CampusExamDisplayStatus.resolve(time: "待公布", isFinished: true), .finished)
        XCTAssertEqual(CampusExamDisplayStatus.resolve(time: "待公布", isFinished: false), .invalid)
    }

    func testShortensThreePartAndroidLocationButPreservesOtherFormats() {
        XCTAssertEqual(
            CampusExamLocationFormatter.shortened("磬苑校区-博学楼-博学楼A101"),
            "磬苑校区 博学楼A101"
        )
        XCTAssertEqual(CampusExamLocationFormatter.shortened("博学南楼 A210"), "博学南楼 A210")
    }
}
