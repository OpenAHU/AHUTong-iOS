import Foundation
import XCTest
@testable import AHUTong

final class CampusCaptchaRecognizerTests: XCTestCase {
    func testRemoteRecognitionSendsOnlyImageToPinnedHTTPSHost() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [CaptchaTestURLProtocol.self]
        let recognizer = RemoteCampusCaptchaRecognizer(session: URLSession(configuration: configuration))

        let code = try await recognizer.recognize(Data("test-only-image".utf8))

        XCTAssertEqual(code, "A7B2")
        let request = try XCTUnwrap(CaptchaTestURLProtocol.lastRequest.value)
        XCTAssertEqual(request.url?.absoluteString, "https://openahu.org/ocr/captcha")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertNil(request.value(forHTTPHeaderField: "Cookie"))
        XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
        XCTAssertTrue(request.value(forHTTPHeaderField: "Content-Type")?.hasPrefix("multipart/form-data; boundary=") == true)
    }

    func testEmptyCaptchaImageIsRejectedBeforeNetworkRequest() async {
        let recognizer = RemoteCampusCaptchaRecognizer()

        do {
            _ = try await recognizer.recognize(Data())
            XCTFail("Expected invalid image")
        } catch {
            XCTAssertEqual(error as? CampusCaptchaRecognitionError, .invalidImage)
        }
    }
}

private final class CaptchaRequestBox: @unchecked Sendable {
    private let lock = NSLock()
    private var request: URLRequest?

    var value: URLRequest? {
        lock.lock()
        defer { lock.unlock() }
        return request
    }

    func set(_ request: URLRequest) {
        lock.lock()
        self.request = request
        lock.unlock()
    }
}

private final class CaptchaTestURLProtocol: URLProtocol, @unchecked Sendable {
    static let lastRequest = CaptchaRequestBox()

    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.host == "openahu.org"
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lastRequest.set(request)
        let response = HTTPURLResponse(
            url: request.url!, statusCode: 200, httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(#"{"result":"A7B2"}"#.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
