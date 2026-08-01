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
        let input = [
            "password=123456 token=abc cookie=session phone=13800000000",
            "authorization=Bearer-raw",
            "Bearer abc.def"
        ].joined(separator: "\n")
        let output = RedactingLogger.sanitize(input)

        XCTAssertFalse(output.contains("123456"))
        XCTAssertFalse(output.contains("abc.def"))
        XCTAssertFalse(output.contains("13800000000"))
        XCTAssertTrue(output.contains("password=<redacted>"))
        XCTAssertTrue(output.contains("token=<redacted>"))
        XCTAssertTrue(output.contains("cookie=<redacted>"))
        XCTAssertTrue(output.contains("authorization=<redacted>"))
        XCTAssertTrue(output.contains("phone=<redacted>"))
        XCTAssertTrue(output.contains("Bearer <redacted>"))
        XCTAssertEqual(RedactingLogger.sanitize(output), output)
    }

    func testNonSensitiveOperationalMessageIsPreserved() {
        XCTAssertEqual(
            RedactingLogger.sanitize("payment reconciliation pending order=MOCK-1"),
            "payment reconciliation pending order=MOCK-1"
        )
    }

    func testCampusHeadersAndEncodedCredentialsAreRedacted() {
        let input = [
            "Synjones-Auth: bearer campus-secret",
            "Set-Cookie: YCardSession=cookie-secret; Path=/",
            "return=https%253A%252F%252Fycard.ahu.edu.cn%252Fdone"
                + "%253Fsynjones-auth%253Dtoken-secret%2526ticket%253DST-secret"
        ].joined(separator: "\n")

        let output = RedactingLogger.sanitize(input)

        XCTAssertFalse(output.contains("campus-secret"))
        XCTAssertFalse(output.contains("cookie-secret"))
        XCTAssertFalse(output.contains("token-secret"))
        XCTAssertFalse(output.contains("ST-secret"))
        XCTAssertTrue(output.contains("Synjones-Auth: <redacted>"))
        XCTAssertTrue(output.contains("Set-Cookie: <redacted>"))
        XCTAssertTrue(output.contains("synjones-auth=<redacted>"))
        XCTAssertTrue(output.contains("ticket=<redacted>"))
        XCTAssertEqual(RedactingLogger.sanitize(output), output)
    }

    func testStandardHeadersJSONAndBasicAuthorizationAreRedacted() {
        let input = [
            "Cookie: SESSION=cookie-value; Path=/",
            "X-AHUTONG-TOKEN: local-server-value",
            "Authorization: Basic base64-value",
            #"payload={"password":"json-password","token":"json-token"}"#,
            #"other={'studentId':'student-value','phone':'phone-value'}"#
        ].joined(separator: "\n")

        let output = RedactingLogger.sanitize(input)

        for secret in [
            "cookie-value",
            "local-server-value",
            "base64-value",
            "json-password",
            "json-token",
            "student-value",
            "phone-value"
        ] {
            XCTAssertFalse(output.contains(secret))
        }
        XCTAssertTrue(output.contains("Cookie: <redacted>"))
        XCTAssertTrue(output.contains("X-AHUTONG-TOKEN: <redacted>"))
        XCTAssertTrue(output.contains("Authorization: <redacted>"))
        XCTAssertTrue(output.contains(#"payload={"password":"<redacted>","token":"<redacted>"}"#))
        XCTAssertTrue(output.contains(#"other={'studentId':"<redacted>",'phone':"<redacted>"}"#))
        XCTAssertEqual(RedactingLogger.sanitize(output), output)
    }

    func testEncodedWhitespaceCannotExposeCredentialSuffix() {
        let output = RedactingLogger.sanitize(
            "token=alpha%20secret&next=preserved"
        )

        XCTAssertFalse(output.contains("alpha"))
        XCTAssertFalse(output.contains("secret"))
        XCTAssertTrue(output.contains("token=<redacted>"))
        XCTAssertTrue(output.contains("next=preserved"))
    }

    func testEmbeddedAuthorizationSchemeRedactsTheWholeCredential() {
        let output = RedactingLogger.sanitize(
            "request Authorization: Basic base64-secret next=preserved"
        )

        XCTAssertFalse(output.contains("Basic"))
        XCTAssertFalse(output.contains("base64-secret"))
        XCTAssertTrue(output.contains("Authorization: <redacted>"))
        XCTAssertEqual(RedactingLogger.sanitize(output), output)
    }

    func testMalformedPercentEscapeCannotBlockLaterCredentialDecoding() {
        let output = RedactingLogger.sanitize(
            "noise=%ZZ return=https%3A%2F%2Fx.example%2Fdone"
                + "%3Fsynjones-auth%3Dtoken-secret"
        )

        XCTAssertTrue(output.contains("noise=%ZZ"))
        XCTAssertFalse(output.contains("token-secret"))
        XCTAssertTrue(output.contains("synjones-auth=<redacted>"))
    }

    func testEmbeddedDigestAuthorizationIsFailClosed() {
        let output = RedactingLogger.sanitize(
            #"request Authorization: Digest username="u", response="proof""#
        )

        XCTAssertFalse(output.contains("Digest"))
        XCTAssertFalse(output.contains("username"))
        XCTAssertFalse(output.contains("proof"))
        XCTAssertTrue(output.contains("Authorization: <redacted>"))
    }

    func testEqualsDigestAuthorizationIsFailClosed() {
        let output = RedactingLogger.sanitize(
            #"request Authorization=Digest username="u", response="proof""#
        )

        XCTAssertFalse(output.contains("Digest"))
        XCTAssertFalse(output.contains("username"))
        XCTAssertFalse(output.contains("proof"))
        XCTAssertTrue(output.contains("Authorization=<redacted>"))
    }
}

final class ReleaseDiagnosticsTests: XCTestCase {
    func testProductionPaymentIsConfiguredWithoutCrashCollection() {
        let diagnostics = ReleaseDiagnostics.current()
        XCTAssertTrue(diagnostics.productionPaymentGatewayConfigured)
        XCTAssertFalse(diagnostics.thirdPartyCrashReportingEnabled)
    }

    func testPrivacyManifestShipsInHostedApplication() {
        let audit = PrivacyManifestAudit.inspect()
        XCTAssertTrue(audit.exists)
        XCTAssertTrue(audit.trackingDisabled)
        XCTAssertTrue(audit.declaresPaymentInfo)
    }
}
