import XCTest
@testable import AHUTong

final class ScheduleWidgetSnapshotTests: XCTestCase {
    func testWidgetUsesTheSameFallbackWeekRangeAsMainSchedule() {
        let course = Course(weekday: 1, startWeek: 3, endWeek: 8, location: "A301", name: "周次范围课程",
            teacher: "", duration: 2, startPeriod: 1, courseID: "range-only", weekIndexes: [])
        XCTAssertTrue(course.occurs(inWeek: 7))
        let snapshot = ScheduleWidgetSnapshot.make(courses: [course], currentWeek: 7)
        XCTAssertEqual(snapshot.status, .ready)
        XCTAssertEqual(snapshot.courses.map(\.name), [course.name])
        XCTAssertEqual(snapshot.courses.first?.weekIndexes, Array(3...8))
        let next = snapshot.resolved(at: snapshot.updatedAt.addingTimeInterval(7 * 86_400))
        XCTAssertEqual(next.status, .ready)
        XCTAssertEqual(next.currentWeek, 8)
        let expired = snapshot.resolved(at: snapshot.updatedAt.addingTimeInterval(14 * 86_400))
        XCTAssertEqual(expired.status, .empty)
        XCTAssertTrue(expired.courses.isEmpty)
    }

    func testTemporaryContainerFailureCanRecoverWithoutRestartingTheStore() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let probe = WidgetContainerProbe()
        let store = ScheduleWidgetSnapshotStore(container: { probe.url })
        let initial = await store.load()
        XCTAssertEqual(initial.status, .sharingUnavailable)
        probe.url = root
        let expected = ScheduleWidgetSnapshot.make(courses: [course()], currentWeek: 1)
        try await store.save(expected)
        let loaded = await store.load()
        XCTAssertEqual(loaded, expected)
    }
    func testMissingSharedContainerIsNotMisreportedAsSignedOut() async {
        let store = ScheduleWidgetSnapshotStore(containerURL: nil)
        let snapshot = await store.load()
        XCTAssertEqual(snapshot.status, .sharingUnavailable)
        do {
            try await store.save(.unavailable(.signedOut))
            XCTFail("A private app directory cannot share data with a widget")
        } catch {
            XCTAssertTrue(error is ScheduleWidgetStoreError)
        }
    }

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

    func testSnapshotAdvancesWeekWithoutOpeningTheApp() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        let updated = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 7, day: 13)))
        let later = try XCTUnwrap(calendar.date(byAdding: .day, value: 7, to: updated))
        let snapshot = ScheduleWidgetSnapshot.make(courses: [course()], currentWeek: 2, updatedAt: updated)
        let resolved = snapshot.resolved(at: later, calendar: calendar)
        XCTAssertEqual(resolved.currentWeek, 3)
        XCTAssertEqual(resolved.courses.map(\.name), ["移动应用开发"])
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

private final class WidgetContainerProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var value: URL?
    var url: URL? {
        get { lock.withLock { value } }
        set { lock.withLock { value = newValue } }
    }
}
