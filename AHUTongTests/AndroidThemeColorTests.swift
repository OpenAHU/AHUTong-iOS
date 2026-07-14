import XCTest
@testable import AHUTong

final class AndroidThemeColorTests: XCTestCase {
    func testOptionsMatchAndroidThemeSelectorOrder() {
        XCTAssertEqual(AndroidThemeColor.options.first?.name, "默认")
        XCTAssertEqual(AndroidThemeColor.options.dropFirst().first?.name, "极光蓝")
        XCTAssertEqual(AndroidThemeColor.options.last?.name, "北极薄荷")
        XCTAssertEqual(AndroidThemeColor.options.count, 13)
    }

    func testARGBHexIgnoresAlphaAndKeepsRGBComponents() {
        let color = AndroidThemeColor.rgbComponents(for: "#FF4A90E2")

        XCTAssertEqual(color.red, 74 / 255, accuracy: 0.0001)
        XCTAssertEqual(color.green, 144 / 255, accuracy: 0.0001)
        XCTAssertEqual(color.blue, 226 / 255, accuracy: 0.0001)
    }

    func testInvalidHexFallsBackToAndroidBrand() {
        let color = AndroidThemeColor.rgbComponents(for: "invalid")

        XCTAssertEqual(color.red, 0, accuracy: 0.0001)
        XCTAssertEqual(color.green, 127 / 255, accuracy: 0.0001)
        XCTAssertEqual(color.blue, 172 / 255, accuracy: 0.0001)
    }
}
