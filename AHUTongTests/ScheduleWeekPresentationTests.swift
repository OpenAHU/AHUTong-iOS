import XCTest
@testable import AHUTong

final class ScheduleWeekPresentationTests: XCTestCase {
    func testSundayFirstIsOffByDefaultAndMondayLayoutIsUnchanged() {
        let layout = ScheduleWeekPresentation()
        XCTAssertFalse(layout.sundayFirst)
        XCTAssertEqual(layout.weekdays, Array(1...7))
        XCTAssertEqual(layout.pages, 1...20)
        XCTAssertEqual(layout.column(for: 7), 6)
        XCTAssertEqual(layout.teachingWeek(weekday: 7, page: 1), 1)
    }

    func testSundayFirstDatesAreConsecutiveAcrossYearBoundary() throws {
        let layout = ScheduleWeekPresentation(sundayFirst: true)
        let calendar = ScheduleCalendar.campus
        let reference = try XCTUnwrap(calendar.date(from: DateComponents(year: 2027, month: 1, day: 1)))
        let dates = try layout.weekdays.map { weekday in
            try XCTUnwrap(ScheduleCalendar.date(week: layout.teachingWeek(weekday: weekday, page: 7),
                weekday: weekday, currentWeek: 7, referenceDate: reference))
        }
        XCTAssertEqual(calendar.dateComponents([.year, .month, .day], from: dates[0]), DateComponents(year: 2026, month: 12, day: 27))
        XCTAssertEqual(calendar.dateComponents([.year, .month, .day], from: dates[6]), DateComponents(year: 2027, month: 1, day: 2))
        for index in 1..<dates.count {
            XCTAssertEqual(calendar.dateComponents([.day], from: dates[index - 1], to: dates[index]).day, 1)
        }
        XCTAssertEqual(layout.weekdays.map { layout.column(for: $0) }, Array(0...6))
    }

    func testEveryCourseKeepsItsActualDateInEitherLayout() throws {
        let reference = try XCTUnwrap(ScheduleCalendar.campus.date(from: DateComponents(year: 2026, month: 10, day: 22)))
        for sundayFirst in [false, true] {
            let layout = ScheduleWeekPresentation(sundayFirst: sundayFirst)
            for teachingWeek in 1...20 {
                for weekday in 1...7 {
                    let page = layout.page(teachingWeek: teachingWeek, weekday: weekday)
                    XCTAssertTrue(layout.pages.contains(page))
                    let mappedWeek = layout.teachingWeek(weekday: weekday, page: page)
                    XCTAssertEqual(mappedWeek, teachingWeek)
                    XCTAssertEqual(ScheduleCalendar.date(week: mappedWeek, weekday: weekday, currentWeek: 7, referenceDate: reference),
                                   ScheduleCalendar.date(week: teachingWeek, weekday: weekday, currentWeek: 7, referenceDate: reference))
                }
            }
        }
    }

    func testSundayAndFollowingMondayStayOnTheSameVisiblePage() {
        let layout = ScheduleWeekPresentation(sundayFirst: true)
        XCTAssertEqual(layout.page(teachingWeek: 7, weekday: 6), 7)
        XCTAssertEqual(layout.page(teachingWeek: 7, weekday: 7), 8)
        XCTAssertEqual(layout.page(teachingWeek: 8, weekday: 1), 8)
        XCTAssertEqual(layout.teachingWeek(weekday: 7, page: 1), 0)
        XCTAssertEqual(layout.page(teachingWeek: 20, weekday: 7), 21)
        XCTAssertEqual(layout.accessibilityTitle(page: 21), "学期末")
        XCTAssertEqual(ScheduleWeekPresentation().clamped(21), 20)
    }
}
