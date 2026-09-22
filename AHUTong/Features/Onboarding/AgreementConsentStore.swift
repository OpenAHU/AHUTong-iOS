import Foundation

protocol AgreementConsentStoring: Sendable {
    func load() async throws -> AgreementConsent
    func setAccepted(_ accepted: Bool, document: AgreementDocument) async throws -> AgreementConsent
    func setPrivacyDecision(_ decision: PrivacyConsentDecision) async throws -> AgreementConsent
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
        if document == .privacy {
            return try await setPrivacyDecision(accepted ? .accepted : .declined)
        }
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

    func setPrivacyDecision(_ decision: PrivacyConsentDecision) async throws -> AgreementConsent {
        var consent = try await load()
        consent.privacyDecision = decision
        consent.privacyPolicyVersion = AgreementConsent.currentPrivacyPolicyVersion
        consent.confirmedVersion = nil
        if decision == .accepted {
            consent.acceptedDocumentIDs.insert(AgreementDocument.privacy.id)
        } else {
            consent.acceptedDocumentIDs.remove(AgreementDocument.privacy.id)
        }
        try await store.set(try JSONEncoder().encode(consent), forKey: Self.storageKey)
        return consent
    }

    func confirmRequiredDocuments() async throws -> AgreementConsent {
        var consent = try await load()
        guard consent.hasResolvedRequiredDocuments else {
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
