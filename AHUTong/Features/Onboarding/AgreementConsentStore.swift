import Foundation

protocol AgreementConsentStoring: Sendable {
    func load() async throws -> AgreementConsent
    func setAccepted(_ accepted: Bool, document: AgreementDocument) async throws -> AgreementConsent
    func confirmRequiredDocuments() async throws -> AgreementConsent
    func reset() async throws
}

actor AgreementConsentStore: AgreementConsentStoring {
    static let storageKey = "onboarding.agreement-consent.v1"

    private let store: any DataStore

    init(store: any DataStore) {
        self.store = store
    }

    func load() async throws -> AgreementConsent {
        guard let data = try await store.data(forKey: Self.storageKey) else {
            return .empty
        }
        do {
            return try JSONDecoder().decode(AgreementConsent.self, from: data)
        } catch {
            try await store.removeValue(forKey: Self.storageKey)
            return .empty
        }
    }

    func setAccepted(
        _ accepted: Bool,
        document: AgreementDocument
    ) async throws -> AgreementConsent {
        var consent = try await load()
        if accepted {
            consent.acceptedDocumentIDs.insert(document.id)
        } else {
            consent.acceptedDocumentIDs.remove(document.id)
        }
        if document.isRequired {
            consent.confirmedVersion = nil
        }
        let data = try JSONEncoder().encode(consent)
        try await store.set(data, forKey: Self.storageKey)
        return consent
    }

    func confirmRequiredDocuments() async throws -> AgreementConsent {
        var consent = try await load()
        guard consent.hasAcceptedRequiredDocuments else {
            return consent
        }
        consent.confirmedVersion = AgreementConsent.currentVersion
        let data = try JSONEncoder().encode(consent)
        try await store.set(data, forKey: Self.storageKey)
        return consent
    }

    func reset() async throws {
        try await store.removeValue(forKey: Self.storageKey)
    }
}
