import XCTest
@testable import AHUTong

final class SemesterCurrentTests: XCTestCase {
    func testCurrentSemesterAcrossAcademicYearBoundaries() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!

        let july = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 7, day: 15)))
        let september = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 9, day: 1)))

        XCTAssertEqual(Semester.current(date: july, calendar: calendar).rawValue, "2025-2026-2")
        XCTAssertEqual(Semester.current(date: september, calendar: calendar).rawValue, "2026-2027-1")
        XCTAssertEqual(Semester.current(date: july, calendar: calendar).next.rawValue, "2026-2027-1")
        XCTAssertEqual(Semester.current(date: september, calendar: calendar).next.rawValue, "2026-2027-2")
    }
}
