import Foundation
import XCTest
@testable import AHUTong

final class CampusCardQRCodeClientTests: XCTestCase {
    func testFirstPartyRequestUsesOnlyMatchingCookiesAndBoundedTimeout() async throws {
        let session = makeSession()
        defer { session.invalidateAndCancel() }
        QRTransportProtocol.state.reset()
        let cookies = [
            CampusCookie(name: "valid", value: "fixture", domain: ".ahu.edu.cn", path: "/", secure: true, httpOnly: true),
            CampusCookie(name: "foreign", value: "never-send", domain: "example.com", path: "/", secure: false, httpOnly: false),
            CampusCookie(name: "wrongpath", value: "never-send", domain: "adwmh.ahu.edu.cn", path: "/user", secure: true, httpOnly: false)
        ]
        let json = String(decoding: try JSONEncoder().encode(cookies), as: UTF8.self)
        let payload = try await CampusCardQRCodeClient(session: session).payload(cookiesJSON: json)
        XCTAssertEqual(payload, "FIXTURE-QR")
        let request = try XCTUnwrap(QRTransportProtocol.state.requests().first)
        XCTAssertEqual(request.url, CampusCardQRCodeClient.endpoint)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Cookie"), "valid=fixture")
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-Requested-With"), "XMLHttpRequest")
        XCTAssertEqual(request.timeoutInterval, 12)
        XCTAssertFalse(request.httpShouldHandleCookies)
    }

