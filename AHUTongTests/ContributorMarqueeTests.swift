import XCTest
@testable import AHUTong

final class ContributorMarqueeTests: XCTestCase {
    func testPauseAndResumePreservePositionWithoutCountingPausedTime() {
        let start = Date(timeIntervalSince1970: 100)
        var clock = ContributorMarqueeClock(now: start)
        XCTAssertEqual(clock.distance(at: start.addingTimeInterval(10)), 120)
        clock.setPaused(true, at: start.addingTimeInterval(10))
        XCTAssertEqual(clock.distance(at: start.addingTimeInterval(100)), 120)
        clock.setPaused(true, at: start.addingTimeInterval(100))
        clock.setPaused(false, at: start.addingTimeInterval(110))
        XCTAssertEqual(clock.distance(at: start.addingTimeInterval(120)), 240)
    }

    func testPausingOneRowDoesNotStopOtherRow() {
        let start = Date(timeIntervalSince1970: 100)
        var first = ContributorMarqueeClock(now: start)
        let second = ContributorMarqueeClock(now: start)
        first.setPaused(true, at: start.addingTimeInterval(1))
        XCTAssertEqual(first.distance(at: start.addingTimeInterval(10)), 12)
        XCTAssertEqual(second.distance(at: start.addingTimeInterval(10)), 120)
    }

    func testRandomRowsContainEveryDeveloperExactlyOnceAndStayBalanced() {
        for _ in 0..<20 {
            let rows = ContributorRows.shuffled(using: ContributorsCatalog.developers)
            XCTAssertEqual(rows.count, 2)
            XCTAssertLessThanOrEqual(abs(rows[0].count - rows[1].count), 1)
            XCTAssertEqual(Set(rows.flatMap { $0 }.map(\.id)), Set(ContributorsCatalog.developers.map(\.id)))
            XCTAssertEqual(rows.flatMap { $0 }.count, ContributorsCatalog.developers.count)
        }
    }
}
