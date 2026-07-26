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
    func download(
        from url: URL,
        headers: [String: String],
        progress: @escaping @Sendable (Double) async -> Void
    ) async throws -> Data
    func downloadToTemporaryFile(
        from url: URL,
        progress: @escaping @Sendable (Double) async -> Void
    ) async throws -> URL
    func downloadToTemporaryFile(
        from url: URL,
        headers: [String: String],
        progress: @escaping @Sendable (Double) async -> Void
    ) async throws -> URL
}

extension RepositoryFileRemoteDataSource {
    func download(
        from url: URL,
        headers: [String: String],
        progress: @escaping @Sendable (Double) async -> Void
    ) async throws -> Data {
        try await download(from: url, progress: progress)
    }

    func downloadToTemporaryFile(
        from url: URL,
        progress: @escaping @Sendable (Double) async -> Void
    ) async throws -> URL {
        let data = try await download(from: url, progress: progress)
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try data.write(to: file, options: .atomic)
        return file
    }

    func downloadToTemporaryFile(
        from url: URL,
        headers: [String: String],
        progress: @escaping @Sendable (Double) async -> Void
    ) async throws -> URL {
        let data = try await download(from: url, headers: headers, progress: progress)
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try data.write(to: file, options: .atomic)
        return file
    }
}

protocol RepositoryGitLFSRemoteDataSource: Sendable {
    func resolveDownload(
        repository: StudyRepositoryConfiguration,
        pointer: RepositoryGitLFSPointer
    ) async throws -> RepositoryGitLFSDownload?
}

protocol RepositoryDownloadStoring: Sendable {
    func save(
        _ data: Data,
        repositoryID: String,
        path: String
    ) async throws -> DownloadedStudyFile
    func saveFile(
        at sourceURL: URL,
        repositoryID: String,
        path: String
    ) async throws -> DownloadedStudyFile
    func files() async throws -> [DownloadedStudyFile]
    func delete(ids: Set<String>) async throws
}

extension RepositoryDownloadStoring {
    func saveFile(
        at sourceURL: URL,
        repositoryID: String,
        path: String
    ) async throws -> DownloadedStudyFile {
        try await save(Data(contentsOf: sourceURL), repositoryID: repositoryID, path: path)
    }
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

struct GitHubRepositoryGitLFSRemote: RepositoryGitLFSRemoteDataSource {
    private let transport: any NetworkTransport

    init(transport: any NetworkTransport = URLSessionTransport()) {
        self.transport = transport
    }

    func resolveDownload(
        repository: StudyRepositoryConfiguration,
        pointer: RepositoryGitLFSPointer
    ) async throws -> RepositoryGitLFSDownload? {
        let payload = GitLFSBatchRequest(
            objects: [GitLFSBatchObject(oid: pointer.oid, size: pointer.size)]
        )
        var request = URLRequest(url: repository.gitLFSBatchURL)
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.httpBody = try JSONEncoder().encode(payload)
        request.setValue("application/vnd.git-lfs+json", forHTTPHeaderField: "Accept")
        request.setValue("application/vnd.git-lfs+json", forHTTPHeaderField: "Content-Type")
        request.setValue("AHUTong-iOS/0.1", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await transport.data(for: request)
        guard (200..<300).contains(response.statusCode) else {
            throw NetworkError.unacceptableStatusCode(response.statusCode)
        }
        let batchResponse: GitLFSBatchResponse
        do {
            batchResponse = try JSONDecoder().decode(GitLFSBatchResponse.self, from: data)
        } catch {
            throw NetworkError.decodingFailed
        }
        guard let action = batchResponse.objects
            .first(where: { $0.oid.caseInsensitiveCompare(pointer.oid) == .orderedSame })?
            .actions?
            .download,
            let url = URL(string: action.href),
            url.scheme?.lowercased() == "https" else {
            return nil
        }
        return RepositoryGitLFSDownload(url: url, headers: action.header ?? [:])
    }
}

private struct GitLFSBatchRequest: Encodable {
    let operation = "download"
    let transfers = ["basic"]
    let objects: [GitLFSBatchObject]
}

private struct GitLFSBatchObject: Codable {
    let oid: String
    let size: Int64
}

private struct GitLFSBatchResponse: Decodable {
    let objects: [GitLFSBatchResponseObject]
}

private struct GitLFSBatchResponseObject: Decodable {
    let oid: String
    let actions: GitLFSBatchActions?
}

private struct GitLFSBatchActions: Decodable {
    let download: GitLFSBatchDownloadAction?
}

private struct GitLFSBatchDownloadAction: Decodable {
    let href: String
    let header: [String: String]?
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
        try await download(from: url, headers: [:], progress: progress)
    }

