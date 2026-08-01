import Foundation
import XCTest
@testable import AHUTong

final class CampusAuthenticatedClientTests: XCTestCase {
    override func tearDown() {
        CampusTestURLProtocol.handler = nil
        super.tearDown()
    }

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
        XCTAssertTrue(cookie.matches(try XCTUnwrap(URL(string: "https://jw.ahu.edu.cn/student"))))
        XCTAssertFalse(cookie.matches(try XCTUnwrap(URL(string: "https://jw.ahu.edu.cn/student-records"))))
        XCTAssertFalse(cookie.matches(try XCTUnwrap(URL(string: "https://jw.ahu.edu.cn/teacher/home"))))
    }

    func testEmptyAndRelativePathsUseRootIdentityWhenDeletingCookies() throws {
        var cookies = [
            CampusCookie(
                name: "EMPTY_PATH",
                value: "old",
                domain: "jw.ahu.edu.cn",
                path: "",
                secure: true,
                httpOnly: true
            ),
            CampusCookie(
                name: "RELATIVE_PATH",
                value: "old",
                domain: "jw.ahu.edu.cn",
                path: "student",
                secure: true,
                httpOnly: true
            )
        ]
        let deletions = try ["EMPTY_PATH", "RELATIVE_PATH"].map { name in
            try XCTUnwrap(HTTPCookie(properties: [
                .name: name,
                .value: "",
                .domain: "jw.ahu.edu.cn",
                .path: "/",
                .secure: "TRUE"
            ]))
        }

        CampusCookieResponsePolicy.merge(deletions, into: &cookies)

        XCTAssertTrue(cookies.isEmpty)
        XCTAssertEqual(CampusCookie.normalizedPath(""), "/")
        XCTAssertEqual(CampusCookie.normalizedPath("student"), "/")
        XCTAssertEqual(CampusCookie.normalizedPath("/student"), "/student")
    }

    func testBlockingRedirectReturnsResponseAndSendsMatchingCookieAndHeaders() async throws {
        let api = CampusAuthenticatedClientAPIStub(
            cookies: #"[{"name":"SESSION","value":"test-only","domain":".ahu.edu.cn","path":"/","secure":true}]"#
        )
        let session = Self.makeSession()
        let client = CampusAuthenticatedClient(campusAPI: api, session: session)
        let capturedRequest = CampusTestLockedBox<URLRequest?>(nil)
        CampusTestURLProtocol.handler = { request in
            capturedRequest.set(request)
            return (
                HTTPURLResponse(
                    url: request.url!,
                    statusCode: 302,
                    httpVersion: nil,
                    headerFields: ["Location": "https://pay.ahu.edu.cn/checkout"]
                )!,
                Data()
            )
        }

        let response = try await client.response(
            url: try XCTUnwrap(URL(string: "https://ycard.ahu.edu.cn/recharge")),
            headers: ["X-Test-Header": "parity"],
            followsRedirects: false,
            refreshesSessionOnUnauthorized: false
        )

        XCTAssertEqual(response.statusCode, 302)
        XCTAssertEqual(response.header("location"), "https://pay.ahu.edu.cn/checkout")
        let request = capturedRequest.value
        XCTAssertEqual(request?.value(forHTTPHeaderField: "Cookie"), "SESSION=test-only")
        XCTAssertEqual(request?.value(forHTTPHeaderField: "X-Test-Header"), "parity")
        let refreshCount = await api.refreshCount()
        XCTAssertEqual(refreshCount, 0)
    }

    func testUnauthorizedRefreshesExactlyOnceThenRetries() async throws {
        let api = CampusAuthenticatedClientAPIStub(cookies: "[]")
        let session = Self.makeSession()
        let client = CampusAuthenticatedClient(campusAPI: api, session: session)
        let requestCount = CampusTestLockedBox(0)
        CampusTestURLProtocol.handler = { request in
            let count = requestCount.withValue {
                $0 += 1
                return $0
            }
            let status = count == 1 ? 401 : 200
            return (
                HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!,
                Data("ok".utf8)
            )
        }

        let data = try await client.data(
            url: try XCTUnwrap(URL(string: "https://jw.ahu.edu.cn/student/home"))
        )

        XCTAssertEqual(String(decoding: data, as: UTF8.self), "ok")
        XCTAssertEqual(requestCount.value, 2)
        let refreshCount = await api.refreshCount()
        XCTAssertEqual(refreshCount, 1)
    }

    func testConcurrentUnauthorizedRequestsShareOneRefresh() async throws {
        let api = CampusAuthenticatedClientAPIStub(
            cookies: "[]",
            refreshDelay: .milliseconds(75)
        )
        let client = CampusAuthenticatedClient(
            campusAPI: api,
            session: Self.makeSession(),
            refreshCoordinator: SessionRefreshCoordinator()
        )
        let requestCount = CampusTestLockedBox(0)
        CampusTestURLProtocol.handler = { request in
            let count = requestCount.withValue {
                $0 += 1
                return $0
            }
            return (
                HTTPURLResponse(
                    url: request.url!,
                    statusCode: count <= 2 ? 401 : 200,
                    httpVersion: nil,
                    headerFields: nil
                )!,
                Data("ok".utf8)
            )
        }
        let url = try XCTUnwrap(URL(string: "https://jw.ahu.edu.cn/student/home"))

        async let first = client.data(url: url)
        async let second = client.data(url: url)
        let results = try await [first, second]

        XCTAssertEqual(results.map { String(decoding: $0, as: UTF8.self) }, ["ok", "ok"])
        XCTAssertEqual(requestCount.value, 4)
        let refreshCount = await api.refreshCount()
        XCTAssertEqual(refreshCount, 1)
    }

    func testLoginHTMLAndStudentSSOFinalURLRefreshAndRetry() async throws {
        for mode in ["html", "final-url"] {
            let api = CampusAuthenticatedClientAPIStub(cookies: "[]")
            let client = CampusAuthenticatedClient(
                campusAPI: api,
                session: Self.makeSession(),
                refreshCoordinator: SessionRefreshCoordinator()
            )
            let requestCount = CampusTestLockedBox(0)
            CampusTestURLProtocol.handler = { request in
                let count = requestCount.withValue {
                    $0 += 1
                    return $0
                }
                if count == 1, mode == "html" {
                    return (
                        HTTPURLResponse(
                            url: request.url!,
                            statusCode: 200,
                            httpVersion: nil,
                            headerFields: ["Content-Type": "text/html; charset=utf-8"]
                        )!,
                        Data(#"<html><form id="loginForm"><input name="username"><input name="password"></form></html>"#.utf8)
                    )
                }
                let responseURL = count == 1
                    ? URL(string: "https://jw.ahu.edu.cn/student/sso/login")!
                    : request.url!
                return (
                    HTTPURLResponse(
                        url: responseURL,
                        statusCode: 200,
                        httpVersion: nil,
                        headerFields: ["Content-Type": "application/json"]
                    )!,
                    Data("ok".utf8)
                )
            }

            let result = try await client.data(
                url: try XCTUnwrap(URL(string: "https://jw.ahu.edu.cn/student/home"))
            )

            XCTAssertEqual(String(decoding: result, as: UTF8.self), "ok")
            XCTAssertEqual(requestCount.value, 2)
            let refreshCount = await api.refreshCount()
            XCTAssertEqual(refreshCount, 1)
        }
    }

    func testRepeatedUnauthorizedRetriesGetOnlyOnceThenInvalidates() async throws {
        let api = CampusAuthenticatedClientAPIStub(cookies: "[]")
        let client = CampusAuthenticatedClient(
            campusAPI: api,
            session: Self.makeSession(),
            refreshCoordinator: SessionRefreshCoordinator()
        )
        let requestCount = CampusTestLockedBox(0)
        CampusTestURLProtocol.handler = { request in
            requestCount.withValue { $0 += 1 }
            return (
                HTTPURLResponse(url: request.url!, statusCode: 401, httpVersion: nil, headerFields: nil)!,
                Data()
            )
        }

        do {
            _ = try await client.data(
                url: try XCTUnwrap(URL(string: "https://jw.ahu.edu.cn/student/home"))
            )
            XCTFail("Expected unauthorized")
        } catch {
            XCTAssertEqual(error as? CampusWebError, .unauthorized)
        }

        XCTAssertEqual(requestCount.value, 2)
        let refreshCount = await api.refreshCount()
        let invalidationCount = await api.invalidationCount()
        XCTAssertEqual(refreshCount, 1)
        XCTAssertEqual(invalidationCount, 1)
    }

    func testPaymentPostRefreshesFutureSessionButIsNeverRepeated() async throws {
        let api = CampusAuthenticatedClientAPIStub(cookies: "[]")
        let client = CampusAuthenticatedClient(
            campusAPI: api,
            session: Self.makeSession(),
            refreshCoordinator: SessionRefreshCoordinator()
        )
        let requestCount = CampusTestLockedBox(0)
        CampusTestURLProtocol.handler = { request in
            requestCount.withValue { $0 += 1 }
            return (
                HTTPURLResponse(url: request.url!, statusCode: 401, httpVersion: nil, headerFields: nil)!,
                Data()
            )
        }

        do {
            _ = try await client.data(
                url: try XCTUnwrap(URL(string: "https://ycard.ahu.edu.cn/blade-pay/pay")),
                method: "POST",
                body: Data("fixture-only".utf8),
                contentType: "application/x-www-form-urlencoded"
            )
            XCTFail("Expected unauthorized")
        } catch {
            XCTAssertEqual(error as? CampusWebError, .unauthorized)
        }

        XCTAssertEqual(requestCount.value, 1)
        let refreshCount = await api.refreshCount()
        let invalidationCount = await api.invalidationCount()
        XCTAssertEqual(refreshCount, 1)
        XCTAssertEqual(invalidationCount, 0)
    }

    func testFiveHundredNeverRefreshesOrInvalidatesSession() async throws {
        let api = CampusAuthenticatedClientAPIStub(cookies: "[]")
        let client = CampusAuthenticatedClient(
            campusAPI: api,
            session: Self.makeSession(),
            refreshCoordinator: SessionRefreshCoordinator()
        )
        CampusTestURLProtocol.handler = { request in
            (
                HTTPURLResponse(url: request.url!, statusCode: 500, httpVersion: nil, headerFields: nil)!,
                Data("upstream changed".utf8)
            )
        }

        do {
            _ = try await client.data(
                url: try XCTUnwrap(URL(string: "https://jw.ahu.edu.cn/student/home"))
            )
            XCTFail("Expected server error")
        } catch {
            guard let webError = error as? CampusWebError,
                  case .server = webError else {
                return XCTFail("Expected finite server error")
            }
        }

        let refreshCount = await api.refreshCount()
        let invalidationCount = await api.invalidationCount()
        XCTAssertEqual(refreshCount, 0)
        XCTAssertEqual(invalidationCount, 0)
    }

    func testSetCookieIsMergedIntoRustSessionAndPersisted() async throws {
        let api = CampusAuthenticatedClientAPIStub(
            cookies: #"[{"name":"OLD","value":"keep","domain":"jw.ahu.edu.cn","path":"/","secure":true}]"#
        )
        let session = Self.makeSession()
        let client = CampusAuthenticatedClient(campusAPI: api, session: session)
        CampusTestURLProtocol.handler = { request in
            (
                HTTPURLResponse(
                    url: request.url!,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: ["Set-Cookie": "NEW=fresh; Path=/; Secure; HttpOnly"]
                )!,
                Data("ok".utf8)
            )
        }

        _ = try await client.data(
            url: try XCTUnwrap(URL(string: "https://jw.ahu.edu.cn/student/home"))
        )
        let initializedValue = await api.lastInitializedCookies()
        let initialized = try XCTUnwrap(initializedValue)
        let cookies = try JSONDecoder().decode([CampusCookie].self, from: Data(initialized.utf8))
        let persistCount = await api.persistCount()

        XCTAssertEqual(Set(cookies.map(\.name)), Set(["OLD", "NEW"]))
        XCTAssertEqual(cookies.first(where: { $0.name == "NEW" })?.value, "fresh")
        XCTAssertEqual(persistCount, 1)
    }

    func testExpiredAndEmptySetCookieDeleteMatchingCookieWithoutAppending() async throws {
        let api = CampusAuthenticatedClientAPIStub(
            cookies: """
            [
              {"name":"EMPTY","value":"old","domain":"jw.ahu.edu.cn","path":"/","secure":true},
              {"name":"EXPIRED","value":"old","domain":"jw.ahu.edu.cn","path":"/","secure":true}
            ]
            """
        )
        let client = CampusAuthenticatedClient(
            campusAPI: api,
            session: Self.makeSession()
        )
        let requestCount = CampusTestLockedBox(0)
        CampusTestURLProtocol.handler = { request in
            let count = requestCount.withValue {
                $0 += 1
                return $0
            }
            let setCookie = count == 1
                ? "EMPTY=; Path=/; Max-Age=0; Secure"
                : "EXPIRED=ignored; Path=/; "
                    + "Expires=Thu, 01 Jan 1970 00:00:00 GMT; Secure"
            return (
                HTTPURLResponse(
                    url: request.url!,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: ["Set-Cookie": setCookie]
                )!,
                Data("ok".utf8)
            )
        }

        let url = try XCTUnwrap(URL(
            string: "https://jw.ahu.edu.cn/student/home"
        ))
        _ = try await client.data(url: url)
        _ = try await client.data(url: url)

        let initializedValue = await api.lastInitializedCookies()
        let initialized = try XCTUnwrap(initializedValue)
        let cookies = try JSONDecoder().decode(
            [CampusCookie].self,
            from: Data(initialized.utf8)
        )
        XCTAssertTrue(cookies.isEmpty)
        XCTAssertFalse(cookies.contains(where: { $0.value.isEmpty }))
    }

    func testLoginRedirectIsUnauthorizedWhenRefreshIsDisabled() async throws {
        let api = CampusAuthenticatedClientAPIStub(cookies: "[]")
        let session = Self.makeSession()
        let client = CampusAuthenticatedClient(campusAPI: api, session: session)
        CampusTestURLProtocol.handler = { request in
            (
                HTTPURLResponse(
                    url: request.url!,
                    statusCode: 302,
                    httpVersion: nil,
                    headerFields: ["Location": "https://one.ahu.edu.cn/cas/login"]
                )!,
                Data()
            )
        }

        do {
            _ = try await client.response(
                url: try XCTUnwrap(URL(string: "https://jw.ahu.edu.cn/student/home")),
                followsRedirects: false,
                refreshesSessionOnUnauthorized: false
            )
            XCTFail("Expected unauthorized")
        } catch {
            XCTAssertEqual(error as? CampusWebError, .unauthorized)
        }
        let refreshCount = await api.refreshCount()
        XCTAssertEqual(refreshCount, 0)
    }

    func testClearingEvaluationCookiesPreservesSharedRootSession() async throws {
        let api = CampusAuthenticatedClientAPIStub(
            cookies: """
            [
              {"name":"EVAL","value":"old","domain":"jw.ahu.edu.cn","path":"/eams5-evaluation-service","secure":true},
              {"name":"ROOT","value":"old","domain":".ahu.edu.cn","path":"/","secure":true},
              {"name":"LOST","value":"keep","domain":"adwmh.ahu.edu.cn","path":"/","secure":true}
            ]
            """
        )
        let client = CampusAuthenticatedClient(campusAPI: api, session: Self.makeSession())
        let url = try XCTUnwrap(URL(string: "https://jw.ahu.edu.cn/eams5-evaluation-service/"))

        let removed = try await client.clearCookies(scopedTo: url)
        let initializedValue = await api.lastInitializedCookies()
        let initialized = try XCTUnwrap(initializedValue)
        let cookies = try JSONDecoder().decode([CampusCookie].self, from: Data(initialized.utf8))
        let persistCount = await api.persistCount()

        XCTAssertEqual(removed, 1)
        XCTAssertEqual(cookies.map(\.name), ["ROOT", "LOST"])
        XCTAssertEqual(persistCount, 1)
    }

    private static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [CampusTestURLProtocol.self]
        return URLSession(configuration: configuration)
    }
}

