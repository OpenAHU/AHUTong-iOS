import CryptoKit
import Foundation
import Security
import Sentry
import XCTest
@testable import AHUTong

final class DiagnosticLogTests: XCTestCase {
    func testDisabledCollectionDoesNotRetainEntries() {
        let log = DiagnosticLog()
        XCTAssertFalse(log.append(.runtime, text: "hello", generation: log.generation))
        XCTAssertEqual(log.snapshot(.runtime), "")
    }
    func testSwitchingAccountRejectsPendingResponse() {
        let log = DiagnosticLog(); log.setEnabled(true)
        let old = log.generation
        log.append(.network, text: "old account", generation: old)
        log.clear()
        XCTAssertFalse(log.append(.network, text: "late response", generation: old))
        XCTAssertEqual(log.snapshot(.network), "")
    }
    func testConsentWithdrawalClearsMemory() {
        let log = DiagnosticLog(); log.setEnabled(true)
        log.append(.network, text: "sensitive", generation: log.generation)
        log.setEnabled(false)
        XCTAssertNil(log.activeGeneration)
        XCTAssertEqual(log.snapshot(.network), "")
    }
    func testByteBudgetDropsOldestEntry() {
        let log = DiagnosticLog(maximumBytes: 8); log.setEnabled(true)
        log.append(.runtime, text: "12345", generation: log.generation)
        log.append(.runtime, text: "67890", generation: log.generation)
        XCTAssertEqual(log.snapshot(.runtime), "67890")
    }
    func testExpiredLogsAreDiscardedWhenRead() {
        let clock = TestClock()
        let log = DiagnosticLog(lifetime: 600, clock: { clock.value }); log.setEnabled(true)
        log.append(.runtime, text: "expired", generation: log.generation)
        clock.value = 601
        XCTAssertEqual(log.snapshot(.runtime), "")
    }
    func testPasswordRedactionHandlesNestedJSONAndEscapes() throws {
        let value = #"{"nested":{"password":"foo\"bar","encrypted_password":"cipher"},"items":[{"pwd":"1234"}],"ok":"visible"}"#
        let redacted = DiagnosticText.redacted(value, includeIdentity: false)
        XCTAssertFalse(redacted.contains("foo")); XCTAssertFalse(redacted.contains("cipher"))
        XCTAssertFalse(redacted.contains("1234")); XCTAssertTrue(redacted.contains("visible"))
    }
    func testRuntimeSummaryRemovesIdentityAndURLQueries() {
        let value = "GET https://one.ahu.edu.cn/result?student=AB220001&opaque=private-value\nCookie: SSO=private-cookie\nBearer private-token"
        let safe = DiagnosticText.redacted(value)
        XCTAssertFalse(safe.contains("private-")); XCTAssertFalse(safe.contains("AB220001"))
        XCTAssertTrue(safe.contains("one.ahu.edu.cn/result"))
    }
    func testNetworkDetailKeepsIdentityOnlyForExplicitPreview() {
        let safe = DiagnosticText.redacted(#"{"studentId":"AB220001","token":"example-token","password":"never-send"}"#, includeIdentity: false)
        XCTAssertTrue(safe.contains("AB220001")); XCTAssertTrue(safe.contains("example-token"))
        XCTAssertFalse(safe.contains("never-send"))
    }
    func testOversizedBodyIsOmittedWithoutPartialSecrets() {
        let data = Data(repeating: 65, count: 256 * 1024 + 1)
        XCTAssertEqual(DiagnosticText.body(data, contentType: "application/json"), "[正文超过256KiB，未采集]")
    }
    func testContributionKeyNeverAppearsInNetworkHeaders() {
        let text = DiagnosticText.headers(["X-Write-Key": "never-send", "Cookie": "explicit-preview-only"])
        XCTAssertFalse(text.contains("never-send")); XCTAssertTrue(text.contains("explicit-preview-only"))
    }
    func testFeedbackUsesFrozenSelectedSnapshot() {
        let log = DiagnosticLog(); log.setEnabled(true)
        log.append(.runtime, text: "first", generation: log.generation)
        log.append(.network, text: "not-selected", generation: log.generation)
        let preview = DiagnosticFeedbackPreview(message: "help", categories: [.runtime], log: log)
        log.append(.runtime, text: "later", generation: log.generation)
        XCTAssertTrue(preview.displayText.contains("first"))
        XCTAssertFalse(preview.displayText.contains("later")); XCTAssertFalse(preview.displayText.contains("not-selected"))
    }
    func testDailyActivityCountsEachInstallationOncePerLocalDay() {
        let name = UUID().uuidString; let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let activity = DiagnosticActivityStore(defaults: defaults)
        let now = Date(timeIntervalSince1970: 1_798_113_600)
        var calls = 0
        for _ in 0..<5 { activity.reportIfNeeded(now: now) { _, _ in calls += 1; return true } }
        activity.reportIfNeeded(now: now.addingTimeInterval(86_400)) { _, _ in calls += 1; return true }
        XCTAssertEqual(calls, 2)
        XCTAssertEqual(activity.installationID, DiagnosticActivityStore(defaults: defaults).installationID)
    }
    func testDisabledDAUSenderDoesNotConsumeToday() {
        let name = UUID().uuidString; let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let activity = DiagnosticActivityStore(defaults: defaults)
        let now = Date(); var calls = 0
        activity.reportIfNeeded(now: now) { _, _ in false }
        activity.reportIfNeeded(now: now) { _, _ in calls += 1; return true }
        XCTAssertEqual(calls, 1)
    }
    func testBreadcrumbScrubberRetainsSafeSummaryOnly() throws {
        let breadcrumb = Breadcrumb(level: .info, category: "app.network")
        breadcrumb.message = "GET https://one.ahu.edu.cn/query?token=private-token"
        breadcrumb.setData(value: "private-cookie", key: "Cookie")
        let result = try XCTUnwrap(DiagnosticsSanitizer.sanitizeBreadcrumb(breadcrumb))
        XCTAssertEqual(result.message, "GET https://one.ahu.edu.cn/query")
        XCTAssertTrue(result.data?.isEmpty != false)
    }
    func testEncryptedExportCanBeDecryptedWithOnlyMatchingPrivateKey() throws {
        let attributes: [CFString: Any] = [kSecAttrKeyType: kSecAttrKeyTypeRSA, kSecAttrKeySizeInBits: 3072]
        let privateKey = try XCTUnwrap(SecKeyCreateRandomKey(attributes as CFDictionary, nil))
        let publicKey = try XCTUnwrap(SecKeyCopyPublicKey(privateKey))
        let pkcs1 = try XCTUnwrap(SecKeyCopyExternalRepresentation(publicKey, nil) as Data?)
        let algorithm = Data([0x30,0x0d,0x06,0x09,0x2a,0x86,0x48,0x86,0xf7,0x0d,0x01,0x01,0x01,0x05,0x00])
        let der = field(0x30, algorithm + field(0x03, Data([0]) + pkcs1))
        let result = try DiagnosticLogExport.encrypt("fixture-private-log", publicDER: der)
        let payload = try XCTUnwrap(JSONSerialization.jsonObject(with: result) as? [String: String])
        XCTAssertFalse(String(decoding: result, as: UTF8.self).contains("fixture-private-log"))
        let wrapped = try XCTUnwrap(Data(base64Encoded: payload["wrappedKey"]!))
        let secret = try XCTUnwrap(SecKeyCreateDecryptedData(privateKey, .rsaEncryptionOAEPSHA256, wrapped as CFData, nil) as Data?)
        let combined = try XCTUnwrap(Data(base64Encoded: payload["ciphertext"]!))
        let nonce = try AES.GCM.Nonce(data: XCTUnwrap(Data(base64Encoded: payload["nonce"]!)))
        let box = try AES.GCM.SealedBox(nonce: nonce, ciphertext: combined.dropLast(16), tag: combined.suffix(16))
        let aad = Data("\(payload["format"]!)|\(payload["algorithm"]!)|\(payload["keyId"]!)".utf8)
        let plain = try AES.GCM.open(box, using: SymmetricKey(data: secret), authenticating: aad)
        XCTAssertEqual(String(decoding: plain, as: UTF8.self), "fixture-private-log")
    }
    func testMalformedPublicKeyCannotExportPlaintext() {
        XCTAssertThrowsError(try DiagnosticLogExport.encrypt("private", publicDER: Data([0x30,0xff])))
    }
    private func field(_ tag: UInt8, _ data: Data) -> Data {
        let length = data.count < 128 ? Data([UInt8(data.count)]) : Data([0x82, UInt8(data.count >> 8), UInt8(data.count & 255)])
        return Data([tag]) + length + data
    }
}

private final class TestClock: @unchecked Sendable {
    private let lock = NSLock(); private var stored = 0.0
    var value: Double { get { lock.withLock { stored } } set { lock.withLock { stored = newValue } } }
}
