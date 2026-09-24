import Foundation
import XCTest
@testable import AHUTong

final class CampusCardLoginClientTests: XCTestCase {
    func testLoginUsesAndroidADWMHContractAndSameCaptchaSession() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [CampusCardLoginTestURLProtocol.self]
        let client = CampusCardLoginClient(session: URLSession(configuration: configuration))
        let original = CampusCookie(
            name: "JSESSIONID", value: "initial-test-only", domain: "adwmh.ahu.edu.cn",
            path: "/", secure: true, httpOnly: true
        )

        let cookies = try await client.login(
            credentials: LoginCredentials(studentID: "AB220001", password: "test-only"),
            captcha: "1234",
            cookies: [original]
        )

        let captured = try XCTUnwrap(CampusCardLoginTestURLProtocol.lastRequest.value)
        XCTAssertEqual(captured.url?.absoluteString, "https://adwmh.ahu.edu.cn/user/login")
        XCTAssertEqual(captured.httpMethod, "POST")
        XCTAssertEqual(captured.value(forHTTPHeaderField: "Cookie"), "JSESSIONID=initial-test-only")
        XCTAssertEqual(captured.value(forHTTPHeaderField: "X-Requested-With"), "XMLHttpRequest")
        let body = try XCTUnwrap(CampusCardLoginTestURLProtocol.lastBody.value)
        let fields = try XCTUnwrap(URLComponents(string: "?" + String(decoding: body, as: UTF8.self))?.queryItems)
        XCTAssertEqual(Dictionary(uniqueKeysWithValues: fields.map { ($0.name, $0.value ?? "") }), [
            "username": "AB220001", "pwd": "test-only", "flag": "0", "imgcode": "1234"
        ])
        XCTAssertEqual(cookies.first(where: { $0.name == "JSESSIONID" })?.value, "rotated-test-only")
    }

    func testMissingCaptchaSessionDoesNotSendLoginRequest() async {
        let client = CampusCardLoginClient()

        do {
            _ = try await client.login(
                credentials: LoginCredentials(studentID: "AB220001", password: "test-only"),
                captcha: "1234",
                cookies: []
            )
            XCTFail("Expected a missing school session")
        } catch {
            XCTAssertEqual(error as? CampusCardLoginError, .missingSchoolSession)
        }
    }

    func testParentDomainSchoolCookieCanCarryFirstCampusLogin() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [CampusCardLoginTestURLProtocol.self]
        let client = CampusCardLoginClient(session: URLSession(configuration: configuration))
        let cookie = CampusCookie(
            name: "SESSION", value: "first-test-only", domain: ".ahu.edu.cn",
            path: "/", secure: true, httpOnly: true
        )

        _ = try await client.login(
            credentials: LoginCredentials(studentID: "AB220001", password: "test-only"),
            captcha: "1234",
            cookies: [cookie]
        )

        let captured = try XCTUnwrap(CampusCardLoginTestURLProtocol.lastRequest.value)
        XCTAssertEqual(captured.value(forHTTPHeaderField: "Cookie"), "SESSION=first-test-only")
    }

    func testSchoolRejectionDoesNotProduceAuthenticatedCookies() async {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [CampusCardRejectedURLProtocol.self]
        let client = CampusCardLoginClient(session: URLSession(configuration: configuration))
        let cookie = CampusCookie(
            name: "JSESSIONID", value: "initial-test-only", domain: "adwmh.ahu.edu.cn",
            path: "/", secure: true, httpOnly: true
        )

        do {
            _ = try await client.login(
                credentials: LoginCredentials(studentID: "AB220001", password: "test-only"),
                captcha: "1234",
                cookies: [cookie]
            )
            XCTFail("Expected school rejection")
        } catch {
            XCTAssertEqual(error as? CampusCardLoginError, .rejected("用户名或密码错误"))
        }
    }
}

private final class CampusCardLoginLockedBox<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: Value?

    var value: Value? {
        lock.lock()
        defer { lock.unlock() }
        return stored
    }

    func set(_ value: Value) {
        lock.lock()
        stored = value
        lock.unlock()
    }
}

private final class CampusCardLoginTestURLProtocol: URLProtocol, @unchecked Sendable {
    static let lastRequest = CampusCardLoginLockedBox<URLRequest>()
    static let lastBody = CampusCardLoginLockedBox<Data>()

    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.host == "adwmh.ahu.edu.cn"
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lastRequest.set(request)
        Self.lastBody.set(Self.readBody(request))
        let response = HTTPURLResponse(
            url: request.url!, statusCode: 200, httpVersion: nil,
            headerFields: [
                "Content-Type": "application/json",
                "Set-Cookie": "JSESSIONID=rotated-test-only; Path=/; HttpOnly"
            ]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(#"{"code":10000,"msg":""}"#.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    private static func readBody(_ request: URLRequest) -> Data {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return Data() }
        stream.open()
        defer { stream.close() }
        var result = Data()
        var buffer = [UInt8](repeating: 0, count: 4_096)
        while true {
            let count = stream.read(&buffer, maxLength: buffer.count)
            if count <= 0 { return result }
            result.append(contentsOf: buffer[..<count])
        }
    }
}

private final class CampusCardRejectedURLProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.host == "adwmh.ahu.edu.cn"
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let response = HTTPURLResponse(
            url: request.url!, statusCode: 200, httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(#"{"code":10001,"msg":"用户名或密码错误"}"#.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
