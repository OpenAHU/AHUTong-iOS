import Foundation
import XCTest
@testable import AHUTong

final class RustCampusServiceErrorMapperTests: XCTestCase {
    func testKnownPublicErrorCodeMapsToLocalizedMessage() {
        let data = Data(#"{"error":"campus_service_error"}"#.utf8)

        XCTAssertEqual(
            RustCampusServiceErrorMapper.message(from: data),
            "校园服务暂不可用，请稍后重试"
        )

        let unavailable = Data(
            #"{"error":"campus_service_unavailable"}"#.utf8
        )
        XCTAssertEqual(
            RustCampusServiceErrorMapper.message(from: unavailable),
            "学校服务当前不可用，请稍后重试"
        )
    }

    func testArbitraryUpstreamErrorIsNeverTrustedAsUserFacingText() throws {
        let secret =
            "https://ycard.ahu.edu.cn/redirect?ticket=ST-secret&synjones-auth=token-secret"
        let data = try JSONSerialization.data(
            withJSONObject: ["error": secret]
        )

        let message = RustCampusServiceErrorMapper.message(from: data)

        XCTAssertNil(message)
        XCTAssertFalse((message ?? "").contains("ST-secret"))
        XCTAssertFalse((message ?? "").contains("token-secret"))
    }

    func testMalformedErrorBodyIsIgnored() {
        XCTAssertNil(
            RustCampusServiceErrorMapper.message(from: Data("not-json".utf8))
        )
    }

    func testTypedAuthenticationCodesRemainDistinct() {
        XCTAssertEqual(
            RustCampusServiceErrorMapper.code(
                from: Data(#"{"error":"campus_session_expired"}"#.utf8)
            ),
            "campus_session_expired"
        )
        XCTAssertEqual(
            RustCampusServiceErrorMapper.code(
                from: Data(#"{"error":"campus_login_rejected"}"#.utf8)
            ),
            "campus_login_rejected"
        )
        XCTAssertNotEqual(
            RustCampusServiceErrorMapper.code(
                from: Data(#"{"error":"campus_service_error"}"#.utf8)
            ),
            "campus_session_expired"
        )
    }
}
