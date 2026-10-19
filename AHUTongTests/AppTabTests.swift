import XCTest
import UIKit
@testable import AHUTong

final class AppTabTests: XCTestCase {
    func testPrimaryTabsMatchAndroidOrder() {
        XCTAssertEqual(AppTab.allCases, [.home, .schedule, .tools, .settings])
        XCTAssertEqual(AppTab.allCases.map(\.title), ["主页", "课表", "小工具", "设置"])
    }

    func testEveryTabHasABundledTemplateIcon() throws {
        let names = AppTab.allCases.map(\.iconAssetName)
        XCTAssertEqual(Set(names).count, AppTab.allCases.count)
        for name in names {
            let image = try XCTUnwrap(UIImage(named: name), "Missing tab asset: \(name)")
            XCTAssertEqual(image.renderingMode, .alwaysTemplate)
            XCTAssertEqual(image.size, CGSize(width: 24, height: 24))
        }
    }
}
