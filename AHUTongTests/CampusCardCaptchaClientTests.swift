import Foundation
import XCTest
@testable import AHUTong

final class CampusCardCaptchaClientTests: XCTestCase {
    func testNativeCaptchaRequestCarriesOnlySchoolCookieAndMergesResponseCookie() async throws {
        let image = try await makeClient().fetch(cookies: [
            cookie(value: "test-only"),
            CampusCookie(
                name: "EXTERNAL", value: "test-only", domain: "example.com",
                path: "/", secure: true, httpOnly: true
            )
        ])

        XCTAssertEqual(image.data.prefix(3), Data([0xFF, 0xD8, 0xFF]))
        XCTAssertEqual(image.cookies.first { $0.name == "JSESSIONID" }?.value, "test-only")
        XCTAssertEqual(image.cookies.first { $0.name == "CAPTCHA" }?.value, "fixture-session")
        XCTAssertFalse(image.cookies.contains { $0.name == "EXTERNAL" })
    }

    func testFirstCampusLoginEstablishesSessionWithoutSavedCookie() async throws {
        let image = try await makeClient().fetch(cookies: [])

        XCTAssertEqual(image.cookies.first { $0.name == "JSESSIONID" }?.value, "first-session")
    }

    func testMissingSchoolSessionAfterCaptchaResponseFailsClosed() async {
        do {
            _ = try await makeClient(using: CampusCardNoSessionFixtureProtocol.self).fetch(cookies: [])
            XCTFail("Expected missing school session")
        } catch {
            XCTAssertEqual(error as? CampusCardCaptchaFetchError, .missingSchoolSession)
        }
    }

    func testRedirectIsRejectedWithoutFollowingExternalLocation() async {
        do {
            _ = try await makeClient().fetch(cookies: [cookie(value: "redirect-fixture")])
            XCTFail("Expected redirect rejection")
        } catch {
            XCTAssertEqual(error as? CampusCardCaptchaFetchError, .redirected)
        }
    }

    func testHTTPFailureReportsStatusWithoutResponseBody() async {
        do {
            _ = try await makeClient().fetch(cookies: [cookie(value: "status-fixture")])
            XCTFail("Expected HTTP failure")
        } catch {
            XCTAssertEqual(error as? CampusCardCaptchaFetchError, .status(503))
        }
    }

    func testHTMLBodyIsNotSentToOCR() async {
        do {
            _ = try await makeClient().fetch(cookies: [cookie(value: "html-fixture")])
            XCTFail("Expected invalid image")
        } catch {
            XCTAssertEqual(error as? CampusCardCaptchaFetchError, .invalidImage)
        }
    }

    private func cookie(value: String) -> CampusCookie {
        CampusCookie(
            name: "JSESSIONID", value: value, domain: "adwmh.ahu.edu.cn",
            path: "/", secure: true, httpOnly: true
        )
    }

    private func makeClient(using fixture: AnyClass = CampusCardCaptchaFixtureProtocol.self) -> CampusCardCaptchaClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [fixture]
        configuration.httpShouldSetCookies = false
        configuration.httpCookieAcceptPolicy = .never
        return CampusCardCaptchaClient(session: URLSession(
            configuration: configuration,
            delegate: CampusCardCaptchaTestRedirectBlocker(),
            delegateQueue: nil
        ))
    }
}

private class CampusCardCaptchaFixtureProtocol: URLProtocol, @unchecked Sendable {
    class var providesAnonymousSession: Bool { true }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url else { return }
        let cookieHeader = request.value(forHTTPHeaderField: "Cookie") ?? ""
        let isValidRequest = request.httpMethod == "GET"
            && url == CampusCardCaptchaClient.endpoint
            && !cookieHeader.contains("EXTERNAL=")
        let status: Int
        let data: Data
        var fields = ["Content-Type": "image/jpeg"]
        if !isValidRequest {
            status = 400
            data = Data()
        } else if cookieHeader.contains("redirect-fixture") {
            status = 302
            fields["Location"] = "https://example.com/should-not-open"
            data = Data()
        } else if cookieHeader.contains("status-fixture") {
            status = 503
            data = Data("school-error".utf8)
        } else if cookieHeader.contains("html-fixture") {
            status = 200
            data = Data("<html>login</html>".utf8)
        } else {
            status = 200
            if cookieHeader.isEmpty {
                if Self.providesAnonymousSession {
                    fields["Set-Cookie"] = "JSESSIONID=first-session; Path=/; Secure; HttpOnly"
                }
            } else {
                fields["Set-Cookie"] = "CAPTCHA=fixture-session; Path=/; Secure; HttpOnly"
            }
            data = Data([0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10, 0xFF, 0xD9])
        }
        let response = HTTPURLResponse(
            url: url, statusCode: status, httpVersion: nil, headerFields: fields
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

private final class CampusCardNoSessionFixtureProtocol: CampusCardCaptchaFixtureProtocol, @unchecked Sendable {
    override class var providesAnonymousSession: Bool { false }
}

private final class CampusCardCaptchaTestRedirectBlocker: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping @Sendable (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }
}
