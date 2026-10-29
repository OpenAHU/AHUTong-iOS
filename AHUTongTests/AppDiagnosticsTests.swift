import Sentry
import XCTest
@testable import AHUTong

final class AppDiagnosticsTests: XCTestCase {
    private var accepted: AgreementConsent {
        AgreementConsent(acceptedDocumentIDs: [AgreementDocument.disclaimer.id, AgreementDocument.privacy.id],
                         confirmedVersion: AgreementConsent.currentVersion, privacyDecision: .accepted,
                         privacyPolicyVersion: AgreementConsent.currentPrivacyPolicyVersion)
    }

    func testOnlyCurrentConfirmedPrivacyAllowsReporting() {
        XCTAssertTrue(DiagnosticsConsentPolicy.allowsReporting(accepted, isolated: false))
        XCTAssertFalse(DiagnosticsConsentPolicy.allowsReporting(accepted, isolated: true))
        XCTAssertFalse(DiagnosticsConsentPolicy.allowsReporting(.empty, isolated: false))
        var consent = accepted
        consent.privacyDecision = .declined
        XCTAssertFalse(DiagnosticsConsentPolicy.allowsReporting(consent, isolated: false))
        consent = accepted
        consent.privacyPolicyVersion = AgreementConsent.currentPrivacyPolicyVersion - 1
        XCTAssertFalse(DiagnosticsConsentPolicy.allowsReporting(consent, isolated: false))
        consent = accepted
        consent.confirmedVersion = nil
        XCTAssertFalse(DiagnosticsConsentPolicy.allowsReporting(consent, isolated: false))
    }

    func testAutomaticContentAndIdentityCollectionAreDisabled() {
        let options = SentryConfiguration.options()
        XCTAssertNotNil(options.dsn)
        XCTAssertFalse(options.debug)
        XCTAssertFalse(options.sendDefaultPii)
        XCTAssertFalse(options.enableAutoSessionTracking)
        XCTAssertFalse(options.enableSwizzling)
        XCTAssertFalse(options.enableAutoBreadcrumbTracking)
        XCTAssertFalse(options.enableNetworkBreadcrumbs)
        XCTAssertFalse(options.enableCaptureFailedRequests)
        XCTAssertFalse(options.enableAutoPerformanceTracing)
        XCTAssertFalse(options.enableNetworkTracking)
        XCTAssertFalse(options.enableLogs)
        XCTAssertFalse(options.enableMetrics)
        XCTAssertFalse(options.sendClientReports)
        XCTAssertFalse(options.enableMetricKit)
        XCTAssertFalse(options.enableMetricKitRawPayload)
        XCTAssertFalse(options.enableMemoryIntrospection)
        XCTAssertFalse(options.attachScreenshot)
        XCTAssertFalse(options.attachViewHierarchy)
        XCTAssertEqual(options.tracesSampleRate, 0)
        XCTAssertEqual(options.sessionReplay.sessionSampleRate, 0)
        XCTAssertEqual(options.sessionReplay.onErrorSampleRate, 0)
        XCTAssertEqual(options.maxBreadcrumbs, 0)
    }

    func testSensitiveEventFieldsAreRemovedAndStackAddressesRemain() throws {
        let event = Event(level: .error)
        event.message = SentryMessage(formatted: "PRIVATE-ACCOUNT PRIVATE-QR")
        event.error = NSError(domain: "PRIVATE-DOMAIN", code: 1, userInfo: ["Cookie": "PRIVATE-COOKIE"])
        event.user = User(userId: "PRIVATE-USER")
        event.extra = ["password": "PRIVATE-PASSWORD", "courses": "PRIVATE-COURSE"]
        event.serverName = "PRIVATE-DEVICE"
        event.logger = "PRIVATE-LOGGER"
        event.modules = ["PRIVATE-MODULE": "PRIVATE-VERSION"]
        event.transaction = "PRIVATE-URL"
        event.tags = ["ahu.signal": DiagnosticSignal.sessionRefreshFailed.rawValue,
                      "ahu.stage": DiagnosticStage.refresh.rawValue,
                      "ahu.failure": DiagnosticFailure.network.rawValue,
                      "ahu.network_code": "-1009", "student": "PRIVATE-STUDENT"]
        event.context = ["device": ["model": "iPhone18,1", "name": "PRIVATE-NAME", "id": "PRIVATE-ID"],
                         "os": ["version": "27.0"], "course": ["title": "PRIVATE-COURSE"]]
        let frame = Frame()
        frame.instructionAddress = "0x1234"
        frame.vars = ["cookie": "PRIVATE-COOKIE"]
        frame.contextLine = "PRIVATE-SOURCE"
        frame.preContext = ["PRIVATE-BEFORE"]
        frame.postContext = ["PRIVATE-AFTER"]
        frame.fileName = "/Users/PRIVATE-PATH/App.swift"
        frame.package = "/Users/PRIVATE-PATH/App.debug.dylib"
        let exception = Exception(value: "PRIVATE-REASON", type: "NSException")
        exception.stacktrace = SentryStacktrace(frames: [frame], registers: ["r0": "PRIVATE-REGISTER"])
        event.exceptions = [exception]
        let result = try XCTUnwrap(DiagnosticsSanitizer.sanitize(event))
        let data = try JSONSerialization.data(withJSONObject: result.serialize())
        let json = try XCTUnwrap(String(data: data, encoding: .utf8))
        XCTAssertFalse(json.contains("PRIVATE-"), json)
        XCTAssertTrue(json.contains("iPhone18,1"))
        XCTAssertTrue(json.contains("0x1234"))
        XCTAssertTrue(json.contains("NSException"))
        XCTAssertTrue(json.contains("session-refresh-failed"))
        XCTAssertEqual(result.tags?["ahu.network_code"], "-1009")
        XCTAssertNil(result.user)
        XCTAssertNil(result.error)
        XCTAssertNil(result.request)
        XCTAssertNil(result.extra)
    }

