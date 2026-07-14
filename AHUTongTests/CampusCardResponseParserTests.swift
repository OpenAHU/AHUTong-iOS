import XCTest
@testable import AHUTong

final class CampusCardResponseParserTests: XCTestCase {
    func testParsesAndroidBalanceEnvelope() throws {
        let data = Data(#"{"code":10000,"msg":"success","object":126.35}"#.utf8)
        XCTAssertEqual(try CampusCardResponseParser().balance(from: data), 126.35, accuracy: 0.001)
    }

    func testParsesAndroidQRCodeEnvelope() throws {
        let data = Data(#"{"code":10000,"msg":"success","object":"PAYLOAD"}"#.utf8)
        XCTAssertEqual(try CampusCardResponseParser().qrPayload(from: data), "PAYLOAD")
    }

    func testRejectsCampusCardFailureEnvelope() {
        let data = Data(#"{"code":50000,"msg":"登录已过期","object":null}"#.utf8)
        XCTAssertThrowsError(try CampusCardResponseParser().balance(from: data))
    }
}
