import XCTest
@testable import AHUTong

/// A repeatable offline workload for comparing Release optimization modes.
final class ReleaseWorkloadPerformanceTests: XCTestCase {
    func testScheduleDecodeAndWidgetSnapshotPerformance() throws {
        let courses = (0..<84).map { index in
            Course(weekday: index % 7 + 1, startWeek: 1, endWeek: 20,
                   location: "教学楼A301", name: "课程\(index)", teacher: "教师",
                   duration: 2, startPeriod: index % 6 * 2 + 1,
                   courseID: "fixture-\(index)", weekIndexes: Array(1...20))
        }
        let data = try JSONEncoder().encode(courses)
        let decoded = try JSONDecoder().decode([Course].self, from: data)
        XCTAssertEqual(ScheduleWidgetSnapshot.make(courses: decoded, currentWeek: 7).courses.count, 84)
        let options = XCTMeasureOptions()
        options.iterationCount = 5
        measure(metrics: [XCTClockMetric()], options: options) {
            let decoder = JSONDecoder()
            for _ in 0..<100 {
                do {
                    let decoded = try decoder.decode([Course].self, from: data)
                    let snapshot = ScheduleWidgetSnapshot.make(courses: decoded, currentWeek: 7)
                    XCTAssertEqual(snapshot.courses.count, 84)
                } catch {
                    XCTFail("Synthetic schedule decoding failed: \(error)")
                }
            }
        }
    }
}
