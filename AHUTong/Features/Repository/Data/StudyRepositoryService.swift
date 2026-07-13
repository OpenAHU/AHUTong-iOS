import CryptoKit
import Foundation

protocol RepositoryContentRemoteDataSource: Sendable {
    func fetchContents(
        repository: StudyRepositoryConfiguration,
        path: String
    ) async throws -> [GitHubContentItem]
}

protocol RepositoryFileRemoteDataSource: Sendable {
    func download(
        from url: URL,
        progress: @escaping @Sendable (Double) async -> Void
    ) async throws -> Data
}

protocol RepositoryDownloadStoring: Sendable {
    func save(
        _ data: Data,
        repositoryID: String,
        path: String
    ) async throws -> DownloadedStudyFile
    func files() async throws -> [DownloadedStudyFile]
    func delete(ids: Set<String>) async throws
}

struct GitHubRepositoryContentRemote: RepositoryContentRemoteDataSource {
    private let transport: any NetworkTransport

    init(transport: any NetworkTransport = URLSessionTransport()) {
        self.transport = transport
    }

    func fetchContents(
        repository: StudyRepositoryConfiguration,
        path: String
    ) async throws -> [GitHubContentItem] {
        var url = URL(string: "https://api.github.com")!
        for component in ["repos", repository.owner, repository.repository, "contents"] {
            url.appendPathComponent(component)
        }
        for component in path.split(separator: "/") {
            url.appendPathComponent(String(component))
        }
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            throw NetworkError.invalidURL
        }
        components.queryItems = [URLQueryItem(name: "ref", value: repository.branch)]
        guard let requestURL = components.url else { throw NetworkError.invalidURL }

        var request = URLRequest(url: requestURL)
        request.timeoutInterval = 20
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("AHUTong-iOS/0.1", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await transport.data(for: request)
        guard (200..<300).contains(response.statusCode) else {
            throw NetworkError.unacceptableStatusCode(response.statusCode)
        }
        do {
            return try JSONDecoder().decode([GitHubContentItem].self, from: data)
        } catch {
            throw NetworkError.decodingFailed
        }
    }
}

struct URLSessionRepositoryFileRemote: RepositoryFileRemoteDataSource {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func download(
        from url: URL,
        progress: @escaping @Sendable (Double) async -> Void
    ) async throws -> Data {
        var request = URLRequest(url: url)
        request.timeoutInterval = 120
        request.setValue("AHUTong-iOS/0.1", forHTTPHeaderField: "User-Agent")
        await progress(0)

        let (bytes, response) = try await session.bytes(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NetworkError.nonHTTPResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw NetworkError.unacceptableStatusCode(httpResponse.statusCode)
        }

        let expected = max(response.expectedContentLength, 0)
        var data = Data()
        if expected > 0, expected <= Int64(Int.max) {
            data.reserveCapacity(Int(expected))
        }
        var lastReportedCount = 0
        for try await byte in bytes {
            try Task.checkCancellation()
            data.append(byte)
            if data.count - lastReportedCount >= 64 * 1024 {
                lastReportedCount = data.count
                if expected > 0 {
                    await progress(min(Double(data.count) / Double(expected), 1))
                }
            }
        }
        await progress(1)
        return data
    }
}

actor RepositoryDownloadFileStore: RepositoryDownloadStoring {
    private let directory: URL
    private let fileManager: FileManager

    init(directory: URL, fileManager: FileManager = .default) {
        self.directory = directory
        self.fileManager = fileManager
    }

    static func live() -> RepositoryDownloadFileStore {
        let fileManager = FileManager.default
        let root = (try? fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )) ?? fileManager.temporaryDirectory
        return RepositoryDownloadFileStore(
            directory: root
                .appendingPathComponent("AHUTong", isDirectory: true)
                .appendingPathComponent("Repository", isDirectory: true)
        )
    }

    func save(
        _ data: Data,
        repositoryID: String,
        path: String
    ) async throws -> DownloadedStudyFile {
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let fileURL = directory.appendingPathComponent(localFilename(repositoryID: repositoryID, path: path))
        try data.write(to: fileURL, options: .atomic)

        var records = try loadRecords()
        records.removeAll { $0.repositoryID == repositoryID && $0.path == path }
        let record = DownloadedStudyFile(
            repositoryID: repositoryID,
            path: path,
            name: URL(fileURLWithPath: path).lastPathComponent,
            localURL: fileURL,
            size: Int64(data.count),
            downloadedAt: Date()
        )
        records.append(record)
        try saveRecords(records)
        return record
    }

    func files() async throws -> [DownloadedStudyFile] {
        var records = try loadRecords()
        let existing = records.filter { fileManager.fileExists(atPath: $0.localURL.path) }
        if existing.count != records.count {
            records = existing
            try saveRecords(records)
        }
        return records.sorted { $0.downloadedAt > $1.downloadedAt }
    }

    func delete(ids: Set<String>) async throws {
        var records = try loadRecords()
        let targets = records.filter { ids.contains($0.id) }
        for target in targets where fileManager.fileExists(atPath: target.localURL.path) {
            try fileManager.removeItem(at: target.localURL)
        }
        records.removeAll { ids.contains($0.id) }
        try saveRecords(records)
    }

    private var indexURL: URL {
        directory.appendingPathComponent("downloads.json")
    }

    private func loadRecords() throws -> [DownloadedStudyFile] {
        guard fileManager.fileExists(atPath: indexURL.path) else { return [] }
        do {
            return try JSONDecoder().decode(
                [DownloadedStudyFile].self,
                from: Data(contentsOf: indexURL)
            )
        } catch {
            try? fileManager.removeItem(at: indexURL)
            return []
        }
    }

    private func saveRecords(_ records: [DownloadedStudyFile]) throws {
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        try JSONEncoder().encode(records).write(to: indexURL, options: .atomic)
    }

    private func localFilename(repositoryID: String, path: String) -> String {
        let digest = SHA256.hash(data: Data("\(repositoryID):\(path)".utf8))
            .map { String(format: "%02x", $0) }
            .joined()
        let extensionName = URL(fileURLWithPath: path).pathExtension
        return extensionName.isEmpty ? digest : "\(digest).\(extensionName)"
    }
}