    func testOnlyClosedDiagnosticTagsAreAccepted() {
        XCTAssertEqual(DiagnosticsSanitizer.safeTags([
            "ahu.signal": "PRIVATE-QR", "ahu.stage": "https://example.test/PRIVATE-TOKEN",
            "ahu.failure": "PRIVATE-ERROR", "ahu.scope": "PRIVATE-ACCOUNT",
            "ahu.widget_issue": "PRIVATE-PROFILE", "ahu.network_code": "PRIVATE-CODE",
            "other": "PRIVATE-DATA"
        ]), [:])
    }

    func testRetiredCampusCodeAndUnknownSignalsAreDropped() {
        for signal in ["campus-code-failed", "unknown-signal"] {
            let event = Event(level: .warning)
            event.tags = ["ahu.signal": signal]
            XCTAssertNil(DiagnosticsSanitizer.sanitize(event))
        }
        XCTAssertNotNil(DiagnosticsSanitizer.sanitize(Event(level: .fatal)))
    }

    func testRetiredQueueRemovalPreservesCurrentCacheAndUnrelatedFiles() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        for name in ["AHUTongDiagnostics", "AHUTongDiagnostics-v2", "unrelated"] {
            let directory = root.appendingPathComponent(name)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try Data("synthetic envelope".utf8).write(to: directory.appendingPathComponent("event"))
        }
        SentryConfiguration.removeRetiredCache(in: root)
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("AHUTongDiagnostics").path))
        for name in ["AHUTongDiagnostics-v2", "unrelated"] {
            XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent(name + "/event").path))
        }
    }

    func testErrorClassificationDoesNotNeedErrorTextOrUserInfo() {
        XCTAssertEqual(DiagnosticFailure.classify(URLError(.notConnectedToInternet,
            userInfo: [NSURLErrorFailingURLStringErrorKey: "PRIVATE-URL"])), .network)
        XCTAssertEqual(DiagnosticFailure.classify(CampusCoreError.unauthorized), .sessionExpired)
        XCTAssertEqual(DiagnosticFailure.classify(CampusCoreError.campus("PRIVATE-RESPONSE")), .service)
    }

    /// Explicit local integration check. Normal unit/UI/CI runs never send events.
    func testOptInSentryDelivery() throws {
        guard ProcessInfo.processInfo.environment["AHUTONG_SENTRY_SMOKE"] == "1" else {
            throw XCTSkip("Requires explicit local Sentry verification opt-in")
        }
        let options = SentryConfiguration.options()
        options.environment = "integration-test"
        options.enableCrashHandler = false
        options.cacheDirectoryPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("sentry-verification-\(UUID().uuidString)").path
        SentrySDK.start(options: options)
        defer {
            SentrySDK.close()
            try? FileManager.default.removeItem(atPath: options.cacheDirectoryPath)
        }
        let event = Event(level: .info)
        event.tags = DiagnosticRecord(signal: .verification, stage: .verification, failure: .none).tags
        let id = SentrySDK.capture(event: event)
        SentrySDK.flush(timeout: 15)
        XCTAssertFalse(id.sentryIdString.isEmpty)
        print("Sentry synthetic verification event: \(id.sentryIdString)")
    }
}
