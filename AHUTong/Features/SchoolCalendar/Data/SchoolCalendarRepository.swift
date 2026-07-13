import Foundation

protocol SchoolCalendarRemoteDataSource: Sendable {
    func fetchCalendar() async throws -> Data
}

protocol SchoolCalendarCaching: Sendable {
    func load() async throws -> URL?
    func save(_ data: Data) async throws -> URL
    func remove() async throws
}

enum SchoolCalendarLoadPolicy: Sendable {
    case cacheFirst
    case refresh
}

enum SchoolCalendarSnapshotSource: String, Equatable, Sendable {
    case cache
    case remote
    case staleCache
}

struct SchoolCalendarSnapshot: Equatable, Sendable {
    let fileURL: URL
    let source: SchoolCalendarSnapshotSource
}

enum SchoolCalendarRepositoryError: Error, Equatable, Sendable {
    case invalidImage
}

struct OpenAHUSchoolCalendarRemote: SchoolCalendarRemoteDataSource {
    static let endpoint = URL(string: "https://openahu.org/download/xiaoli.jpg")!

    private let transport: any NetworkTransport

    init(transport: any NetworkTransport = URLSessionTransport()) {
        self.transport = transport
    }

    func fetchCalendar() async throws -> Data {
        var request = URLRequest(url: Self.endpoint)
        request.timeoutInterval = 30
        request.setValue("AHUTong-iOS/0.1", forHTTPHeaderField: "User-Agent")
        request.setValue("image/*", forHTTPHeaderField: "Accept")
        let (data, response) = try await transport.data(for: request)
        guard (200..<300).contains(response.statusCode) else {
            throw NetworkError.unacceptableStatusCode(response.statusCode)
        }
        return data
    }
}

actor SchoolCalendarFileCache: SchoolCalendarCaching {
    private let directory: URL
    private let fileManager: FileManager

    init(directory: URL, fileManager: FileManager = .default) {
        self.directory = directory
        self.fileManager = fileManager
    }

    static func live() -> SchoolCalendarFileCache {
        let fileManager = FileManager.default
        let root = (try? fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )) ?? fileManager.temporaryDirectory
        return SchoolCalendarFileCache(
            directory: root
                .appendingPathComponent("AHUTong", isDirectory: true)
                .appendingPathComponent("SchoolCalendar", isDirectory: true)
        )
    }

    func load() async throws -> URL? {
        let url = fileURL
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        let data = try Data(contentsOf: url)
        guard SchoolCalendarImageFormat.isSupported(data) else {
            try? fileManager.removeItem(at: url)
            return nil
        }
        return url
    }

    func save(_ data: Data) async throws -> URL {
        try fileManager.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        try data.write(to: fileURL, options: .atomic)
        return fileURL
    }

    func remove() async throws {
        guard fileManager.fileExists(atPath: fileURL.path) else { return }
        try fileManager.removeItem(at: fileURL)
    }

    private var fileURL: URL {
        directory.appendingPathComponent("xiaoli.jpg")
    }
}

enum SchoolCalendarImageFormat {
    static func isSupported(_ data: Data) -> Bool {
        let bytes = [UInt8](data.prefix(8))
        let isJPEG = bytes.count >= 3
            && bytes[0] == 0xFF && bytes[1] == 0xD8 && bytes[2] == 0xFF
        let pngSignature: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]
        return isJPEG || bytes == pngSignature
    }
}

struct SchoolCalendarRepository: Sendable {
    private let remote: any SchoolCalendarRemoteDataSource
    private let cache: any SchoolCalendarCaching

    init(
        remote: any SchoolCalendarRemoteDataSource,
        cache: any SchoolCalendarCaching
    ) {
        self.remote = remote
        self.cache = cache
    }

    static func live() -> SchoolCalendarRepository {
        SchoolCalendarRepository(
            remote: OpenAHUSchoolCalendarRemote(),
            cache: SchoolCalendarFileCache.live()
        )
    }

    func load(
        policy: SchoolCalendarLoadPolicy = .cacheFirst
    ) async throws -> SchoolCalendarSnapshot {
        let cachedURL = try? await cache.load()
        if policy == .cacheFirst, let cachedURL {
            return SchoolCalendarSnapshot(fileURL: cachedURL, source: .cache)
        }

        do {
            let data = try await remote.fetchCalendar()
            guard SchoolCalendarImageFormat.isSupported(data) else {
                throw SchoolCalendarRepositoryError.invalidImage
            }
            let url = try await cache.save(data)
            return SchoolCalendarSnapshot(fileURL: url, source: .remote)
        } catch {
            if let cachedURL {
                return SchoolCalendarSnapshot(fileURL: cachedURL, source: .staleCache)
            }
            throw error
        }
    }
}
