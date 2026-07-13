import Foundation
import XCTest
@testable import AHUTong

final class SemesterWeekResolverTests: XCTestCase {
    func testSemesterParsesCanonicalAndLegacyKeys() {
        XCTAssertEqual(
            Semester.parse(" 2025-2026-1 "),
            Semester(schoolYear: "2025-2026", term: "1")
        )
        XCTAssertEqual(
            Semester.parse("2", fallbackSchoolYear: "2025-2026"),
            Semester(schoolYear: "2025-2026", term: "2")
        )
        XCTAssertNil(Semester.parse("2025-1"))
        XCTAssertNil(Semester.parse("2026-2025-1"))
    }

    func testLocalWeekResolutionUsesCalendarDaysAndISOWeekday() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let start = try XCTUnwrap(calendar.date(from: DateComponents(year: 2025, month: 9, day: 1)))
        let now = try XCTUnwrap(calendar.date(from: DateComponents(year: 2025, month: 9, day: 17)))

        let position = ScheduleWeekResolver.resolve(
            semesterStart: start,
            now: now,
            calendar: calendar
        )

        XCTAssertEqual(position.week, 3)
        XCTAssertEqual(position.weekday, 3)
        XCTAssertEqual(position.source, .local)
    }

    func testDatesBeforeSemesterStartClampToWeekOne() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let start = try XCTUnwrap(calendar.date(from: DateComponents(year: 2025, month: 9, day: 1)))
        let now = try XCTUnwrap(calendar.date(from: DateComponents(year: 2025, month: 8, day: 31)))

        let position = ScheduleWeekResolver.resolve(
            semesterStart: start,
            now: now,
            calendar: calendar
        )

        XCTAssertEqual(position.week, 1)
        XCTAssertEqual(position.weekday, 7)
    }
}
