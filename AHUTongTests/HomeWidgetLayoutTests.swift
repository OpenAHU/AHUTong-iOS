import XCTest
@testable import AHUTong

final class HomeWidgetLayoutTests: XCTestCase {
    func testDefaultMatchesAndroidHomeWidgets() {
        XCTAssertEqual(
            HomeWidgetLayout().slots,
            ["bathroom", "electricity", nil, nil, nil, nil, nil, nil]
        )
    }

    func testNormalizesUnknownAndDuplicateWidgetsToEightSlots() {
        let layout = HomeWidgetLayout(slots: ["grade", "grade", "unknown", "exam"])

        XCTAssertEqual(layout.slots.count, 8)
        XCTAssertEqual(layout.slots[0], "grade")
        XCTAssertNil(layout.slots[1])
        XCTAssertNil(layout.slots[2])
        XCTAssertEqual(layout.slots[3], "exam")
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
    }

    @MainActor
    func testCourseSummaryMatchesAndroidOngoingCourseAtFixedBaselineTime() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let summary = HomeCourseSummary.make(
            courses: ScheduleViewModel.demoCourses.filter { $0.weekday == 2 },
            now: DemoDataState.referenceDate,
            calendar: calendar
        )

        XCTAssertEqual(summary.title, "正在上课")
        XCTAssertEqual(summary.headline, "计算机网络")
        XCTAssertEqual(summary.detail, "距下课还有 1小时25分钟")
        XCTAssertEqual(summary.focusedCourseID, "demo-3")
    }

    @MainActor
    func testCourseSummaryReportsNextAndFinishedStates() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let course = ScheduleViewModel.demoCourses.first { $0.courseID == "demo-3" }!

        let before = HomeCourseSummary.make(
            courses: [course],
            now: Date(timeIntervalSince1970: 1_784_021_400),
            calendar: calendar
        )
        XCTAssertEqual(before.title, "下节课是")
        XCTAssertEqual(before.detail, "还有 20分钟，在 笃行北楼 B402")

        let after = HomeCourseSummary.make(
            courses: [course],
            now: Date(timeIntervalSince1970: 1_784_030_400),
            calendar: calendar
        )
        XCTAssertEqual(after.title, "今日课程")
        XCTAssertEqual(after.headline, "已全部上完")
    }
}
