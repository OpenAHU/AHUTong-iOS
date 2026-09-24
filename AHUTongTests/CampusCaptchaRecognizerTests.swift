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
        XCTAssertEqual(request.value(forHTTPHeaderField: "User-Agent"), "AHUTong/1.0 (iOS)")
        XCTAssertTrue(request.value(forHTTPHeaderField: "Content-Type")?.hasPrefix("multipart/form-data; boundary=") == true)
    }

    func testUploadFormatMatchesTheActualImageRatherThanAlwaysClaimingJPEG() {
        XCTAssertEqual(CampusCaptchaUploadFormat.detect(Data([0xFF, 0xD8, 0xFF])).contentType, "image/jpg")
        XCTAssertEqual(
            CampusCaptchaUploadFormat.detect(Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])).filename,
            "img.png"
        )
        XCTAssertEqual(CampusCaptchaUploadFormat.detect(Data("GIF89a".utf8)).contentType, "image/gif")
    }

    func testOCRHTTPStatusIsReportedWithoutLeakingResponseBody() async {
        do {
            _ = try await recognizer(using: CaptchaHTTPFailureProtocol.self).recognize(Data("test-only-image".utf8))
            XCTFail("Expected OCR HTTP failure")
        } catch {
            XCTAssertEqual(error as? CampusCaptchaRecognitionError, .status(503))
        }
    }

    func testOCRRedirectIsNotTreatedAsRecognition() async {
        do {
            _ = try await recognizer(using: CaptchaRedirectProtocol.self).recognize(Data("test-only-image".utf8))
            XCTFail("Expected OCR redirect rejection")
        } catch {
            XCTAssertEqual(error as? CampusCaptchaRecognitionError, .redirected)
        }
    }

    func testMalformedOCRResponseHasSeparateReason() async {
        do {
            _ = try await recognizer(using: CaptchaMalformedProtocol.self).recognize(Data("test-only-image".utf8))
            XCTFail("Expected malformed OCR response")
        } catch {
            XCTAssertEqual(error as? CampusCaptchaRecognitionError, .invalidResponse)
        }
    }

    func testNonFourCharacterOCRResultHasSeparateReason() async {
        do {
            _ = try await recognizer(using: CaptchaInvalidCodeProtocol.self).recognize(Data("test-only-image".utf8))
            XCTFail("Expected invalid OCR result")
        } catch {
            XCTAssertEqual(error as? CampusCaptchaRecognitionError, .invalidCode)
        }
    }

    func testOCRTimeoutHasSeparateReason() async {
        do {
            _ = try await recognizer(using: CaptchaTimeoutProtocol.self).recognize(Data("test-only-image".utf8))
            XCTFail("Expected OCR timeout")
        } catch {
            XCTAssertEqual(error as? CampusCaptchaRecognitionError, .timedOut)
        }
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

    private func recognizer(using fixture: AnyClass) -> RemoteCampusCaptchaRecognizer {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [fixture]
        return RemoteCampusCaptchaRecognizer(session: URLSession(configuration: configuration))
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

private class CaptchaTestURLProtocol: URLProtocol, @unchecked Sendable {
    static let lastRequest = CaptchaRequestBox()
    class var fixtureStatus: Int { 200 }
    class var fixtureBody: Data { Data(#"{"result":"A7B2"}"#.utf8) }
    class var fixtureError: Error? { nil }

    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.host == "openahu.org"
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lastRequest.set(request)
        if let error = Self.fixtureError {
            client?.urlProtocol(self, didFailWithError: error)
            return
        }
        let response = HTTPURLResponse(
            url: request.url!, statusCode: Self.fixtureStatus, httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.fixtureBody)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

private final class CaptchaHTTPFailureProtocol: CaptchaTestURLProtocol, @unchecked Sendable {
    override class var fixtureStatus: Int { 503 }
    override class var fixtureBody: Data { Data("private-school-error".utf8) }
}

private final class CaptchaRedirectProtocol: CaptchaTestURLProtocol, @unchecked Sendable {
    override class var fixtureStatus: Int { 302 }
}

private final class CaptchaMalformedProtocol: CaptchaTestURLProtocol, @unchecked Sendable {
    override class var fixtureBody: Data { Data(#"{"unexpected":"test"}"#.utf8) }
}

private final class CaptchaInvalidCodeProtocol: CaptchaTestURLProtocol, @unchecked Sendable {
    override class var fixtureBody: Data { Data(#"{"result":"ABCDE"}"#.utf8) }
}

private final class CaptchaTimeoutProtocol: CaptchaTestURLProtocol, @unchecked Sendable {
    override class var fixtureError: Error? { URLError(.timedOut) }
}
