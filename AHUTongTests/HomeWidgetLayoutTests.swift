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
}
