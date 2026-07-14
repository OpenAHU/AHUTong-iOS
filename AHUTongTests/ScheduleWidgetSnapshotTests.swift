import XCTest
@testable import AHUTong

final class ScheduleWidgetSnapshotTests: XCTestCase {
    func testSnapshotKeepsOnlyActiveWeekAndSortsForGrid() {
        let courses = [
            Course(weekday: 2, startWeek: 1, endWeek: 4, location: "B402", name: "计算机网络", teacher: "王老师", duration: 2, startPeriod: 3, courseID: "2", weekIndexes: [1, 2, 3, 4]),
            Course(weekday: 1, startWeek: 1, endWeek: 4, location: "A301", name: "移动应用开发", teacher: "张老师", duration: 2, startPeriod: 1, courseID: "1", weekIndexes: [1, 2, 3, 4]),
            Course(weekday: 1, startWeek: 5, endWeek: 8, location: "A101", name: "未开课程", teacher: "", duration: 2, startPeriod: 5, courseID: "3", weekIndexes: [5, 6, 7, 8])
        ]
        let snapshot = ScheduleWidgetSnapshot.make(courses: courses, currentWeek: 2)
        XCTAssertEqual(snapshot.status, .ready)
        XCTAssertEqual(snapshot.courses.map(\.name), ["移动应用开发", "计算机网络"])
        XCTAssertEqual(snapshot.courses.last?.endPeriod, 4)
    }

    func testSnapshotUsesExplicitEmptyAndSessionStates() {
        XCTAssertEqual(ScheduleWidgetSnapshot.make(courses: [], currentWeek: 3).status, .empty)
        XCTAssertEqual(ScheduleWidgetSnapshot.unavailable(.signedOut).status, .signedOut)
        XCTAssertEqual(ScheduleWidgetSnapshot.unavailable(.expired).status, .expired)
    }

    func testStoreRoundTripsSharedSnapshotAtomically() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = ScheduleWidgetSnapshotStore(fileURL: root.appendingPathComponent("widget.json"))
        let expected = ScheduleWidgetSnapshot.make(courses: [course()], currentWeek: 1, updatedAt: DemoDataState.referenceDate)
        try await store.save(expected)
        let loaded = await store.load()
        XCTAssertEqual(loaded, expected)
    }

    func testCorruptStoreFallsBackToSignedOutWithoutCrashing() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let file = root.appendingPathComponent("widget.json")
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data("not-json".utf8).write(to: file)
        let value = await ScheduleWidgetSnapshotStore(fileURL: file).load()
        XCTAssertEqual(value.status, .signedOut)
    }

    private func course() -> Course {
        Course(weekday: 1, startWeek: 1, endWeek: 16, location: "A301", name: "移动应用开发", teacher: "张老师", duration: 2, startPeriod: 1, courseID: "1", weekIndexes: Array(1...16))
    }
}
