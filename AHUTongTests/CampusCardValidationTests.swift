import Foundation
import XCTest
@testable import AHUTong

final class CampusCardValidationTests: XCTestCase {
    func testRenewalValidationUsesQRCodeWithoutWaitingForBalance() async throws {
        let session = makeSession()
        defer { session.invalidateAndCancel() }
        QRValidationURLProtocol.state.reset(payload: "RENEWED-QR")
        let api = RustCampusCoreAPI(session: session)

        try await api.validateSession(scope: .campusCard)

        XCTAssertEqual(QRValidationURLProtocol.state.paths(), ["/ycard/qrcode"])
    }

    func testRenewalValidationRejectsEmptyPaymentCode() async {
        let session = makeSession()
        defer { session.invalidateAndCancel() }
        QRValidationURLProtocol.state.reset(payload: "")
        let api = RustCampusCoreAPI(session: session)

        do {
            try await api.validateSession(scope: .campusCard)
            XCTFail("空付款码不能证明会话已恢复")
        } catch {
            XCTAssertEqual(error as? CampusCoreError, .invalidResponse)
        }
        XCTAssertEqual(QRValidationURLProtocol.state.paths(), ["/ycard/qrcode"])
    }

    private func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [QRValidationURLProtocol.self]
        return URLSession(configuration: configuration)
    }
}

private final class QRValidationURLProtocol: URLProtocol, @unchecked Sendable {
    static let state = QRValidationState()
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let path = request.url?.path ?? ""
        let payload = Self.state.record(path: path)
        // Any attempt to use the balance endpoint fails, just like a weak-network timeout.
        guard path == "/ycard/qrcode", let url = request.url else {
            client?.urlProtocol(self, didFailWithError: URLError(.timedOut))
            return
        }
        let data = try! JSONSerialization.data(withJSONObject: ["code": 10000, "object": payload])
        let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

private final class QRValidationState: @unchecked Sendable {
    private let lock = NSLock()
    private var recordedPaths: [String] = []
    private var payload = ""
    func reset(payload: String) { lock.withLock { self.payload = payload; recordedPaths = [] } }
    func record(path: String) -> String {
        lock.withLock { recordedPaths.append(path); return payload }
    }
    func paths() -> [String] { lock.withLock { recordedPaths } }
}
