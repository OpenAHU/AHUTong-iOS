import Foundation

struct LoginCredentials: Codable, Equatable, Sendable {
    let studentID: String
    let password: String
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
        let studentID = credentials.studentID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !studentID.isEmpty, !credentials.password.isEmpty else {
            throw CredentialStoreError.invalidCredentials
        }
        let normalized = LoginCredentials(studentID: studentID, password: credentials.password)
        let data = try JSONEncoder().encode(normalized)
        try await secureStore.set(data, forAccount: account(for: studentID))
    }

    func credentials(for studentID: String) async throws -> LoginCredentials? {
        let normalizedID = studentID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedID.isEmpty else {
            return nil
        }
        guard let data = try await secureStore.data(forAccount: account(for: normalizedID)) else {
            return nil
        }
        return try JSONDecoder().decode(LoginCredentials.self, from: data)
    }

    func removeCredentials(for studentID: String) async throws {
        let normalizedID = studentID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedID.isEmpty else {
            return
        }
        try await secureStore.removeValue(forAccount: account(for: normalizedID))
    }

    private func account(for studentID: String) -> String {
        "login.\(studentID)"
    }
}
