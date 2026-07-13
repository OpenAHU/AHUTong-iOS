import Foundation
import XCTest
@testable import AHUTong

final class FileDataStoreTests: XCTestCase {
    @MainActor
    func testFileStorePersistsUserScopedDataAcrossInstances() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("AHUTongTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let firstStore = UserScopedStore(
            store: FileDataStore(directory: directory),
            userID: "AB220001"
        )
        try await firstStore.set(Data("cached-course".utf8), forKey: "schedule.current")

        let reopenedStore = UserScopedStore(
            store: FileDataStore(directory: directory),
            userID: "AB220001"
        )
        let data = try await reopenedStore.data(forKey: "schedule.current")

        XCTAssertEqual(data, Data("cached-course".utf8))
    }

    @MainActor
    func testHashedFilesDoNotExposeStudentIDOrCacheKey() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("AHUTongTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = UserScopedStore(
            store: FileDataStore(directory: directory),
            userID: "AB220001"
        )
        try await store.set(Data("value".utf8), forKey: "schedule.2025-2026-1")

        let filenames = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        XCTAssertEqual(filenames.count, 1)
        XCTAssertFalse(filenames[0].contains("AB220001"))
        XCTAssertFalse(filenames[0].contains("schedule"))
    }
}
