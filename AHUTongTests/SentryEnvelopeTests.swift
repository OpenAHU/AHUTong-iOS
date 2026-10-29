import Foundation
import Sentry
import XCTest
import zlib
@testable import AHUTong

final class SentryEnvelopeTests: XCTestCase {
    func testFeedbackEnvelopeContainsOnlySelectedAttachments() throws {
        let received = expectation(description: "SDK envelope intercepted locally")
        EnvelopeProtocol.state.reset { received.fulfill() }
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [EnvelopeProtocol.self]
        let options = SentryConfiguration.options()
        options.dsn = "https://public@example.invalid/1"
        options.urlSession = URLSession(configuration: config)
        options.cacheDirectoryPath = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
        options.enableCrashHandler = false; options.enableSwizzling = false
        options.enableAutoSessionTracking = false; options.enableMetricKit = false
        options.enableWatchdogTerminationTracking = false; options.enableAutoPerformanceTracing = false
        options.tracesSampleRate = 0
        SentrySDK.start(options: options)
        defer { SentrySDK.close(); try? FileManager.default.removeItem(atPath: options.cacheDirectoryPath) }
        SentrySDK.configureScope { scope in
            let breadcrumb = Breadcrumb(level: .info, category: "app.diagnostics.runtime")
            breadcrumb.message = "unselected-runtime"
            scope.addBreadcrumb(breadcrumb)
            scope.addAttachment(Attachment(data: Data("unselected-attachment".utf8), filename: "ambient.txt"))
        }
        let log = DiagnosticLog(); log.setEnabled(true)
        log.append(.network, text: "selected-network-fixture", generation: log.generation)
        let preview = DiagnosticFeedbackPreview(message: "fixture-feedback-message", categories: [.network], log: log)
        let (event, hint) = AppDiagnostics.feedbackPayload(preview)
        SentrySDK.capture(event: event, scope: Scope(), hint: hint)
        SentrySDK.flush(timeout: 5)
        wait(for: [received], timeout: 5)
        let body = try XCTUnwrap(EnvelopeProtocol.state.data)
        let text = String(decoding: try ungzip(body), as: UTF8.self)
        XCTAssertTrue(text.contains("fixture-feedback-message"))
        XCTAssertTrue(text.contains("selected-network-fixture"))
        XCTAssertTrue(text.contains("\"type\":\"feedback\""))
        XCTAssertFalse(text.contains("unselected-runtime"))
        XCTAssertFalse(text.contains("unselected-attachment"))
    }

    func testDailyActivityUsesFullSamplingAndKeepsItsIdentityInTheEnvelope() throws {
        let received = expectation(description: "Daily activity envelope intercepted locally")
        EnvelopeProtocol.state.reset { received.fulfill() }
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [EnvelopeProtocol.self]
        let options = SentryConfiguration.options()
        options.dsn = "https://public@example.invalid/1"
        options.urlSession = URLSession(configuration: config)
        options.cacheDirectoryPath = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
        options.enableCrashHandler = false; options.enableSwizzling = false
        options.enableAutoSessionTracking = false; options.enableMetricKit = false
        options.enableWatchdogTerminationTracking = false; options.enableAutoPerformanceTracing = false
        options.tracesSampleRate = 0
        SentrySDK.start(options: options)
        defer { SentrySDK.close(); try? FileManager.default.removeItem(atPath: options.cacheDirectoryPath) }
        let installation = UUID().uuidString.lowercased()
        SentrySDK.configureScope { $0.setExtra(value: "private-scope-fixture", key: "account") }
        let context = TransactionContext(name: "AHUTong DAU", operation: "app.dau", sampled: .yes, sampleRate: 1, sampleRand: nil)
        let span = SentrySDK.startTransaction(transactionContext: context, bindToScope: false)
        span.setTag(value: installation, key: "dau_id")
        span.setData(value: "2026-10-30", key: "dau_date")
        span.finish(status: .ok)
        SentrySDK.flush(timeout: 5)
        wait(for: [received], timeout: 5)
        let text = String(decoding: try ungzip(XCTUnwrap(EnvelopeProtocol.state.data)), as: UTF8.self)
        XCTAssertTrue(text.contains("app.dau"))
        XCTAssertTrue(text.contains(installation))
        XCTAssertTrue(text.contains("2026-10-30"))
        XCTAssertFalse(text.contains("private-scope-fixture"))
    }

    private func ungzip(_ data: Data) throws -> Data {
        guard data.starts(with: [0x1f, 0x8b]) else { return data }
        var stream = z_stream()
        guard inflateInit2_(&stream, 31, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size)) == Z_OK else { throw DiagnosticFeedbackError.encryption }
        defer { inflateEnd(&stream) }
        var output = Data(count: 512 * 1024)
        let status: Int32 = data.withUnsafeBytes { input in
            output.withUnsafeMutableBytes { destination in
                stream.next_in = UnsafeMutablePointer(mutating: input.bindMemory(to: UInt8.self).baseAddress!)
                stream.avail_in = UInt32(input.count)
                stream.next_out = destination.bindMemory(to: UInt8.self).baseAddress!
                stream.avail_out = UInt32(destination.count)
                return inflate(&stream, Z_FINISH)
            }
        }
        guard status == Z_STREAM_END else { throw DiagnosticFeedbackError.encryption }
        return output.prefix(Int(stream.total_out))
    }
}

private final class EnvelopeProtocol: URLProtocol, @unchecked Sendable {
    static let state = EnvelopeState()
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        var data = request.httpBody
        if data == nil, let stream = request.httpBodyStream {
            stream.open(); defer { stream.close() }
            var collected = Data(), buffer = [UInt8](repeating: 0, count: 8192)
            while stream.hasBytesAvailable {
                let count = stream.read(&buffer, maxLength: buffer.count)
                if count <= 0 { break }; collected.append(contentsOf: buffer.prefix(count))
            }
            data = collected
        }
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data("{}".utf8))
        client?.urlProtocolDidFinishLoading(self)
        Self.state.received(data)
    }
    override func stopLoading() {}
}

private final class EnvelopeState: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: Data?
    private var callback: (() -> Void)?
    var data: Data? { lock.withLock { stored } }
    func reset(_ callback: @escaping () -> Void) { lock.withLock { stored = nil; self.callback = callback } }
    func received(_ data: Data?) {
        let notify = lock.withLock { () -> (() -> Void)? in
            guard stored == nil else { return nil }; stored = data
            defer { callback = nil }; return callback
        }
        notify?()
    }
}
