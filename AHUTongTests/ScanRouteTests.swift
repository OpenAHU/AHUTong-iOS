import XCTest
@testable import AHUTong

final class ScanRouteTests: XCTestCase {
    func testChaoxingHandoffPreservesSignedURLWithoutDecodingItsParameters() throws {
        let raw = "https://mobilelearn.chaoxing.com/widget/sign/pcqrcode?id=12&enc=a%2Bb&c=x+y&DB_STRATEGY=PRIMARY_KEY"
        guard case let .chaoxing(url) = ScanRoute(raw) else { return XCTFail("Expected learning app handoff") }
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        XCTAssertEqual(components.scheme, "chaoxingshareback")
        XCTAssertEqual(components.queryItems?.first(where: { $0.name == "url" })?.value, raw)
        XCTAssertEqual(components.queryItems?.first(where: { $0.name == "sharebacktype" })?.value, "1")
    }

    func testMeituanHandoffUsesConstructionTimeAndOriginalBikeCode() throws {
        let time = Date(timeIntervalSince1970: 1_793_280_123.456)
        let raw = "http://t8.pub/test-bike"
        guard case let .meituan(url) = ScanRoute(raw, now: time) else { return XCTFail("Expected bike handoff") }
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        XCTAssertEqual(components.scheme, "imeituan")
        XCTAssertEqual(components.path, "/bike/scan")
        XCTAssertEqual(components.queryItems?.first(where: { $0.name == "time" })?.value, "1793280123456")
        XCTAssertEqual(components.queryItems?.first(where: { $0.name == "url" })?.value, raw)
    }

    func testUntrustedOrMalformedCodesCannotLaunchAnApplication() {
        for raw in ["javascript:alert(1)", "weixin://", "https://mobilelearn.chaoxing.com.evil.example/widget/sign/e",
                    "https://mobilelearn.chaoxing.com@evil.example/widget/sign/e", "https://notyuketang.cn/x",
                    "https://www.mobike.com/download/app.html?b=oops", "AB12CD34EF", "8611234567"] {
            XCTAssertEqual(ScanRoute(raw), .unsupported, raw)
        }
    }
}
