import XCTest
@testable import AHUTong

final class CampusAuthenticatedClientTests: XCTestCase {
    func testParentDomainCookieMatchesCampusSubdomain() throws {
        let cookie = CampusCookie(
            name: "SESSION",
            value: "test-only",
            domain: ".ahu.edu.cn",
            path: "/",
            secure: true,
            httpOnly: true
        )

        XCTAssertTrue(cookie.matches(try XCTUnwrap(URL(string: "https://adwmh.ahu.edu.cn/lostfound/all"))))
        XCTAssertTrue(cookie.matches(try XCTUnwrap(URL(string: "https://jw.ahu.edu.cn/student/for-std/course-table"))))
        XCTAssertFalse(cookie.matches(try XCTUnwrap(URL(string: "https://example.com/"))))
        XCTAssertFalse(cookie.matches(try XCTUnwrap(URL(string: "http://jw.ahu.edu.cn/"))))
    }

    func testCookiePathIsRespected() throws {
        let cookie = CampusCookie(
            name: "JSESSIONID",
            value: "test-only",
            domain: "jw.ahu.edu.cn",
            path: "/student",
            secure: nil,
            httpOnly: nil
        )

        XCTAssertTrue(cookie.matches(try XCTUnwrap(URL(string: "https://jw.ahu.edu.cn/student/home"))))
        XCTAssertFalse(cookie.matches(try XCTUnwrap(URL(string: "https://jw.ahu.edu.cn/teacher/home"))))
    }
}
