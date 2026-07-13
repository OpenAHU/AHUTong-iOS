import CryptoKit
import Foundation

actor FileDataStore: DataStore {
    private let directory: URL
    private let fileManager = FileManager.default

    init(directory: URL) {
        self.directory = directory
    }

    static func applicationCache() throws -> FileDataStore {
        let root = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directory = root
            .appendingPathComponent("AHUTong", isDirectory: true)
            .appendingPathComponent("Cache", isDirectory: true)
        return FileDataStore(directory: directory)
    }

    func data(forKey key: String) async throws -> Data? {
        let url = fileURL(forKey: key)
        guard fileManager.fileExists(atPath: url.path) else {
            return nil
        }
        return try Data(contentsOf: url)
    }

    func set(_ data: Data, forKey key: String) async throws {
        try fileManager.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        try data.write(to: fileURL(forKey: key), options: .atomic)
    }

    func removeValue(forKey key: String) async throws {
        let url = fileURL(forKey: key)
        guard fileManager.fileExists(atPath: url.path) else {
            return
        }
        try fileManager.removeItem(at: url)
    }

    private func fileURL(forKey key: String) -> URL {
        let digest = SHA256.hash(data: Data(key.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
        return directory.appendingPathComponent(digest).appendingPathExtension("cache")
    }
}
