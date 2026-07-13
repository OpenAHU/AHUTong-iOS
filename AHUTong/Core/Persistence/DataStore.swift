import Foundation

protocol DataStore: Sendable {
    func data(forKey key: String) async throws -> Data?
    func set(_ data: Data, forKey key: String) async throws
    func removeValue(forKey key: String) async throws
}

actor InMemoryDataStore: DataStore {
    private var values: [String: Data] = [:]

    func data(forKey key: String) async throws -> Data? {
        values[key]
    }

    func set(_ data: Data, forKey key: String) async throws {
        values[key] = data
    }

    func removeValue(forKey key: String) async throws {
        values.removeValue(forKey: key)
    }
}

struct UserScopedStore: Sendable {
    private let store: any DataStore
    private let userID: String

    init(store: any DataStore, userID: String) {
        let normalizedUserID = userID.trimmingCharacters(in: .whitespacesAndNewlines)
        precondition(!normalizedUserID.isEmpty)
        self.store = store
        self.userID = normalizedUserID
    }

    func data(forKey key: String) async throws -> Data? {
        try await store.data(forKey: namespaced(key))
    }

    func set(_ data: Data, forKey key: String) async throws {
        try await store.set(data, forKey: namespaced(key))
    }

    func removeValue(forKey key: String) async throws {
        try await store.removeValue(forKey: namespaced(key))
    }

    private func namespaced(_ key: String) -> String {
        "users.\(userID).\(key)"
    }
}

struct JSONStore<Value: Codable & Sendable>: Sendable {
    private let store: UserScopedStore
    private let key: String

    init(store: UserScopedStore, key: String) {
        self.store = store
        self.key = key
    }

    func load() async throws -> Value? {
        guard let data = try await store.data(forKey: key) else {
            return nil
        }
        return try JSONDecoder().decode(Value.self, from: data)
    }

    func save(_ value: Value) async throws {
        let data = try JSONEncoder().encode(value)
        try await store.set(data, forKey: key)
    }

    func remove() async throws {
        try await store.removeValue(forKey: key)
    }
}
