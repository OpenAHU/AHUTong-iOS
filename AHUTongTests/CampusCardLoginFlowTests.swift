import XCTest
@testable import AHUTong

final class CampusCardLoginFlowTests: XCTestCase {
    override func tearDown() {
        LoginFlowURLProtocol.fixture = nil
        super.tearDown()
    }

    func testInvalidOCRFetchesFreshChallengeAndCarriesRotatedCookie() async throws {
        let fixture = LoginFlowFixture(ocr: [.failure(.invalidCode), .success("1234")])
        let cookies = try await fixture.flow.login(credentials: fixture.credentials, cookies: [])
        XCTAssertEqual(cookies.first?.value, "challenge-2")
        XCTAssertEqual(fixture.paths, ["/remind/authcode", "/remind/authcode", "/user/login"])
        XCTAssertEqual(fixture.cookieHeaders, ["", "JSESSIONID=challenge-1", "JSESSIONID=challenge-2"])
    }

    func testSchoolCaptchaRejectionFetchesAnotherImageBeforeResubmitting() async throws {
        let fixture = LoginFlowFixture(loginReplies: [#"{"code":10001,"msg":"验证码错误"}"#, #"{"code":10000}"#])
        _ = try await fixture.flow.login(credentials: fixture.credentials, cookies: [])
        XCTAssertEqual(fixture.paths, ["/remind/authcode", "/user/login", "/remind/authcode", "/user/login"])
        XCTAssertEqual(fixture.cookieHeaders.last, "JSESSIONID=challenge-2")
    }

    func testUnusableOCRStopsAfterFiveImagesWithoutSendingCredentials() async {
        let fixture = LoginFlowFixture(ocr: Array(repeating: .failure(.invalidCode), count: 5))
        do {
            _ = try await fixture.flow.login(credentials: fixture.credentials, cookies: [])
            XCTFail("Expected exhausted challenges")
        } catch { XCTAssertEqual(error as? CampusWebAuthenticationError, .campusCardOCRFailed(.invalidCode)) }
        XCTAssertEqual(fixture.paths, Array(repeating: "/remind/authcode", count: 5))
    }

    func testExplicitCredentialRejectionIsNeverRetriedEvenIfMessageMentionsCaptcha() async {
        let fixture = LoginFlowFixture(loginReplies: [#"{"code":10012,"msg":"密码错误，请重新输入验证码"}"#])
        do {
            _ = try await fixture.flow.login(credentials: fixture.credentials, cookies: [])
            XCTFail("Expected credential rejection")
        } catch { XCTAssertEqual(error as? CampusWebAuthenticationError, .campusCardSchoolRejected) }
        XCTAssertEqual(fixture.paths, ["/remind/authcode", "/user/login"])
    }
}

private final class LoginFlowFixture: @unchecked Sendable {
    let credentials = LoginCredentials(studentID: "TEST001", password: "fixture-only")
    private let lock = NSLock()
    private var requests: [URLRequest] = []
    private var replies: [String]
    private let recognizer: FixtureRecognizer
    private let session: URLSession
    var paths: [String] { lock.withLock { requests.map { $0.url!.path } } }
    var cookieHeaders: [String] { lock.withLock { requests.map { $0.value(forHTTPHeaderField: "Cookie") ?? "" } } }
    var flow: CampusCardLoginFlow { .init(captchaClient: .init(session: session), recognizer: recognizer, loginClient: .init(session: session)) }
    init(ocr: [Result<String, CampusCaptchaRecognitionError>] = [.success("1234"), .success("5678")], loginReplies: [String] = [#"{"code":10000}"#]) {
        replies = loginReplies; recognizer = FixtureRecognizer(values: ocr)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [LoginFlowURLProtocol.self]
        configuration.httpCookieStorage = nil; configuration.httpShouldSetCookies = false
        session = URLSession(configuration: configuration)
        LoginFlowURLProtocol.fixture = self
    }
    func reply(_ request: URLRequest) -> (Data, [String: String]) {
        lock.withLock {
            requests.append(request)
            if request.url?.path == "/remind/authcode" {
                let count = requests.filter { $0.url?.path == "/remind/authcode" }.count
                return (Data([0xFF, 0xD8, 0xFF, 0x01]), ["Set-Cookie": "JSESSIONID=challenge-\(count); Path=/; Secure"])
            }
            return (Data(replies.removeFirst().utf8), [:])
        }
    }
}

private actor FixtureRecognizer: CampusCaptchaRecognizing {
    var values: [Result<String, CampusCaptchaRecognitionError>]
    init(values: [Result<String, CampusCaptchaRecognitionError>]) { self.values = values }
    func recognize(_ image: Data) throws -> String { try values.removeFirst().get() }
}

private final class LoginFlowURLProtocol: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var value: LoginFlowFixture?
    static var fixture: LoginFlowFixture? {
        get { lock.withLock { value } }
        set { lock.withLock { value = newValue } }
    }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let (data, fields) = Self.fixture!.reply(request)
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: fields)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
