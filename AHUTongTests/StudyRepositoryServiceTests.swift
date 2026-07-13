import Foundation
import XCTest
@testable import AHUTong

final class StudyRepositoryServiceTests: XCTestCase {
    func testCatalogMatchesSixAndroidSourceRepositories() throws {
        XCTAssertEqual(StudyRepositoryCatalog.repositories.count, 6)
        let cs = try XCTUnwrap(StudyRepositoryCatalog.repository(id: "cs"))
        XCTAssertEqual(cs.branch, "master")
        XCTAssertEqual(cs.githubURL.absoluteString, "https://github.com/Kaltsit-cell/AHU-CS-Repository")
        XCTAssertEqual(
            cs.downloadURLs(for: "大一/高数 1.pdf").last?.absoluteString,
            "https://raw.githubusercontent.com/Kaltsit-cell/AHU-CS-Repository/master/%E5%A4%A7%E4%B8%80/%E9%AB%98%E6%95%B0%201.pdf"
        )
    }

    @MainActor
    func testGitHubRemoteDecodesDirectoryAndBuildsEncodedRequest() async throws {
        let data = Data(#"[{"name":"高数 1.pdf","path":"大一/高数 1.pdf","type":"file","size":42,"download_url":"https://example.edu/file","html_url":null}]"#.utf8)
        let transport = RepositoryRecordingTransport(data: data)
        let remote = GitHubRepositoryContentRemote(transport: transport)
        let repository = try XCTUnwrap(StudyRepositoryCatalog.repository(id: "cs"))

        let items = try await remote.fetchContents(repository: repository, path: "大一")
        let request = await transport.lastRequest

        XCTAssertEqual(items.first?.name, "高数 1.pdf")
        XCTAssertEqual(request?.url?.query, "ref=master")
        XCTAssertEqual(request?.url?.path.removingPercentEncoding, "/repos/Kaltsit-cell/AHU-CS-Repository/contents/大一")
        XCTAssertEqual(request?.value(forHTTPHeaderField: "User-Agent"), "AHUTong-iOS/0.1")
    }

    @MainActor
    func testDirectoryCacheFirstFetchesOnceAndSortsFoldersFirst() async throws {
        let remote = RepositoryContentStub(items: [Self.file, Self.folder])
        let service = Self.makeService(contentRemote: remote)

        let first = try await service.loadDirectory(repositoryID: "cs", path: "")
        let second = try await service.loadDirectory(repositoryID: "cs", path: "")
        let count = await remote.count

        XCTAssertEqual(first.source, .remote)
        XCTAssertEqual(first.items.map(\.name), ["课程", "试卷.pdf"])
        XCTAssertEqual(second.source, .cache)
        XCTAssertEqual(count, 1)
    }

    @MainActor
    func testRefreshFailureUsesStaleDirectoryCache() async throws {
        let remote = RepositoryContentStub(items: [Self.file])
        let service = Self.makeService(contentRemote: remote)
        _ = try await service.loadDirectory(repositoryID: "cs", path: "")
        await remote.setShouldFail(true)

        let snapshot = try await service.loadDirectory(
            repositoryID: "cs",
            path: "",
            policy: .refresh
        )

        XCTAssertEqual(snapshot.source, .staleCache)
        XCTAssertEqual(snapshot.items, [Self.file])
    }

    @MainActor
    func testDownloadFallsBackFromCDNReportsProgressAndPersistsFile() async throws {
        let directory = Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileRemote = RepositoryFileStub(data: Data("fixture".utf8), failCDN: true)
        let downloads = RepositoryDownloadFileStore(directory: directory)
        let service = StudyRepositoryService(
            contentRemote: RepositoryContentStub(items: []),
            fileRemote: fileRemote,
            cache: InMemoryDataStore(),
            downloads: downloads
        )
        let progress = ProgressRecorder()

        let file = try await service.download(repositoryID: "cs", item: Self.file) { value in
            await progress.append(value)
        }
        let urls = await fileRemote.urls
        let values = await progress.values
        let downloadedIDs = try await service.downloadedFiles().map(\.id)

        XCTAssertEqual(urls.compactMap(\.host), ["cdn.jsdelivr.net", "raw.githubusercontent.com"])
        XCTAssertEqual(values, [0, 0.5, 1])
        XCTAssertEqual(try Data(contentsOf: file.localURL), Data("fixture".utf8))
        XCTAssertEqual(downloadedIDs, [file.id])
    }

    @MainActor
    func testDownloadStoreSupportsSingleAndBatchDeletion() async throws {
        let directory = Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = RepositoryDownloadFileStore(directory: directory)
        let first = try await store.save(Data([1]), repositoryID: "cs", path: "a.pdf")
        let second = try await store.save(Data([2]), repositoryID: "cs", path: "b.pdf")
        let third = try await store.save(Data([3]), repositoryID: "ai", path: "c.pdf")

        try await store.delete(ids: [first.id])
        let afterSingleDelete = try await store.files()
        XCTAssertEqual(Set(afterSingleDelete.map(\.id)), [second.id, third.id])

        try await store.delete(ids: [second.id, third.id])
        let afterBatchDelete = try await store.files()
        XCTAssertTrue(afterBatchDelete.isEmpty)
    }

    private static func makeService(
        contentRemote: any RepositoryContentRemoteDataSource
    ) -> StudyRepositoryService {
        StudyRepositoryService(
            contentRemote: contentRemote,
            fileRemote: RepositoryFileStub(data: Data()),
            cache: InMemoryDataStore(),
            downloads: RepositoryDownloadStoreStub()
        )
    }

    private static func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("AHUTongRepositoryTests-\(UUID().uuidString)", isDirectory: true)
    }

