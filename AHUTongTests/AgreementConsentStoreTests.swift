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

    func testPreviousPolicyVersionRequiresRenewedConsent() {
        let previous = AgreementConsent(
            acceptedDocumentIDs: Set(AgreementDocument.allCases.map(\.id)),
            confirmedVersion: AgreementConsent.currentVersion,
            privacyDecision: .accepted,
            privacyPolicyVersion: AgreementConsent.currentPrivacyPolicyVersion - 1
        )

        XCTAssertFalse(previous.isComplete)
    }

    func testExistingAcceptanceMustBeConfirmedAgainForCurrentPrivacyPolicy() async throws {
        let dataStore = InMemoryDataStore()
        let previous = AgreementConsent(
            acceptedDocumentIDs: Set(AgreementDocument.allCases.map(\.id)),
            confirmedVersion: AgreementConsent.currentVersion - 1,
            privacyDecision: .accepted,
            privacyPolicyVersion: AgreementConsent.currentPrivacyPolicyVersion - 1
        )
        try await dataStore.set(
            try JSONEncoder().encode(previous),
            forKey: AgreementConsentStore.storageKey
        )
        let store = AgreementConsentStore(store: dataStore)

        let loaded = try await store.load()
        XCTAssertFalse(loaded.isComplete)
        _ = try await store.setPrivacyDecision(.accepted)
        let renewed = try await store.confirmRequiredDocuments()

        XCTAssertTrue(renewed.isComplete)
        XCTAssertEqual(renewed.privacyPolicyVersion, AgreementConsent.currentPrivacyPolicyVersion)
    }
}
