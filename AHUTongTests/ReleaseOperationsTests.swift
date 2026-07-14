import Foundation
import XCTest
@testable import AHUTong

final class GrayRolloutTests: XCTestCase {
    func testBucketMatchesAndroidSHA256Implementation() {
        XCTAssertEqual(GrayRollout.bucket(featureKey: "home_edit", subjectKey: "guest"), 57)
        XCTAssertEqual(GrayRollout.bucket(featureKey: "home_edit", subjectKey: "student-20260001"), 58)
        XCTAssertEqual(GrayRollout.bucket(featureKey: "payment", subjectKey: "guest"), 42)
    }

    func testRolloutBoundaryIsClamped() {
        XCTAssertFalse(GrayRollout.isEnabled(rolloutPercentage: 0, bucket: 0))
        XCTAssertTrue(GrayRollout.isEnabled(rolloutPercentage: 100, bucket: 99))
        XCTAssertTrue(GrayRollout.isEnabled(rolloutPercentage: 25, bucket: 24))
        XCTAssertFalse(GrayRollout.isEnabled(rolloutPercentage: 25, bucket: 25))
    }

    func testSubjectIsHashedBeforeRemoteQuery() throws {
        let rawID = "2026000001"
        let hash = GrayRollout.subjectHash(userID: rawID)
        XCTAssertEqual(hash.count, 64)
        XCTAssertFalse(hash.contains(rawID))

        let url = try GrayReleaseService.remoteURL(
            endpoint: URL(string: "https://openahu.org/api/gray/check")!,
            feature: "home_edit",
            hashedSubject: hash,
            versionCode: 1,
            versionName: "3.1.9"
        )
        XCTAssertFalse(url.absoluteString.contains(rawID))
        XCTAssertTrue(url.absoluteString.contains(hash))
    }

    func testRemoteURLRejectsRawSubject() {
        XCTAssertThrowsError(try GrayReleaseService.remoteURL(
            endpoint: URL(string: "https://openahu.org/api/gray/check")!,
            feature: "home_edit",
            hashedSubject: "2026000001",
            versionCode: 1,
            versionName: "3.1.9"
        ))
    }
}

final class RedactingLoggerTests: XCTestCase {
    func testSensitiveFieldsAndBearerAreRedacted() {
        let input = "password=123456 token=abc cookie=session authorization=Bearer-raw phone=13800000000 Bearer abc.def"
        let output = RedactingLogger.sanitize(input)

        XCTAssertFalse(output.contains("123456"))
        XCTAssertFalse(output.contains("abc.def"))
        XCTAssertFalse(output.contains("13800000000"))
        XCTAssertTrue(output.contains("password=<redacted>"))
        XCTAssertTrue(output.contains("Bearer <redacted>"))
    }

    func testNonSensitiveOperationalMessageIsPreserved() {
        XCTAssertEqual(
            RedactingLogger.sanitize("payment reconciliation pending order=MOCK-1"),
            "payment reconciliation pending order=MOCK-1"
        )
    }
}

final class ReleaseDiagnosticsTests: XCTestCase {
    func testProductionPaymentAndCrashCollectionRemainSafetyOff() {
        let diagnostics = ReleaseDiagnostics.current()
        XCTAssertFalse(diagnostics.productionPaymentGatewayConfigured)
        XCTAssertFalse(diagnostics.thirdPartyCrashReportingEnabled)
    }

    func testPrivacyManifestShipsInHostedApplication() {
        let audit = PrivacyManifestAudit.inspect()
        XCTAssertTrue(audit.exists)
        XCTAssertTrue(audit.trackingDisabled)
        XCTAssertTrue(audit.declaresPaymentInfo)
    }
}
