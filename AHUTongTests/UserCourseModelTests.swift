import Foundation
import XCTest
@testable import AHUTong

final class UserCourseModelTests: XCTestCase {
    func testUserDecodesAndroidFieldNamesAndBuildsAcademicYears() throws {
        let user = try JSONDecoder().decode(
            User.self,
            from: Data(#"{"name":"张三","xh":"AB220001"}"#.utf8)
        )
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let date = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 7, day: 14)))

        XCTAssertEqual(user.name, "张三")
        XCTAssertEqual(user.studentID, "AB220001")
        XCTAssertEqual(
            user.academicYears(asOf: date, calendar: calendar),
            ["2025-2026", "2024-2025", "2023-2024", "2022-2023"]
        )
    }

    func testMalformedStudentIDDoesNotCrashAcademicYearResolution() throws {
        let user = User(name: "访客", studentID: "guest")
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let date = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 7, day: 14)))

        XCTAssertEqual(user.academicYears(asOf: date, calendar: calendar), [])
    }

    func testCourseDecodesStringNumbersAndUsesExactWeekIndexes() throws {
        let data = Data(
            #"{"weekday":"2","startWeek":"1","endWeek":"16","extra":"","location":"博学南楼101","name":"高等数学","teacher":"李老师","length":"2","startTime":"3","courseId":"42","weekIndexes":[5,1,3,3]}"#.utf8
        )

        let course = try JSONDecoder().decode(Course.self, from: data)

        XCTAssertEqual(course.weekday, 2)
        XCTAssertEqual(course.startWeek, 1)
        XCTAssertEqual(course.endWeek, 5)
        XCTAssertEqual(course.weekIndexes, [1, 3, 5])
        XCTAssertEqual(course.endPeriod, 4)
        XCTAssertTrue(course.occurs(inWeek: 3))
        XCTAssertFalse(course.occurs(inWeek: 2))
        XCTAssertTrue(course.isStructurallyValid)
    }

    func testLegacyCourseWithoutWeekIndexesFallsBackToRange() throws {
        let data = Data(
            #"{"weekday":1,"startWeek":2,"endWeek":4,"location":"行知楼","name":"大学英语","teacher":"王老师","length":2,"startTime":1,"courseId":"7"}"#.utf8
        )

        let course = try JSONDecoder().decode(Course.self, from: data)

        XCTAssertEqual(course.activeWeeks, [2, 3, 4])
        XCTAssertTrue(course.occurs(inWeek: 4))
        XCTAssertFalse(course.occurs(inWeek: 5))
    }

    func testScheduleTextMatchesAndroidLocationAndWeekRules() {
        let biweekly = Course(
            weekday: 1,
            startWeek: 1,
            endWeek: 9,
            location: "博学南楼 A101 [临时教室]",
            name: "测试课程",
            teacher: "老师",
            duration: 2,
            startPeriod: 1,
            courseID: "format",
            weekIndexes: [1, 3, 5, 7, 9]
        )
        let irregular = Course(
            weekday: 1,
            startWeek: 1,
            endWeek: 8,
            location: "体育场",
            name: "测试课程",
            teacher: "老师",
            duration: 2,
            startPeriod: 1,
            courseID: "irregular",
            weekIndexes: [1, 2, 5, 8]
        )

        XCTAssertEqual(ScheduleTextFormatter.shortLocation(biweekly.location), "博南A101")
        XCTAssertEqual(ScheduleTextFormatter.shortLocation(irregular.location), "体")
        XCTAssertEqual(ScheduleTextFormatter.weekRange(for: biweekly), "1-9单周")
        XCTAssertEqual(ScheduleTextFormatter.weekRange(for: irregular), "1/2/5/8周")
    }
}