    func testBusinessExpiryInHTTP200IsRecoverable() async throws {
        let session = makeSession()
        defer { session.invalidateAndCancel() }
        QRTransportProtocol.state.reset(body: #"{"code":40001,"msg":"expired"}"#)
        do {
            _ = try await CampusCardQRCodeClient(session: session).payload(cookiesJSON: "[]")
            XCTFail("HTTP 200 does not prove the campus session is valid")
        } catch { XCTAssertEqual(error as? CampusCoreError, .unauthorized) }
    }

    func testLoginRedirectAndHTTPExpiryDoNotBecomePaymentPayloads() async throws {
        let session = makeSession()
        defer { session.invalidateAndCancel() }
        for status in [302, 401, 403] {
            QRTransportProtocol.state.reset(status: status)
            do {
                _ = try await CampusCardQRCodeClient(session: session).payload(cookiesJSON: "[]")
                XCTFail("Expected expired session")
            } catch { XCTAssertEqual(error as? CampusCoreError, .unauthorized) }
        }
    }

    func testEmptyPayloadIsRejected() async throws {
        let session = makeSession()
        defer { session.invalidateAndCancel() }
        QRTransportProtocol.state.reset(body: #"{"code":10000,"object":"   "}"#)
        do {
            _ = try await CampusCardQRCodeClient(session: session).payload(cookiesJSON: "[]")
            XCTFail("Whitespace is not a payment code")
        } catch { XCTAssertEqual(error as? CampusCoreError, .invalidResponse) }
    }

    func testSavedFirstPartySessionWorksWithoutAnyLoopbackRequest() async throws {
        let session = makeSession()
        defer { session.invalidateAndCancel() }
        QRTransportProtocol.state.reset()
        let store = CampusSessionStore(secureStore: InMemorySecureStore())
        try await store.save(CampusSessionSnapshot(user: User(name: "Fixture", studentID: "QR-FIXTURE"), cookiesJSON: "[]"))
        let api = RustCampusCoreAPI(qrClient: CampusCardQRCodeClient(session: session), session: session, sessionStore: store)
        let payload = try await api.cardQRCode()
        XCTAssertEqual(payload, "FIXTURE-QR")
        XCTAssertEqual(QRTransportProtocol.state.requests().map { $0.url?.host }, ["adwmh.ahu.edu.cn"])
    }

    func testRecoveryUsesFallbackAfterTransportFailure() async throws {
        let calls = QRRecoveryCalls()
        let payload = try await CampusCardQRRecovery.payload {
            await calls.record("direct")
            throw URLError(.cannotConnectToHost)
        } fallback: {
            await calls.record("rust")
            return "FALLBACK-QR"
        }
        XCTAssertEqual(payload, "FALLBACK-QR")
        let events = await calls.events
        XCTAssertEqual(events, ["direct", "rust"])
    }

    func testBothFailuresStillAllowOneFinalFirstPartyAttempt() async throws {
        let calls = QRRecoveryCalls()
        let payload = try await CampusCardQRRecovery.payload {
            let count = await calls.record("direct")
            if count == 1 { throw URLError(.timedOut) }
            return "RECOVERED-QR"
        } fallback: {
            await calls.record("rust")
            throw URLError(.cannotConnectToHost)
        }
        XCTAssertEqual(payload, "RECOVERED-QR")
        let events = await calls.events
        XCTAssertEqual(events, ["direct", "rust", "direct"])
    }

    func testExpiredSessionsRenewOnlyOnceBeforeFinalRead() async throws {
        let calls = QRRecoveryCalls()
        let payload = try await CampusCardQRRecovery.payload {
            let count = await calls.record("direct")
            if count == 1 { throw CampusCoreError.unauthorized }
            return "RENEWED-QR"
        } fallback: {
            await calls.record("rust")
            throw CampusCoreError.unauthorized
        } refresh: {
            await calls.record("refresh")
        }
        XCTAssertEqual(payload, "RENEWED-QR")
        let events = await calls.events
        XCTAssertEqual(events, ["direct", "rust", "refresh", "direct"])
    }

    func testCancellationNeverStartsAnotherTransport() async {
        let calls = QRRecoveryCalls()
        do {
            _ = try await CampusCardQRRecovery.payload {
                await calls.record("direct")
                throw CancellationError()
            } fallback: {
                await calls.record("rust")
                return "UNEXPECTED"
            }
            XCTFail("Cancellation must propagate")
        } catch { XCTAssertTrue(error is CancellationError) }
        let events = await calls.events
        XCTAssertEqual(events, ["direct"])
    }

    func testRenewedSessionCanUseFallbackWhenDirectReadStillFails() async throws {
        let calls = QRRecoveryCalls()
        let payload = try await CampusCardQRRecovery.payload {
            await calls.record("direct")
            throw CampusCoreError.unauthorized
        } fallback: {
            let events = await calls.events
            await calls.record("rust")
            if events.contains("refresh") { return "RENEWED-FALLBACK" }
            throw CampusCoreError.unauthorized
        } refresh: {
            await calls.record("refresh")
        }
        XCTAssertEqual(payload, "RENEWED-FALLBACK")
        let events = await calls.events
        XCTAssertEqual(events, ["direct", "rust", "refresh", "direct", "rust"])
    }

    func testCancellationAfterRenewalDoesNotFallThroughToFallback() async {
        let calls = QRRecoveryCalls()
        do {
            _ = try await CampusCardQRRecovery.payload {
                let events = await calls.events
                await calls.record("direct")
                if events.contains("refresh") { throw CancellationError() }
                throw CampusCoreError.unauthorized
            } fallback: {
                await calls.record("rust")
                throw CampusCoreError.unauthorized
            } refresh: {
                await calls.record("refresh")
            }
            XCTFail("Cancellation must propagate")
        } catch { XCTAssertTrue(error is CancellationError) }
        let events = await calls.events
        XCTAssertEqual(events, ["direct", "rust", "refresh", "direct"])
    }

    private func makeSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [QRTransportProtocol.self]
        return URLSession(configuration: config)
    }
}

private actor QRRecoveryCalls {
    private(set) var events: [String] = []
    @discardableResult func record(_ event: String) -> Int { events.append(event); return events.count }
}

private final class QRTransportProtocol: URLProtocol, @unchecked Sendable {
    static let state = QRTransportState()
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let (status, body) = Self.state.record(request)
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

private final class QRTransportState: @unchecked Sendable {
    private let lock = NSLock()
    private var captured: [URLRequest] = []
    private var status = 200
    private var body = ""
    func reset(status: Int = 200, body: String = #"{"code":10000,"object":"FIXTURE-QR"}"#) {
        lock.withLock { self.status = status; self.body = body; captured = [] }
    }
    func record(_ request: URLRequest) -> (Int, String) {
        lock.withLock { captured.append(request); return (status, body) }
    }
    func requests() -> [URLRequest] { lock.withLock { captured } }
}
