import XCTest
@testable import AHUTong

final class AppTabTests: XCTestCase {
    func testPrimaryTabsMatchAndroidOrder() {
        XCTAssertEqual(AppTab.allCases, [.home, .schedule, .tools, .settings])
        XCTAssertEqual(AppTab.allCases.map(\.title), ["主页", "课表", "小工具", "设置"])
    }

    func testEveryTabHasAUniqueSymbol() {
        let symbols = AppTab.allCases.map(\.systemImage)
        XCTAssertEqual(Set(symbols).count, AppTab.allCases.count)
    }
}
