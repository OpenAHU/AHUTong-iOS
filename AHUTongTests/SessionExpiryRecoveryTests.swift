import Foundation
import XCTest
@testable import AHUTong

final class SessionExpiryRecoveryTests: XCTestCase {
    @MainActor
    func testColdStartKeepsSavedIdentityForTemporaryRenewalFailures() async throws {
        for failure in [CampusWebAuthenticationError.inactive, .timedOut, .interactionRequired, .credentialsUnavailable] {
            RecoveryURLProtocol.state.reset(alwaysExpired: true, expiresValidation: true)
            let secure = InMemorySecureStore()
            let store = CampusSessionStore(secureStore: secure)
            let credentials = CredentialStore(secureStore: secure)
            let snapshot = Self.snapshot
            try await store.save(snapshot)
            try await credentials.save(Self.credentials)
            let session = makeSession()
            defer { session.invalidateAndCancel() }
            let api = RustCampusCoreAPI(
                session: session, sessionStore: store, credentialStore: credentials,
                refreshCoordinator: SessionRefreshCoordinator(),
                authenticate: { _, _ in throw failure }
            )
            let defaults = UserDefaults(suiteName: UUID().uuidString)!
            let model = AppModel(campusAPI: api, sessionStore: store, credentialStore: credentials, defaults: defaults)

            await model.restore()

            XCTAssertEqual(model.sessionState, .authenticated(snapshot.user), "\(failure)")
            let saved = try await store.load()
            let savedCredentials = try await credentials.credentials(for: snapshot.user.studentID)
            XCTAssertEqual(saved, snapshot)
            XCTAssertEqual(savedCredentials, Self.credentials)
        }
    }

    func testExamReadRenewsExpiredSessionAndDecodesProductionContract() async throws {
        RecoveryURLProtocol.state.reset()
        let (api, store, credentials, session) = try await makeAPI()
        defer { session.invalidateAndCancel() }

        let exams = try await api.exams()

        XCTAssertEqual(exams.first?.course, "操作系统")
        XCTAssertEqual(exams.first?.seatNumber, "18")
        XCTAssertEqual(RecoveryURLProtocol.state.count("/exam"), 2)
        let saved = try await store.load()
        XCTAssertEqual(saved?.cookiesJSON, Self.renewedCookies)
        let savedCredentials = try await credentials.credentials(for: Self.credentials.studentID)
        XCTAssertEqual(savedCredentials, Self.credentials)
    }

    func testGradeReadRenewsExpiredSessionAndDecodesProductionContract() async throws {
        RecoveryURLProtocol.state.reset()
        let (api, _, _, session) = try await makeAPI()
        defer { session.invalidateAndCancel() }

        let report = try await api.grades()

        XCTAssertEqual(report.grades.first?.courseName, "高等数学")
        XCTAssertEqual(report.grades.first?.score, "92")
        XCTAssertEqual(report.gradePointAverage, 3.92)
        XCTAssertEqual(RecoveryURLProtocol.state.count("/grade"), 2)
    }

    func testSecondExpiredResponseDoesNotEraseCredentialsOrLoop() async throws {
        RecoveryURLProtocol.state.reset(alwaysExpired: true)
        let (api, store, credentials, session) = try await makeAPI()
        defer { session.invalidateAndCancel() }

        do {
            _ = try await api.exams()
            XCTFail("Expected a recoverable session failure")
        } catch {
            XCTAssertEqual(error as? CampusCoreError, .sessionRefreshDeferred)
        }

        let saved = try await store.load()
        let savedCredentials = try await credentials.credentials(for: Self.credentials.studentID)
        XCTAssertNotNil(saved)
        XCTAssertEqual(savedCredentials, Self.credentials)
        XCTAssertEqual(RecoveryURLProtocol.state.count("/exam"), 2)
    }

