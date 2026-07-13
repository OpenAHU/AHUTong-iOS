import Foundation

actor UserDefaultsDataStore: DataStore {
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func data(forKey key: String) async throws -> Data? {
        defaults.data(forKey: key)
    }

    func set(_ data: Data, forKey key: String) async throws {
        defaults.set(data, forKey: key)
    }

    func removeValue(forKey key: String) async throws {
        defaults.removeObject(forKey: key)
    }
}