    private static let file = GitHubContentItem(
        name: "试卷.pdf",
        path: "课程/试卷.pdf",
        type: "file",
        size: 7,
        downloadURL: nil,
        htmlURL: nil
    )
    private static let folder = GitHubContentItem(
        name: "课程",
        path: "课程",
        type: "dir",
        size: 0,
        downloadURL: nil,
        htmlURL: nil
    )
}

private actor RepositoryRecordingTransport: NetworkTransport {
    let data: Data
    private(set) var lastRequest: URLRequest?

    init(data: Data) { self.data = data }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        lastRequest = request
        return (
            data,
            HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
        )
    }
}

private actor RepositoryContentStub: RepositoryContentRemoteDataSource {
    enum Failure: Error { case unavailable }

    let items: [GitHubContentItem]
    private(set) var count = 0
    private var shouldFail = false

    init(items: [GitHubContentItem]) { self.items = items }

    func fetchContents(
        repository: StudyRepositoryConfiguration,
        path: String
    ) async throws -> [GitHubContentItem] {
        count += 1
        if shouldFail { throw Failure.unavailable }
        return items
    }

    func setShouldFail(_ value: Bool) { shouldFail = value }
}

private actor RepositoryFileStub: RepositoryFileRemoteDataSource {
    enum Failure: Error { case unavailable }

    let data: Data
    let failCDN: Bool
    private(set) var urls: [URL] = []

    init(data: Data, failCDN: Bool = false) {
        self.data = data
        self.failCDN = failCDN
    }

    func download(
        from url: URL,
        progress: @escaping @Sendable (Double) async -> Void
    ) async throws -> Data {
        urls.append(url)
        if failCDN, url.host == "cdn.jsdelivr.net" { throw Failure.unavailable }
        await progress(0)
        await progress(0.5)
        await progress(1)
        return data
    }
}

private actor RepositoryDownloadStoreStub: RepositoryDownloadStoring {
    var records: [DownloadedStudyFile] = []

    func save(
        _ data: Data,
        repositoryID: String,
        path: String
    ) async throws -> DownloadedStudyFile {
        let record = DownloadedStudyFile(
            repositoryID: repositoryID,
            path: path,
            name: URL(fileURLWithPath: path).lastPathComponent,
            localURL: URL(fileURLWithPath: "/tmp/fixture"),
            size: Int64(data.count),
            downloadedAt: Date()
        )
        records.append(record)
        return record
    }

    func files() async throws -> [DownloadedStudyFile] { records }

    func delete(ids: Set<String>) async throws {
        records.removeAll { ids.contains($0.id) }
    }
}

private actor ProgressRecorder {
    private(set) var values: [Double] = []
    func append(_ value: Double) { values.append(value) }
}