struct StudyRepositoryService: Sendable {
    private let contentRemote: any RepositoryContentRemoteDataSource
    private let fileRemote: any RepositoryFileRemoteDataSource
    private let cache: any DataStore
    private let downloads: any RepositoryDownloadStoring

    init(
        contentRemote: any RepositoryContentRemoteDataSource,
        fileRemote: any RepositoryFileRemoteDataSource,
        cache: any DataStore,
        downloads: any RepositoryDownloadStoring
    ) {
        self.contentRemote = contentRemote
        self.fileRemote = fileRemote
        self.cache = cache
        self.downloads = downloads
    }

    static func live() -> StudyRepositoryService {
        let cache: any DataStore
        do {
            cache = try FileDataStore.applicationCache()
        } catch {
            cache = InMemoryDataStore()
        }
        return StudyRepositoryService(
            contentRemote: GitHubRepositoryContentRemote(),
            fileRemote: URLSessionRepositoryFileRemote(),
            cache: cache,
            downloads: RepositoryDownloadFileStore.live()
        )
    }

    func loadDirectory(
        repositoryID: String,
        path: String,
        policy: RepositoryLoadPolicy = .cacheFirst
    ) async throws -> RepositoryDirectorySnapshot {
        guard let repository = StudyRepositoryCatalog.repository(id: repositoryID) else {
            throw StudyRepositoryError.unknownRepository
        }
        let key = cacheKey(repositoryID: repositoryID, path: path)
        let cached = await loadCacheRecoveringCorruption(key: key)
        if policy == .cacheFirst, let cached {
            return RepositoryDirectorySnapshot(
                items: cached.items,
                source: .cache,
                updatedAt: cached.updatedAt
            )
        }

        do {
            let fetched = try await contentRemote.fetchContents(
                repository: repository,
                path: path
            )
            let items = fetched.sorted(by: Self.contentOrder)
            let entry = RepositoryDirectoryCacheEntry(items: items, updatedAt: Date())
            try await cache.set(JSONEncoder().encode(entry), forKey: key)
            return RepositoryDirectorySnapshot(
                items: items,
                source: .remote,
                updatedAt: entry.updatedAt
            )
        } catch {
            if let cached {
                return RepositoryDirectorySnapshot(
                    items: cached.items,
                    source: .staleCache,
                    updatedAt: cached.updatedAt
                )
            }
            throw error
        }
    }

    func download(
        repositoryID: String,
        item: GitHubContentItem,
        progress: @escaping @Sendable (Double) async -> Void
    ) async throws -> DownloadedStudyFile {
        guard !item.isDirectory,
              let repository = StudyRepositoryCatalog.repository(id: repositoryID) else {
            throw StudyRepositoryError.unknownRepository
        }
        var urls = repository.downloadURLs(for: item.path)
        if let downloadURL = item.downloadURL, !urls.contains(downloadURL) {
            urls.append(downloadURL)
        }

        for url in urls {
            do {
                let data = try await fileRemote.download(from: url, progress: progress)
                guard !data.isEmpty else { throw StudyRepositoryError.emptyDownload }
                return try await downloads.save(
                    data,
                    repositoryID: repositoryID,
                    path: item.path
                )
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                continue
            }
        }
        throw StudyRepositoryError.downloadFailed
    }

    func downloadedFiles() async throws -> [DownloadedStudyFile] {
        try await downloads.files()
    }

    func deleteDownloadedFiles(ids: Set<String>) async throws {
        try await downloads.delete(ids: ids)
    }

    private func loadCacheRecoveringCorruption(
        key: String
    ) async -> RepositoryDirectoryCacheEntry? {
        do {
            guard let data = try await cache.data(forKey: key) else { return nil }
            return try JSONDecoder().decode(RepositoryDirectoryCacheEntry.self, from: data)
        } catch {
            try? await cache.removeValue(forKey: key)
            return nil
        }
    }

    private func cacheKey(repositoryID: String, path: String) -> String {
        "repository.contents.\(repositoryID).\(path.isEmpty ? "root" : path)"
    }

    private static func contentOrder(_ lhs: GitHubContentItem, _ rhs: GitHubContentItem) -> Bool {
        if lhs.isDirectory != rhs.isDirectory { return lhs.isDirectory }
        return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
    }
}