    func testExplicitPasswordRejectionStillClearsInvalidCredentials() async throws {
        RecoveryURLProtocol.state.reset()
        let secure = InMemorySecureStore()
        let store = CampusSessionStore(secureStore: secure)
        let credentials = CredentialStore(secureStore: secure)
        try await store.save(Self.snapshot)
        try await credentials.save(Self.credentials)
        let session = makeSession()
        defer { session.invalidateAndCancel() }
        let api = RustCampusCoreAPI(
            session: session, sessionStore: store, credentialStore: credentials,
            refreshCoordinator: SessionRefreshCoordinator(),
            authenticate: { _, _ in throw CampusWebAuthenticationError.credentialsRejected }
        )

        do {
            _ = try await api.exams()
            XCTFail("Expected credential rejection")
        } catch {
            XCTAssertEqual(error as? CampusCoreError, .credentialsRejected)
        }
        let saved = try await store.load()
        let savedCredentials = try await credentials.credentials(for: Self.credentials.studentID)
        XCTAssertNil(saved)
        XCTAssertNil(savedCredentials)
    }

    func testCaptchaAndServerBannersAreNotPasswordRejections() {
        for message in ["验证码错误", "账户已锁定，请稍后重试", "系统繁忙", "请完成设备验证", "", "用户 AB220001 登录失败"] {
            XCTAssertEqual(AcademicLoginFailurePolicy.error(for: message), .interactionRequired)
        }
        XCTAssertEqual(AcademicLoginFailurePolicy.error(for: "用户名或密码错误"), .credentialsRejected)
        XCTAssertEqual(AcademicLoginFailurePolicy.error(for: "Invalid username or password"), .credentialsRejected)
    }

    private func makeAPI() async throws -> (RustCampusCoreAPI, CampusSessionStore, CredentialStore, URLSession) {
        let secure = InMemorySecureStore()
        let store = CampusSessionStore(secureStore: secure)
        let credentials = CredentialStore(secureStore: secure)
        try await store.save(Self.snapshot)
        try await credentials.save(Self.credentials)
        let session = makeSession()
        let api = RustCampusCoreAPI(
            session: session, sessionStore: store, credentialStore: credentials,
            refreshCoordinator: SessionRefreshCoordinator(),
            authenticate: { _, credentials in
                CampusWebAuthenticationResult(credentials: credentials, cookies: [
                    CampusCookie(name: "SESSION", value: "renewed-test-only", domain: "jw.ahu.edu.cn", path: "/", secure: true, httpOnly: true)
                ])
            }
        )
        return (api, store, credentials, session)
    }

    private func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [RecoveryURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    private static let credentials = LoginCredentials(studentID: "AB220001", password: "test-only")
    private static let snapshot = CampusSessionSnapshot(
        user: User(name: "测试同学", studentID: "AB220001"), cookiesJSON: "[]"
    )
    static let renewedCookies = #"[{"name":"SESSION","value":"renewed-test-only","domain":"jw.ahu.edu.cn","path":"/","secure":true,"http_only":true}]"#
}

private final class RecoveryURLProtocol: URLProtocol, @unchecked Sendable {
    static let state = RecoveryResponseState()
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard let url = request.url else { return }
        let (status, body) = Self.state.response(for: url.path)
        let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

private final class RecoveryResponseState: @unchecked Sendable {
    private let lock = NSLock()
    private var counts: [String: Int] = [:]
    private var alwaysExpired = false
    private var expiresValidation = false
    func reset(alwaysExpired: Bool = false, expiresValidation: Bool = false) {
        lock.withLock {
            counts = [:]
            self.alwaysExpired = alwaysExpired
            self.expiresValidation = expiresValidation
        }
    }
    func count(_ path: String) -> Int { lock.withLock { counts[path, default: 0] } }
    func response(for path: String) -> (Int, String) {
        lock.withLock {
            counts[path, default: 0] += 1
            if ["/exam", "/grade"].contains(path), alwaysExpired || counts[path] == 1 {
                return (401, #"{"error":"campus_session_expired"}"#)
            }
            if path == "/schedule/current-week" {
                return expiresValidation
                    ? (401, #"{"error":"campus_session_expired"}"#) : (200, "6")
            }
            switch path {
            case "/cookies/flat": return (200, SessionExpiryRecoveryTests.renewedCookies)
            case "/exam": return (200, #"[{"course":"操作系统","time":"2026-10-20 09:00~11:00","seatNum":"18","location":"博学南楼-A210","finished":false}]"#)
            case "/grade": return (200, #"{"gpa":3.92,"items":[{"courseName":"高等数学","courseCode":"MATH1001","credit":"5","grade":"92","gradePoint":"4.2"}]}"#)
            default: return (200, "{}")
            }
        }
    }
}
