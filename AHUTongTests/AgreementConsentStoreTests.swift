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
}
