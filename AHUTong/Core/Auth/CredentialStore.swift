import Foundation

struct LoginCredentials: Codable, Equatable, Sendable {
    let studentID: String
    let password: String
}

enum StudentIDCanonicalizer {
    static func canonical(_ studentID: String) -> String {
        studentID
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased(with: Locale(identifier: "en_US_POSIX"))
    }
}

enum CredentialStoreError: Error, Equatable, Sendable {
    case invalidCredentials
}

struct CredentialStore: Sendable {
    private let secureStore: any SecureStore

    init(secureStore: any SecureStore = KeychainSecureStore()) {
        self.secureStore = secureStore
    }

    func save(_ credentials: LoginCredentials) async throws {
        let studentID = StudentIDCanonicalizer.canonical(credentials.studentID)
        guard !studentID.isEmpty, !credentials.password.isEmpty else {
            throw CredentialStoreError.invalidCredentials
        }
        let normalized = LoginCredentials(studentID: studentID, password: credentials.password)
        let data = try JSONEncoder().encode(normalized)
        try await secureStore.set(data, forAccount: account(for: studentID))
    }

    func credentials(for studentID: String) async throws -> LoginCredentials? {
        let normalizedID = StudentIDCanonicalizer.canonical(studentID)
        guard !normalizedID.isEmpty else {
            return nil
        }
        let canonicalAccount = account(for: normalizedID)
        if let data = try await secureStore.data(forAccount: canonicalAccount) {
            return try normalizedCredentials(from: data, canonicalID: normalizedID)
        }

        // Migrate the exact pre-canonical account when possible. If an old
        // snapshot and its credential account no longer have a discoverable
        // identity match, AppModel presents a one-time re-login message.
        let legacyID = studentID.trimmingCharacters(in: .whitespacesAndNewlines)
        let legacyAccount = account(for: legacyID)
        guard legacyAccount != canonicalAccount,
              let legacyData = try await secureStore.data(forAccount: legacyAccount) else {
            return nil
        }
        let credentials = try normalizedCredentials(from: legacyData, canonicalID: normalizedID)
        try await save(credentials)
        try await secureStore.removeValue(forAccount: legacyAccount)
        return credentials
    }

    func removeCredentials(for studentID: String) async throws {
        let normalizedID = StudentIDCanonicalizer.canonical(studentID)
        guard !normalizedID.isEmpty else {
            return
        }
        try await secureStore.removeValue(forAccount: account(for: normalizedID))
        let legacyID = studentID.trimmingCharacters(in: .whitespacesAndNewlines)
        if legacyID != normalizedID {
            try await secureStore.removeValue(forAccount: account(for: legacyID))
        }
    }

    private func account(for studentID: String) -> String {
        "login.\(studentID)"
    }

    private func normalizedCredentials(
        from data: Data,
        canonicalID: String
    ) throws -> LoginCredentials {
        let decoded = try JSONDecoder().decode(LoginCredentials.self, from: data)
        return LoginCredentials(studentID: canonicalID, password: decoded.password)
    }
}