    func download(
        from url: URL,
        headers: [String: String],
        progress: @escaping @Sendable (Double) async -> Void
    ) async throws -> Data {
        var request = URLRequest(url: url)
        request.timeoutInterval = 120
        request.setValue("AHUTong-iOS/0.1", forHTTPHeaderField: "User-Agent")
        headers.forEach { request.setValue($0.value, forHTTPHeaderField: $0.key) }
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

    func downloadToTemporaryFile(
        from url: URL,
        progress: @escaping @Sendable (Double) async -> Void
    ) async throws -> URL {
        try await downloadToTemporaryFile(from: url, headers: [:], progress: progress)
    }

    func downloadToTemporaryFile(
        from url: URL,
        headers: [String: String],
        progress: @escaping @Sendable (Double) async -> Void
    ) async throws -> URL {
        var request = URLRequest(url: url)
        request.timeoutInterval = 120
        request.setValue("AHUTong-iOS/0.1", forHTTPHeaderField: "User-Agent")
        headers.forEach { request.setValue($0.value, forHTTPHeaderField: $0.key) }
        await progress(0)
        let (fileURL, response) = try await session.download(for: request)
        guard let httpResponse = response as? HTTPURLResponse else { throw NetworkError.nonHTTPResponse }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw NetworkError.unacceptableStatusCode(httpResponse.statusCode)
        }
        await progress(1)
        return fileURL
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

    func saveFile(
        at sourceURL: URL,
        repositoryID: String,
        path: String
    ) async throws -> DownloadedStudyFile {
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let fileURL = directory.appendingPathComponent(localFilename(repositoryID: repositoryID, path: path))
        if fileManager.fileExists(atPath: fileURL.path) { try fileManager.removeItem(at: fileURL) }
        do {
            try fileManager.moveItem(at: sourceURL, to: fileURL)
        } catch {
            try fileManager.copyItem(at: sourceURL, to: fileURL)
            try? fileManager.removeItem(at: sourceURL)
        }
        let attributes = try fileManager.attributesOfItem(atPath: fileURL.path)
        let size = (attributes[.size] as? NSNumber)?.int64Value ?? 0
        guard size > 0 else { throw StudyRepositoryError.emptyDownload }
        var records = try loadRecords()
        records.removeAll { $0.repositoryID == repositoryID && $0.path == path }
        let record = DownloadedStudyFile(
            repositoryID: repositoryID,
            path: path,
            name: URL(fileURLWithPath: path).lastPathComponent,
            localURL: fileURL,
            size: size,
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
    private let gitLFSRemote: any RepositoryGitLFSRemoteDataSource
    private let cache: any DataStore
    private let downloads: any RepositoryDownloadStoring

    init(
        contentRemote: any RepositoryContentRemoteDataSource,
        fileRemote: any RepositoryFileRemoteDataSource,
        gitLFSRemote: any RepositoryGitLFSRemoteDataSource = GitHubRepositoryGitLFSRemote(),
        cache: any DataStore,
        downloads: any RepositoryDownloadStoring
    ) {
        self.contentRemote = contentRemote
        self.fileRemote = fileRemote
        self.gitLFSRemote = gitLFSRemote
        self.cache = cache
        self.downloads = downloads
    }

    static func live() -> StudyRepositoryService {
        return StudyRepositoryService(
            contentRemote: GitHubRepositoryContentRemote(),
            fileRemote: URLSessionRepositoryFileRemote(),
            gitLFSRemote: GitHubRepositoryGitLFSRemote(),
            cache: AppPersistence.migratingFileCache(),
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
        accelerationSource: RepositoryAccelerationSource = RepositoryAccelerationPreferences.defaultSource,
        progress: @escaping @Sendable (Double) async -> Void
    ) async throws -> DownloadedStudyFile {
        guard !item.isDirectory,
              let repository = StudyRepositoryCatalog.repository(id: repositoryID) else {
            throw StudyRepositoryError.unknownRepository
        }
        let temporaryURL = try await fetchTemporaryFile(
            repository: repository,
            item: item,
            accelerationSource: accelerationSource,
            progress: progress
        )
        return try await downloads.saveFile(
            at: temporaryURL,
            repositoryID: repositoryID,
            path: item.path
        )
    }

    func loadRemoteMarkdown(
        repositoryID: String,
        item: GitHubContentItem,
        accelerationSource: RepositoryAccelerationSource = RepositoryAccelerationPreferences.defaultSource
    ) async throws -> RepositoryMarkdownDocument {
        guard !item.isDirectory,
              RepositoryMarkdownSupport.isMarkdownFile(item.name),
              let repository = StudyRepositoryCatalog.repository(id: repositoryID) else {
            throw StudyRepositoryError.invalidMarkdown
        }
        let temporaryURL = try await fetchTemporaryFile(
            repository: repository,
            item: item,
            accelerationSource: accelerationSource,
            progress: { _ in }
        )
        defer { try? FileManager.default.removeItem(at: temporaryURL) }
        return try markdownDocument(
            data: Data(contentsOf: temporaryURL),
            title: item.name,
            path: item.path,
            origin: .remote
        )
    }

    func loadLocalMarkdown(
        _ file: DownloadedStudyFile
    ) async throws -> RepositoryMarkdownDocument {
        guard RepositoryMarkdownSupport.isMarkdownFile(file.name) else {
            throw StudyRepositoryError.invalidMarkdown
        }
        return try markdownDocument(
            data: Data(contentsOf: file.localURL),
            title: file.name,
            path: file.path,
            origin: .local
        )
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

    private func fetchTemporaryFile(
        repository: StudyRepositoryConfiguration,
        item: GitHubContentItem,
        accelerationSource: RepositoryAccelerationSource,
        progress: @escaping @Sendable (Double) async -> Void
    ) async throws -> URL {
        var urls = repository.downloadURLs(for: item.path, source: accelerationSource)
        if let downloadURL = item.downloadURL, !urls.contains(downloadURL) {
            urls.append(downloadURL)
        }

        var detectedGitLFS = false
        var failedIntegrityCheck = false
        for url in urls {
            do {
                let temporaryURL = try await fileRemote.downloadToTemporaryFile(
                    from: url,
                    progress: progress
                )
                let pointer: RepositoryGitLFSPointer?
                do {
                    pointer = try gitLFSPointer(at: temporaryURL)
                } catch {
                    try? FileManager.default.removeItem(at: temporaryURL)
                    throw error
                }
                guard let pointer else {
                    return temporaryURL
                }
                detectedGitLFS = true
                try? FileManager.default.removeItem(at: temporaryURL)

                guard let action = try await gitLFSRemote.resolveDownload(
                    repository: repository,
                    pointer: pointer
                ) else {
                    continue
                }
                for targetURL in accelerationSource.prioritizedLFSURLs(for: action) {
                    do {
                        let resolvedURL = try await fileRemote.downloadToTemporaryFile(
                            from: targetURL,
                            headers: action.headers,
                            progress: progress
                        )
                        do {
                            try validateGitLFSFile(at: resolvedURL, pointer: pointer)
                            return resolvedURL
                        } catch StudyRepositoryError.gitLFSIntegrityCheckFailed {
                            failedIntegrityCheck = true
                            try? FileManager.default.removeItem(at: resolvedURL)
                        } catch {
                            try? FileManager.default.removeItem(at: resolvedURL)
                        }
                    } catch is CancellationError {
                        throw CancellationError()
                    } catch {
                        continue
                    }
                }
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                continue
            }
        }
        if failedIntegrityCheck {
            throw StudyRepositoryError.gitLFSIntegrityCheckFailed
        }
        if detectedGitLFS {
            throw StudyRepositoryError.gitLFSUnavailable
        }
        throw StudyRepositoryError.downloadFailed
    }

    private func gitLFSPointer(at fileURL: URL) throws -> RepositoryGitLFSPointer? {
        let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
        let size = (attributes[.size] as? NSNumber)?.intValue ?? 0
        guard size > 0, size <= RepositoryGitLFSPointer.maximumPointerBytes else {
            return nil
        }
        return RepositoryGitLFSPointer.parse(try Data(contentsOf: fileURL))
    }

    private func validateGitLFSFile(
        at fileURL: URL,
        pointer: RepositoryGitLFSPointer
    ) throws {
        let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
        let size = (attributes[.size] as? NSNumber)?.int64Value ?? 0
        guard size == pointer.size else {
            throw StudyRepositoryError.gitLFSIntegrityCheckFailed
        }

        let handle = try FileHandle(forReadingFrom: fileURL)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 64 * 1_024), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        let digest = hasher.finalize().map { String(format: "%02x", $0) }.joined()
        guard digest == pointer.oid else {
            throw StudyRepositoryError.gitLFSIntegrityCheckFailed
        }
    }

    private func markdownDocument(
        data: Data,
        title: String,
        path: String,
        origin: RepositoryMarkdownOrigin
    ) throws -> RepositoryMarkdownDocument {
        guard let content = String(data: data, encoding: .utf8) else {
            throw StudyRepositoryError.invalidMarkdown
        }
        return RepositoryMarkdownDocument(
            title: title,
            path: path,
            content: content,
            origin: origin
        )
    }

    private static func contentOrder(_ lhs: GitHubContentItem, _ rhs: GitHubContentItem) -> Bool {
        if lhs.isDirectory != rhs.isDirectory { return lhs.isDirectory }
        return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
    }
}
