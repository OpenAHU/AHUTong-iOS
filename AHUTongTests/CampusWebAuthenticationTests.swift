import Foundation
import XCTest
@testable import AHUTong

final class CampusWebAuthenticationTests: XCTestCase {
    func testCampusServiceDialogsOnlySurfaceFromTrustedMainFrame() {
        XCTAssertEqual(
            CampusWebDialogPolicy.message(
                " 请输入正确的图形验证码 ", scheme: "https", host: "adwmh.ahu.edu.cn",
                isMainFrame: true, scope: .campusCard
            ),
            "请输入正确的图形验证码"
        )
        XCTAssertNil(CampusWebDialogPolicy.message(
            "test-only", scheme: "http", host: "adwmh.ahu.edu.cn",
            isMainFrame: true, scope: .campusCard
        ))
        XCTAssertNil(CampusWebDialogPolicy.message(
            "test-only", scheme: "https", host: "example.com",
            isMainFrame: true, scope: .campusCard
        ))
        XCTAssertNil(CampusWebDialogPolicy.message(
            "test-only", scheme: "https", host: "adwmh.ahu.edu.cn",
            isMainFrame: false, scope: .campusCard
        ))
    }

    func testCampusCardAutomaticLoginRequiresPreviouslySavedCampusCookie() throws {
        let academicOnly = [CampusCookie(
            name: "SESSION", value: "test-only", domain: "jw.ahu.edu.cn",
            path: "/", secure: true, httpOnly: true
        )]
        let cardCookie = CampusCookie(
            name: "JSESSIONID", value: "test-only", domain: ".adwmh.ahu.edu.cn",
            path: "/", secure: true, httpOnly: true
        )
        let academicJSON = String(decoding: try JSONEncoder().encode(academicOnly), as: UTF8.self)
        let authorizedJSON = String(decoding: try JSONEncoder().encode(academicOnly + [cardCookie]), as: UTF8.self)

        XCTAssertFalse(CampusCardAuthorizationPolicy.hasPriorLogin(cookiesJSON: academicJSON))
        XCTAssertTrue(CampusCardAuthorizationPolicy.hasPriorLogin(cookiesJSON: authorizedJSON))
    }

    func testCredentialCaptureOnlyAcceptsMainFrameOnSchoolCASPage() {
        XCTAssertTrue(CampusCredentialCapturePolicy.isTrusted(
            scheme: "https", host: "one.ahu.edu.cn", path: "/cas/login", isMainFrame: true
        ))
        XCTAssertFalse(CampusCredentialCapturePolicy.isTrusted(
            scheme: "https", host: "one.ahu.edu.cn", path: "/other", isMainFrame: true
        ))
        XCTAssertFalse(CampusCredentialCapturePolicy.isTrusted(
            scheme: "https", host: "example.com", path: "/cas/login", isMainFrame: true
        ))
        XCTAssertFalse(CampusCredentialCapturePolicy.isTrusted(
            scheme: "https", host: "one.ahu.edu.cn", path: "/cas/login", isMainFrame: false
        ))
    }

    @MainActor
    func testSuccessfulNavigationWaitsForSubmittedCredentials() async {
        let collector = SubmittedCredentialsCollector()
        let expected = LoginCredentials(studentID: "AB220001", password: "test-only")
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(20))
            collector.capture(expected)
        }

        let captured = await collector.wait(timeout: .seconds(1))

        XCTAssertEqual(captured, expected)
    }

    func testNavigationPolicyAllowsOnlyExpectedHTTPSHosts() throws {
        XCTAssertTrue(CampusWebNavigationPolicy.isAllowed(
            try XCTUnwrap(URL(string: "https://one.ahu.edu.cn/cas/login")),
            scope: .academic
        ))
        XCTAssertTrue(CampusWebNavigationPolicy.isAllowed(
            try XCTUnwrap(URL(string: "https://jw.ahu.edu.cn/student/home")),
            scope: .academic
        ))
        XCTAssertFalse(CampusWebNavigationPolicy.isAllowed(
            try XCTUnwrap(URL(string: "http://one.ahu.edu.cn/cas/login")),
            scope: .academic
        ))
        XCTAssertFalse(CampusWebNavigationPolicy.isAllowed(
            try XCTUnwrap(URL(string: "https://example.com/cas/login")),
            scope: .academic
        ))
        XCTAssertTrue(CampusWebNavigationPolicy.isAllowed(
            try XCTUnwrap(URL(string: "https://adwmh.ahu.edu.cn/index/tologin")),
            scope: .campusCard
        ))
    }

    func testSuccessRoutesAreExactSchoolDestinations() throws {
        XCTAssertTrue(CampusWebNavigationPolicy.isSuccess(
            try XCTUnwrap(URL(string: "https://jw.ahu.edu.cn/student/home")),
            scope: .academic
        ))
        XCTAssertFalse(CampusWebNavigationPolicy.isSuccess(
            try XCTUnwrap(URL(string: "https://adwmh.ahu.edu.cn/index/user/success")),
            scope: .campusCard
        ))
        XCTAssertFalse(CampusWebNavigationPolicy.isSuccess(
            try XCTUnwrap(URL(string: "https://jw.ahu.edu.cn/student/sso/login")),
            scope: .academic
        ))
    }

    func testCookiePolicyRejectsExternalCookiesAndPromotesSchoolCookiesToSecure() throws {
        let allowed = try XCTUnwrap(HTTPCookie(properties: [
            .name: "SESSION",
            .value: "test-only",
            .domain: "jw.ahu.edu.cn",
            .path: "/",
            .secure: "TRUE"
        ]))
        let external = try XCTUnwrap(HTTPCookie(properties: [
            .name: "TRACK",
            .value: "test-only",
            .domain: "example.com",
            .path: "/",
            .secure: "TRUE"
        ]))
        let insecure = try XCTUnwrap(HTTPCookie(properties: [
            .name: "PLAIN",
            .value: "test-only",
            .domain: "jw.ahu.edu.cn",
            .path: "/"
        ]))

        let cookies = CampusWebCookiePolicy.cookies(
            from: [allowed, external, insecure],
            scope: .academic
        )

        XCTAssertEqual(cookies.map(\.name), ["SESSION", "PLAIN"])
        XCTAssertTrue(cookies.allSatisfy { $0.secure == true })
    }

    func testCookieMergerReplacesOnlySameIdentity() {
        let existing = [
            CampusCookie(name: "SESSION", value: "old", domain: "jw.ahu.edu.cn", path: "/", secure: true, httpOnly: true),
            CampusCookie(name: "CARD", value: "keep", domain: "adwmh.ahu.edu.cn", path: "/", secure: true, httpOnly: true)
        ]
        let incoming = [
            CampusCookie(name: "SESSION", value: "new", domain: ".jw.ahu.edu.cn", path: "/", secure: true, httpOnly: true)
        ]

        let merged = CampusCookieMerger.merge(existing: existing, incoming: incoming)

        XCTAssertEqual(merged.first { $0.name == "SESSION" }?.value, "new")
        XCTAssertEqual(merged.first { $0.name == "CARD" }?.value, "keep")
    }
}
