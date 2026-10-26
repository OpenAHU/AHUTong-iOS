import XCTest
@testable import AHUTong

final class HomeWidgetLayoutTests: XCTestCase {
    func testNormalizesUnknownAndDuplicateWidgetsToEightSlots() {
        let layout = HomeWidgetLayout(slots: ["grade", "grade", "unknown", "exam"])

        XCTAssertEqual(layout.slots.count, 8)
        XCTAssertEqual(layout.slots[0], "grade")
        XCTAssertNil(layout.slots[1])
        XCTAssertNil(layout.slots[2])
        XCTAssertEqual(layout.slots[3], "exam")
    }

    func testDecodingRemovesRetiredWidgets() throws {
        let data = Data(#"{"slots":["grade","evaluation","exam",null,null,null,null,null]}"#.utf8)

        let layout = try JSONDecoder().decode(HomeWidgetLayout.self, from: data)

        XCTAssertEqual(layout.slots[0], "grade")
        XCTAssertNil(layout.slots[1])
        XCTAssertEqual(layout.slots[2], "exam")
    }

    func testAddRemoveAndMovePreserveUniqueSlots() {
        var layout = HomeWidgetLayout(slots: ["grade", nil, "exam"])
        layout.add("weather")
        XCTAssertEqual(layout.slots[1], "weather")

        layout.move(from: 0, to: 2)
        XCTAssertEqual(layout.slots[0], "exam")
        XCTAssertEqual(layout.slots[2], "grade")

        layout.remove(at: 2)
        XCTAssertNil(layout.slots[2])
        XCTAssertEqual(layout.slots.compactMap { $0 }.count, Set(layout.slots.compactMap { $0 }).count)

        layout.place("weather", at: 5)
        XCTAssertNil(layout.slots[1])
        XCTAssertEqual(layout.slots[5], "weather")
    }

    func testCourseTimelineSeparatesCompletedOngoingAndUpcomingCourses() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let courses = [
            Course(
                weekday: 1,
                startWeek: 1,
                endWeek: 16,
                location: "博学南楼 A101",
                name: "第一节",
                teacher: "教师",
                duration: 2,
                startPeriod: 1,
                courseID: "timeline-1",
                weekIndexes: Array(1...16)
            ),
            Course(
                weekday: 1,
                startWeek: 1,
                endWeek: 16,
                location: "博学南楼 A102",
                name: "第二节",
                teacher: "教师",
                duration: 2,
                startPeriod: 3,
                courseID: "timeline-2",
                weekIndexes: Array(1...16)
            ),
            Course(
                weekday: 1,
                startWeek: 1,
                endWeek: 16,
                location: "博学南楼 A103",
                name: "第三节",
                teacher: "教师",
                duration: 2,
                startPeriod: 6,
                courseID: "timeline-3",
                weekIndexes: Array(1...16)
            )
        ]
        let now = try XCTUnwrap(
            calendar.date(from: DateComponents(year: 2026, month: 7, day: 13, hour: 10, minute: 20))
        )

        XCTAssertEqual(
            HomeCourseTimeline.states(for: courses, now: now, calendar: calendar),
            [.completed, .ongoing, .upcoming]
        )
    }
}
