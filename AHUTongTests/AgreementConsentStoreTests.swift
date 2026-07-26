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

        XCTAssertTrue(privacy.contains("安徽大学对应业务系统"))
        XCTAssertTrue(privacy.contains("联系人、手机号和内容"))
        XCTAssertTrue(privacy.contains("不运营用于汇集用户业务数据的自有云服务"))
        XCTAssertFalse(privacy.contains("不会将您的用户数据上传"))
        XCTAssertFalse(disclaimer.contains("不会收集、存储或泄露用户的任何个人信息"))
    }

    func testPreviousPolicyVersionRequiresRenewedConsent() {
        let previous = AgreementConsent(
            acceptedDocumentIDs: Set(AgreementDocument.allCases.map(\.id)),
            confirmedVersion: AgreementConsent.currentVersion - 1
        )

        XCTAssertFalse(previous.isComplete)
    }
}
