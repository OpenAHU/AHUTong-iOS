import XCTest
@testable import AHUTong

final class AndroidThemeColorTests: XCTestCase {
    func testDefaultIsAuroraBlueAndPreviousDefaultRemainsSelectableAsIrisPurple() {
        XCTAssertEqual(AndroidThemeColor.options.first?.name, "极光蓝")
        XCTAssertEqual(AndroidThemeColor.options.dropFirst().first?.name, "鸢尾紫")
        XCTAssertEqual(AndroidThemeColor.options.last?.name, "北极薄荷")
        XCTAssertEqual(AndroidThemeColor.options.count, 13)
        for value in ["default", "blue", "#FF4A90E2"] {
            let color = AndroidThemeColor.rgbComponents(for: value)
            XCTAssertEqual(color.red, 74 / 255, accuracy: 0.0001)
            XCTAssertEqual(color.green, 144 / 255, accuracy: 0.0001)
            XCTAssertEqual(color.blue, 226 / 255, accuracy: 0.0001)
            XCTAssertEqual(AndroidThemeColor.canonicalValue(value), AndroidThemeColor.defaultValue)
        }
        let purple = AndroidThemeColor.rgbComponents(for: AndroidThemeColor.irisPurple)
        XCTAssertEqual(purple.red, 103 / 255, accuracy: 0.0001)
        XCTAssertEqual(purple.green, 80 / 255, accuracy: 0.0001)
        XCTAssertEqual(purple.blue, 164 / 255, accuracy: 0.0001)
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
