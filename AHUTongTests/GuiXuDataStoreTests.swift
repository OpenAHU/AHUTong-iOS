import Foundation
import XCTest
@testable import AHUTong

final class GuiXuDataStoreTests: XCTestCase {
    func testPersistenceFailureMessageNeverIncludesFFIDetails() {
        let message = GuiXuPersistenceError.operationFailed.localizedDescription

        XCTAssertEqual(message, "GuiXu 持久化操作失败")
        XCTAssertFalse(message.contains("/private/"))
        XCTAssertFalse(message.contains("database"))
    }

    @MainActor
    func testGuiXuRoundTripReopenAccountIsolationAndClear() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("AHUTong-GuiXuTests-\(UUID().uuidString)", isDirectory: true)
        let firstURL = root.appendingPathComponent("first", isDirectory: true)
        let secondURL = root.appendingPathComponent("second", isDirectory: true)
        let box = "swift_test_\(UUID().uuidString.replacingOccurrences(of: "-", with: ""))"
        defer { try? FileManager.default.removeItem(at: root) }

        let first = GuiXuDataStore(databaseURL: firstURL, box: box)
        let scoped = UserScopedStore(store: first, userID: "AB220001")
        try await scoped.set(Data("cached-course".utf8), forKey: "schedule.current")

        let reopened = GuiXuDataStore(databaseURL: firstURL, box: box)
        let reopenedScoped = UserScopedStore(store: reopened, userID: "AB220001")
        let reopenedValue = try await reopenedScoped.data(forKey: "schedule.current")
        let otherUserValue = try await UserScopedStore(store: reopened, userID: "AB230001")
            .data(forKey: "schedule.current")
        XCTAssertEqual(reopenedValue, Data("cached-course".utf8))
        XCTAssertNil(otherUserValue)

        let second = GuiXuDataStore(databaseURL: secondURL, box: box)
        try await second.set(Data("second-database".utf8), forKey: "shared")
        let switchedBackValue = try await first.data(forKey: "users.AB220001.schedule.current")
        let isolatedDatabaseValue = try await first.data(forKey: "shared")
        XCTAssertEqual(switchedBackValue, Data("cached-course".utf8))
        XCTAssertNil(isolatedDatabaseValue)

        let persistedBytes = try FileManager.default
            .subpathsOfDirectory(atPath: firstURL.path)
            .compactMap { try? Data(contentsOf: firstURL.appendingPathComponent($0)) }
            .reduce(into: Data()) { $0.append($1) }
        XCTAssertNil(persistedBytes.range(of: Data("AB220001".utf8)))
        XCTAssertNil(persistedBytes.range(of: Data("schedule.current".utf8)))

        try await first.clearAll()
        let clearedValue = try await reopenedScoped.data(forKey: "schedule.current")
        XCTAssertNil(clearedValue)
    }

    @MainActor
    func testMigratingStoreMovesLegacyValueOnlyOnce() async throws {
        let primary = InMemoryDataStore()
        let legacy = InMemoryDataStore()
        let store = MigratingDataStore(primary: primary, legacy: legacy)
        let expected = Data("legacy".utf8)
        try await legacy.set(expected, forKey: "schedule")

        let migrated = try await store.data(forKey: "schedule")
        let primaryValue = try await primary.data(forKey: "schedule")
        let legacyValue = try await legacy.data(forKey: "schedule")
        XCTAssertEqual(migrated, expected)
        XCTAssertEqual(primaryValue, expected)
        XCTAssertNil(legacyValue)
    }
}
