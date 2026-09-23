import XCTest
@testable import AHUTong

final class AgreementConsentStoreTests: XCTestCase {
    @MainActor
    func testRequiredDocumentsPersistAndCompleteConsent() async throws {
        let dataStore = InMemoryDataStore()
        let store = AgreementConsentStore(store: dataStore)

        var consent = try await store.load()
        XCTAssertFalse(consent.isComplete)

        consent = try await store.setAccepted(true, document: .disclaimer)
        XCTAssertFalse(consent.isComplete)
        consent = try await store.setAccepted(true, document: .privacy)
        XCTAssertFalse(consent.isComplete)
        XCTAssertTrue(consent.hasAcceptedRequiredDocuments)
        consent = try await store.confirmRequiredDocuments()
        XCTAssertTrue(consent.isComplete)

        let reloaded = try await AgreementConsentStore(store: dataStore).load()
        XCTAssertEqual(reloaded, consent)
    }

    @MainActor
    func testOptionalCommunityDocumentDoesNotBlockEntry() async throws {
        let store = AgreementConsentStore(store: InMemoryDataStore())

        _ = try await store.setAccepted(true, document: .disclaimer)
        let consent = try await store.setAccepted(true, document: .privacy)

        XCTAssertTrue(consent.hasAcceptedRequiredDocuments)
        XCTAssertFalse(consent.isAccepted(.community))
    }

    @MainActor
    func testDecliningPrivacyStillAllowsExperienceModeConsent() async throws {
        let store = AgreementConsentStore(store: InMemoryDataStore())

        _ = try await store.setPrivacyDecision(.declined)
        _ = try await store.setAccepted(true, document: .disclaimer)
        let consent = try await store.confirmRequiredDocuments()

        XCTAssertEqual(consent.privacyDecision, .declined)
        XCTAssertTrue(consent.hasResolvedRequiredDocuments)
        XCTAssertFalse(consent.hasAcceptedRequiredDocuments)
        XCTAssertTrue(consent.isComplete)
    }

    @MainActor
    func testResetRevokesConsent() async throws {
        let store = AgreementConsentStore(store: InMemoryDataStore())
        _ = try await store.setAccepted(true, document: .disclaimer)
        _ = try await store.setAccepted(true, document: .privacy)

        try await store.reset()

        let resetConsent = try await store.load()
        XCTAssertEqual(resetConsent, .empty)
    }

    func testPrivacyCopyDisclosesSchoolSubmissionAndRejectsLegacyNoUploadClaim() {
        let privacy = AgreementDocument.privacy.body
        let disclaimer = AgreementDocument.disclaimer.body

        XCTAssertTrue(privacy.contains("ThisDeviceOnly"))
        XCTAssertTrue(privacy.contains("App 可启动隐藏 WebView"))
        XCTAssertTrue(privacy.contains("远程验证码识别请求只包含"))
        XCTAssertTrue(privacy.contains("首次登录需要图形验证码"))
        XCTAssertTrue(privacy.contains("远程验证码识别接口"))
        XCTAssertTrue(privacy.contains("保存到本机文件"))
        XCTAssertTrue(privacy.contains("不附带学号、密码、Cookie、Token"))
        XCTAssertTrue(privacy.contains("安大通体验用户"))
        XCTAssertFalse(privacy.contains("不会将您的用户数据上传"))
        XCTAssertFalse(disclaimer.contains("不会收集、存储或泄露用户的任何个人信息"))
    }

    func testPreviousPolicyVersionRequiresRenewedConsent() {
        let previous = AgreementConsent(
            acceptedDocumentIDs: Set(AgreementDocument.allCases.map(\.id)),
            confirmedVersion: AgreementConsent.currentVersion - 1,
            privacyDecision: .accepted,
            privacyPolicyVersion: AgreementConsent.currentPrivacyPolicyVersion - 1
        )

        XCTAssertFalse(previous.isComplete)
    }
}