private final class CampusTestURLProtocol: URLProtocol, @unchecked Sendable {
    typealias Handler = @Sendable (URLRequest) throws -> (HTTPURLResponse, Data)
    private static let registry = CampusTestURLProtocolRegistry()

    static var handler: Handler? {
        get { registry.handler }
        set { registry.handler = newValue }
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        do {
            guard let handler = Self.handler else {
                throw CampusTestURLProtocolError.missingHandler
            }
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

private enum CampusTestURLProtocolError: Error {
    case missingHandler
}

private final class CampusTestURLProtocolRegistry: @unchecked Sendable {
    private let lock = NSLock()
    private var storedHandler: CampusTestURLProtocol.Handler?

    var handler: CampusTestURLProtocol.Handler? {
        get {
            lock.lock()
            defer { lock.unlock() }
            return storedHandler
        }
        set {
            lock.lock()
            storedHandler = newValue
            lock.unlock()
        }
    }
}

private final class CampusTestLockedBox<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var storedValue: Value

    init(_ value: Value) {
        storedValue = value
    }

    var value: Value {
        lock.lock()
        defer { lock.unlock() }
        return storedValue
    }

    func set(_ value: Value) {
        lock.lock()
        storedValue = value
        lock.unlock()
    }

    func withValue<Result>(_ body: (inout Value) -> Result) -> Result {
        lock.lock()
        defer { lock.unlock() }
        return body(&storedValue)
    }
}

private actor CampusAuthenticatedClientAPIStub: CampusCoreAPI {
    private var cookies: String
    private var refreshes = 0
    private var persists = 0
    private var initializedCookies: String?
    private var invalidations = 0
    private let refreshDelay: Duration?

    init(cookies: String, refreshDelay: Duration? = nil) {
        self.cookies = cookies
        self.refreshDelay = refreshDelay
    }

    func initialize(cookiesJSON: String) {
        cookies = cookiesJSON
        initializedCookies = cookiesJSON
    }

    func login(studentID: String, password: String) throws -> User {
        throw CampusCoreError.invalidResponse
    }

    func dumpCookies() -> String { cookies }
    func cookiesFlat() -> String { cookies }
    func schedule() throws -> [Course] { throw CampusCoreError.invalidResponse }
    func currentWeek() throws -> Int { throw CampusCoreError.invalidResponse }
    func exams() throws -> [CampusExam] { throw CampusCoreError.invalidResponse }
    func grades() throws -> CampusGradeReport { throw CampusCoreError.invalidResponse }
    func cardBalance() throws -> Double { throw CampusCoreError.invalidResponse }
    func cardQRCode() throws -> String { throw CampusCoreError.invalidResponse }

    func refreshSession() async {
        refreshes += 1
        if let refreshDelay {
            try? await Task.sleep(for: refreshDelay)
        }
    }

    func invalidateStoredSession() {
        invalidations += 1
    }

    func persistSessionCookies() {
        persists += 1
    }

    func refreshCount() -> Int { refreshes }
    func invalidationCount() -> Int { invalidations }
    func persistCount() -> Int { persists }
    func lastInitializedCookies() -> String? { initializedCookies }
}
