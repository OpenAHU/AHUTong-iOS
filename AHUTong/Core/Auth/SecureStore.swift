import Foundation
import Security

protocol SecureStore: Sendable {
    func data(forAccount account: String) async throws -> Data?
    func set(_ data: Data, forAccount account: String) async throws
    func removeValue(forAccount account: String) async throws
}

enum SecureStoreError: Error, Equatable, Sendable {
    case unexpectedStatus(OSStatus)
    case invalidItem
}

actor KeychainSecureStore: SecureStore {
    private let service: String

    init(service: String = "com.openahu.ahutong.credentials") {
        self.service = service
    }

    func data(forAccount account: String) async throws -> Data? {
        var query = baseQuery(account: account)
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        query[kSecReturnData as String] = true

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess else {
            throw SecureStoreError.unexpectedStatus(status)
        }
        guard let data = item as? Data else {
            throw SecureStoreError.invalidItem
        }
        return data
    }

    func set(_ data: Data, forAccount account: String) async throws {
        let query = baseQuery(account: account)
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]

        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess {
            return
        }
        guard updateStatus == errSecItemNotFound else {
            throw SecureStoreError.unexpectedStatus(updateStatus)
        }

        var item = query
        attributes.forEach { item[$0.key] = $0.value }
        let addStatus = SecItemAdd(item as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw SecureStoreError.unexpectedStatus(addStatus)
        }
    }

    func removeValue(forAccount account: String) async throws {
        let status = SecItemDelete(baseQuery(account: account) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw SecureStoreError.unexpectedStatus(status)
        }
    }

    private func baseQuery(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }
}

actor InMemorySecureStore: SecureStore {
    private var values: [String: Data] = [:]

    func data(forAccount account: String) async throws -> Data? {
        values[account]
    }

    func set(_ data: Data, forAccount account: String) async throws {
        values[account] = data
    }

    func removeValue(forAccount account: String) async throws {
        values.removeValue(forKey: account)
    }
}
