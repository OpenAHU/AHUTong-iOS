import Foundation
import XCTest
@testable import AHUTong

final class SchoolCalendarRepositoryTests: XCTestCase {
    @MainActor
    func testViewModelReportsPhotoSaveCompletion() async {
        let saver = CalendarPhotoSaverStub()
        let model = SchoolCalendarViewModel(photoSaver: saver)
        let fileURL = URL(fileURLWithPath: "/tmp/xiaoli.jpg")

        await model.savePhoto(at: fileURL)
        let savedURLs = await saver.savedURLs

        XCTAssertEqual(model.saveMessage, "校历已保存到系统照片")
        XCTAssertEqual(savedURLs, [fileURL])
    }

    @MainActor
    func testCacheFirstDownloadsThenUsesCache() async throws {
        let remote = CalendarRemoteStub(data: Self.jpeg)
        let cache = CalendarCacheStub()
        let repository = SchoolCalendarRepository(remote: remote, cache: cache)

        let first = try await repository.load()
        let second = try await repository.load()

        let fetchCount = await remote.count
        XCTAssertEqual(first.source, .remote)
        XCTAssertEqual(second.source, .cache)
        XCTAssertEqual(fetchCount, 1)
    }

    @MainActor
    func testRefreshFailureFallsBackToStaleCache() async throws {
        let remote = CalendarRemoteStub(data: Self.jpeg)
        let cache = CalendarCacheStub()
        let repository = SchoolCalendarRepository(remote: remote, cache: cache)
        _ = try await repository.load()
        await remote.failNextRequest()

        let snapshot = try await repository.load(policy: .refresh)

        XCTAssertEqual(snapshot.source, .staleCache)
    }

    @MainActor
    func testInvalidRemoteImageIsRejectedAndNotCached() async {
        let cache = CalendarCacheStub()
        let repository = SchoolCalendarRepository(
            remote: CalendarRemoteStub(data: Data("not an image".utf8)),
            cache: cache
        )

        do {
            _ = try await repository.load()
            XCTFail("Expected an invalid image error")
        } catch {
            let cachedURL = await cache.url
            XCTAssertEqual(error as? SchoolCalendarRepositoryError, .invalidImage)
            XCTAssertNil(cachedURL)
        }
    }

    @MainActor
    func testFileCacheRemovesCorruptFile() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try Data("broken".utf8).write(to: directory.appendingPathComponent("xiaoli.jpg"))
        let cache = SchoolCalendarFileCache(directory: directory)

        let result = try await cache.load()

        XCTAssertNil(result)
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: directory.appendingPathComponent("xiaoli.jpg").path
            )
        )
    }

    private static let jpeg = Data([0xFF, 0xD8, 0xFF, 0xE0, 0x00])
}

private actor CalendarRemoteStub: SchoolCalendarRemoteDataSource {
    enum Failure: Error { case unavailable }

    let data: Data
    private(set) var count = 0
    private var shouldFail = false

    init(data: Data) {
        self.data = data
    }

    func fetchCalendar() async throws -> Data {
        count += 1
        if shouldFail { throw Failure.unavailable }
        return data
    }

    func failNextRequest() {
        shouldFail = true
    }
}

private actor CalendarCacheStub: SchoolCalendarCaching {
    private(set) var url: URL?

    func load() async throws -> URL? { url }

    func save(_ data: Data) async throws -> URL {
        let savedURL = URL(fileURLWithPath: "/tmp/xiaoli.jpg")
        url = savedURL
        return savedURL
    }

    func remove() async throws {
        url = nil
    }
}

private actor CalendarPhotoSaverStub: SchoolCalendarPhotoSaving {
    private(set) var savedURLs: [URL] = []

    func saveImage(at fileURL: URL) async throws {
        savedURLs.append(fileURL)
    }
}
