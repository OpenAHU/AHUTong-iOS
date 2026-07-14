import CryptoKit
import Foundation

enum GuiXuPersistenceError: Error, LocalizedError, Equatable {
    case ffiDidNotReturn
    case invalidResponse
    case operationFailed(String)
    case corruptValue

    var errorDescription: String? {
        switch self {
        case .ffiDidNotReturn: "GuiXu FFI 未返回结果"
        case .invalidResponse: "GuiXu FFI 返回了无效数据"
        case let .operationFailed(message): "GuiXu 持久化失败：\(message)"
        case .corruptValue: "GuiXu 中的缓存数据已损坏"
        }
    }
}

private struct GuiXuFFIResponse<Value: Decodable>: Decodable {
    let ok: Bool
    let value: Value?
    let error: String?
}

actor RustPersistenceCoordinator {
    static let shared = RustPersistenceCoordinator()

    private var activeDatabasePath: String?

    func configure(databaseURL: URL) throws {
        let path = databaseURL.standardizedFileURL.path
        guard activeDatabasePath != path else { return }

        let pointer = path.withCString { pathPointer in
            "".withCString { seedPointer in
                ahutong_init_persistence(pathPointer, seedPointer, 0)
            }
        }
        try requireSuccess(pointer)
        activeDatabasePath = path

        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var databaseURL = databaseURL
        try? databaseURL.setResourceValues(values)
    }

    func put(box: String, key: String, value: String, databaseURL: URL) throws {
        try configure(databaseURL: databaseURL)
        let pointer = box.withCString { boxPointer in
            key.withCString { keyPointer in
                value.withCString { valuePointer in
                    ahutong_kv_put_string(boxPointer, keyPointer, valuePointer)
                }
            }
        }
        try requireSuccess(pointer)
    }

    func value(box: String, key: String, databaseURL: URL) throws -> String? {
        try configure(databaseURL: databaseURL)
        let pointer = box.withCString { boxPointer in
            key.withCString { keyPointer in
                ahutong_kv_get_string(boxPointer, keyPointer)
            }
        }
        return try decode(pointer, as: String.self)
    }

    func remove(box: String, key: String, databaseURL: URL) throws {
        try configure(databaseURL: databaseURL)
        let pointer = box.withCString { boxPointer in
            key.withCString { keyPointer in
                ahutong_kv_remove(boxPointer, keyPointer)
            }
        }
        try requireSuccess(pointer)
    }

    func clear(box: String, databaseURL: URL) throws {
        try configure(databaseURL: databaseURL)
        let pointer = box.withCString { boxPointer in
            ahutong_kv_clear_box(boxPointer)
        }
        try requireSuccess(pointer)
    }

    private func requireSuccess(_ pointer: UnsafeMutablePointer<CChar>?) throws {
        guard try decode(pointer, as: Bool.self) == true else {
            throw GuiXuPersistenceError.invalidResponse
        }
    }

    private func decode<Value: Decodable>(
        _ pointer: UnsafeMutablePointer<CChar>?,
        as type: Value.Type
    ) throws -> Value? {
        guard let pointer else { throw GuiXuPersistenceError.ffiDidNotReturn }
        defer { ahutong_free_string(pointer) }
        guard let data = String(validatingCString: pointer)?.data(using: .utf8),
              let response = try? JSONDecoder().decode(GuiXuFFIResponse<Value>.self, from: data) else {
            throw GuiXuPersistenceError.invalidResponse
        }
        guard response.ok else {
            throw GuiXuPersistenceError.operationFailed(response.error ?? "未知错误")
        }
        return response.value
    }
}

actor GuiXuDataStore: DataStore {
    static let defaultsBox = "swift_defaults_v1"
    static let fileCacheBox = "swift_file_cache_v1"

    private let databaseURL: URL
    private let box: String
    private let coordinator: RustPersistenceCoordinator

    init(
        databaseURL: URL = GuiXuDataStore.applicationDatabaseURL(),
        box: String = GuiXuDataStore.defaultsBox,
        coordinator: RustPersistenceCoordinator = .shared
    ) {
        self.databaseURL = databaseURL
        self.box = box
        self.coordinator = coordinator
    }

    func data(forKey key: String) async throws -> Data? {
        guard let encoded = try await coordinator.value(
            box: box,
            key: Self.hashedKey(key),
            databaseURL: databaseURL
        ) else {
            return nil
        }
        guard let data = Data(base64Encoded: encoded) else {
            try? await coordinator.remove(
                box: box,
                key: Self.hashedKey(key),
                databaseURL: databaseURL
            )
            throw GuiXuPersistenceError.corruptValue
        }
        return data
    }

    func set(_ data: Data, forKey key: String) async throws {
        try await coordinator.put(
            box: box,
            key: Self.hashedKey(key),
            value: data.base64EncodedString(),
            databaseURL: databaseURL
        )
    }

    func removeValue(forKey key: String) async throws {
        try await coordinator.remove(
            box: box,
            key: Self.hashedKey(key),
            databaseURL: databaseURL
        )
    }

    func clearAll() async throws {
        try await coordinator.clear(box: box, databaseURL: databaseURL)
    }

    static func applicationDatabaseURL() -> URL {
        let root = (try? FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )) ?? FileManager.default.temporaryDirectory
        return root
            .appendingPathComponent("AHUTong", isDirectory: true)
            .appendingPathComponent("Rust", isDirectory: true)
            .appendingPathComponent("GuiXu", isDirectory: true)
    }

    private static func hashedKey(_ key: String) -> String {
        SHA256.hash(data: Data(key.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }
}

actor MigratingDataStore: DataStore {
    private let primary: any DataStore
    private let legacy: any DataStore

    init(primary: any DataStore, legacy: any DataStore) {
        self.primary = primary
        self.legacy = legacy
    }

    func data(forKey key: String) async throws -> Data? {
        if let data = try await primary.data(forKey: key) {
            return data
        }
        guard let legacyData = try await legacy.data(forKey: key) else { return nil }
        try await primary.set(legacyData, forKey: key)
        try? await legacy.removeValue(forKey: key)
        return legacyData
    }

    func set(_ data: Data, forKey key: String) async throws {
        try await primary.set(data, forKey: key)
        try? await legacy.removeValue(forKey: key)
    }

    func removeValue(forKey key: String) async throws {
        try await primary.removeValue(forKey: key)
        try? await legacy.removeValue(forKey: key)
    }
}

enum AppPersistence {
    static func migratingDefaults() -> any DataStore {
        MigratingDataStore(
            primary: GuiXuDataStore(box: GuiXuDataStore.defaultsBox),
            legacy: UserDefaultsDataStore()
        )
    }

    static func migratingFileCache() -> any DataStore {
        let legacy: any DataStore
        if let fileStore = try? FileDataStore.applicationCache() {
            legacy = fileStore
        } else {
            legacy = InMemoryDataStore()
        }
        return MigratingDataStore(
            primary: GuiXuDataStore(box: GuiXuDataStore.fileCacheBox),
            legacy: legacy
        )
    }

    static func clearCaches() async {
        try? await GuiXuDataStore(box: GuiXuDataStore.defaultsBox).clearAll()
        try? await GuiXuDataStore(box: GuiXuDataStore.fileCacheBox).clearAll()
    }
}
