import CryptoKit
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

    func testRepositoryDisplayPathUsesCollegeNameAndRemovesDuplicatedRoot() {
        XCTAssertEqual(
            RepositoryPathPresentation.formatDisplayPath(
                repositoryID: "cs",
                relativePath: "大一/高等数学.pdf"
            ),
            "计算机科学与技术学院/大一/高等数学.pdf"
        )
        XCTAssertEqual(
            RepositoryPathPresentation.formatDisplayPath(
                repositoryID: "cs",
                relativePath: "计算机科学与技术学院/大一/高等数学.pdf"
            ),
            "计算机科学与技术学院/大一/高等数学.pdf"
        )
        XCTAssertEqual(
            RepositoryPathPresentation.formatDisplayPath(
                repositoryID: "cs",
                relativePath: "cs/大一/高等数学.pdf"
            ),
            "计算机科学与技术学院/大一/高等数学.pdf"
        )
        XCTAssertEqual(
            RepositoryPathPresentation.formatDisplayPath(virtualPath: ""),
            "学习资料"
        )
    }

    func testRepositoryBreadcrumbPreservesVirtualTargetsWhileHidingDuplicatedRoot() {
        let breadcrumbs = RepositoryPathPresentation.breadcrumbs(
            for: "cs/计算机科学与技术学院/大一/高数"
        )

        XCTAssertEqual(
            breadcrumbs.map(\.label),
            ["学习资料", "计算机科学与技术学院", "大一", "高数"]
        )
        XCTAssertEqual(
            breadcrumbs.map(\.path),
            [
                "",
                "cs",
                "cs/计算机科学与技术学院/大一",
                "cs/计算机科学与技术学院/大一/高数"
            ]
        )
        XCTAssertEqual(
            RepositoryPathPresentation.location(
                for: breadcrumbs.last?.path ?? ""
            ),
            RepositoryVirtualLocation(
                repositoryID: "cs",
                relativePath: "计算机科学与技术学院/大一/高数"
            )
        )
    }

    func testAccelerationPreferencePersistsAndInvalidValueFallsBack() {
        let suite = "RepositoryAccelerationPreferenceTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        XCTAssertEqual(
            RepositoryAccelerationPreferences.selectedSource(in: defaults),
            .jsDelivr
        )
        RepositoryAccelerationPreferences.save(.ghProxy, in: defaults)
        XCTAssertEqual(
            RepositoryAccelerationPreferences.selectedSource(in: defaults),
            .ghProxy
        )

        defaults.set("removed-source", forKey: RepositoryAccelerationPreferences.key)
        XCTAssertEqual(
            RepositoryAccelerationPreferences.selectedSource(in: defaults),
            .jsDelivr
        )
    }

    func testDownloadURLPolicyPrioritizesThreeAcceleratorsAndDirectFallback() throws {
        let repository = try XCTUnwrap(StudyRepositoryCatalog.repository(id: "cs"))
        let path = "大一/高数 1.pdf"

        let jsDelivr = repository.downloadURLs(for: path, source: .jsDelivr)
        XCTAssertEqual(jsDelivr.map(\.host), ["cdn.jsdelivr.net", "raw.githubusercontent.com"])

        let moeyy = repository.downloadURLs(for: path, source: .moeyy)
        XCTAssertEqual(moeyy.first?.host, "github.moeyy.xyz")
        XCTAssertTrue(try XCTUnwrap(moeyy.first?.absoluteString).contains("raw.githubusercontent.com"))
        XCTAssertEqual(moeyy.suffix(2).compactMap(\.host), ["cdn.jsdelivr.net", "raw.githubusercontent.com"])

        let ghProxy = repository.downloadURLs(for: path, source: .ghProxy)
        XCTAssertEqual(ghProxy.first?.host, "gh-proxy.com")
        XCTAssertEqual(ghProxy.last?.host, "raw.githubusercontent.com")

        let direct = repository.downloadURLs(for: path, source: .direct)
        XCTAssertEqual(direct.map(\.host), ["raw.githubusercontent.com", "cdn.jsdelivr.net"])
    }

    func testMarkdownDetectionSupportsCommonExtensions() {
        XCTAssertTrue(RepositoryMarkdownSupport.isMarkdownFile("README.md"))
        XCTAssertTrue(RepositoryMarkdownSupport.isMarkdownFile("指南.MARKDOWN"))
        XCTAssertTrue(RepositoryMarkdownSupport.isMarkdownFile("notes.mdown"))
        XCTAssertFalse(RepositoryMarkdownSupport.isMarkdownFile("lecture.pdf"))
        XCTAssertFalse(RepositoryMarkdownSupport.isMarkdownFile("md"))
    }

    func testGitLFSPointerParserRejectsMalformedPointers() throws {
        let oid = String(repeating: "a", count: 64)
        let valid = Data(
            """
            version https://git-lfs.github.com/spec/v1
            oid sha256:\(oid)
            size 42
            """.utf8
        )
        XCTAssertEqual(
            RepositoryGitLFSPointer.parse(valid),
            RepositoryGitLFSPointer(oid: oid, size: 42)
        )
        XCTAssertNil(RepositoryGitLFSPointer.parse(Data("plain file".utf8)))
        XCTAssertNil(
            RepositoryGitLFSPointer.parse(
                Data(
                    """
                    version https://git-lfs.github.com/spec/v1
                    oid sha256:not-a-digest
                    size 42
                    """.utf8
                )
            )
        )
        XCTAssertNil(
            RepositoryGitLFSPointer.parse(
                Data(
                    """
                    version https://git-lfs.github.com/spec/v1
                    oid sha256:\(oid)
                    size 0
                    """.utf8
                )
            )
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
    func testGitLFSBatchRemoteResolvesHTTPSDownloadTargetAndHeaders() async throws {
        let oid = String(repeating: "c", count: 64)
        let responseData = Data(
            """
            {
              "objects": [{
                "oid": "\(oid)",
                "size": 42,
                "actions": {
                  "download": {
                    "href": "https://media.githubusercontent.com/lfs/object",
                    "header": {"Authorization": "Remote fixture"}
                  }
                }
              }]
            }
            """.utf8
        )
        let transport = RepositoryRecordingTransport(data: responseData)
        let remote = GitHubRepositoryGitLFSRemote(transport: transport)
        let repository = try XCTUnwrap(StudyRepositoryCatalog.repository(id: "cs"))

        let action = try await remote.resolveDownload(
            repository: repository,
            pointer: RepositoryGitLFSPointer(oid: oid, size: 42)
        )
        let request = await transport.lastRequest

        XCTAssertEqual(
            request?.url?.absoluteString,
            "https://github.com/Kaltsit-cell/AHU-CS-Repository.git/info/lfs/objects/batch"
        )
        XCTAssertEqual(request?.httpMethod, "POST")
        XCTAssertEqual(
            request?.value(forHTTPHeaderField: "Content-Type"),
            "application/vnd.git-lfs+json"
        )
        XCTAssertEqual(action?.url.absoluteString, "https://media.githubusercontent.com/lfs/object")
        XCTAssertEqual(action?.headers, ["Authorization": "Remote fixture"])
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
    func testGitLFSPointerResolvesVerifiedRealDownload() async throws {
        let directory = Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let payload = Data("real Git LFS document".utf8)
        let oid = SHA256.hash(data: payload).map { String(format: "%02x", $0) }.joined()
        let pointer = Data(
            """
            version https://git-lfs.github.com/spec/v1
            oid sha256:\(oid)
            size \(payload.count)
            """.utf8
        )
        let lfsURL = URL(string: "https://media.githubusercontent.com/lfs/object")!
        let fileRemote = RepositoryLFSFileStub(
            pointer: pointer,
            payload: payload,
            lfsURL: lfsURL
        )
        let service = StudyRepositoryService(
            contentRemote: RepositoryContentStub(items: []),
            fileRemote: fileRemote,
            gitLFSRemote: RepositoryLFSRemoteStub(
                action: RepositoryGitLFSDownload(
                    url: lfsURL,
                    headers: ["X-LFS-Token": "fixture"]
                )
            ),
            cache: InMemoryDataStore(),
            downloads: RepositoryDownloadFileStore(directory: directory)
        )

        let file = try await service.download(
            repositoryID: "cs",
            item: Self.file,
            accelerationSource: .moeyy
        ) { _ in }
        let requests = await fileRemote.requests

        XCTAssertEqual(try Data(contentsOf: file.localURL), payload)
        XCTAssertEqual(file.size, Int64(payload.count))
        XCTAssertEqual(requests.last?.url, lfsURL)
        XCTAssertEqual(requests.last?.headers, ["X-LFS-Token": "fixture"])
        XCTAssertFalse(requests.contains { $0.url.host == "github.moeyy.xyz" && !$0.headers.isEmpty })
    }

    @MainActor
    func testUnresolvableGitLFSPointerUsesClearErrorInsteadOfSavingPointer() async throws {
        let oid = String(repeating: "b", count: 64)
        let pointer = Data(
            """
            version https://git-lfs.github.com/spec/v1
            oid sha256:\(oid)
            size 123
            """.utf8
        )
        let fileRemote = RepositoryLFSFileStub(
            pointer: pointer,
            payload: Data(),
            lfsURL: URL(string: "https://media.githubusercontent.com/lfs/missing")!
        )
        let service = StudyRepositoryService(
            contentRemote: RepositoryContentStub(items: []),
            fileRemote: fileRemote,
            gitLFSRemote: RepositoryLFSRemoteStub(action: nil),
            cache: InMemoryDataStore(),
            downloads: RepositoryDownloadStoreStub()
        )

        do {
            _ = try await service.download(
                repositoryID: "cs",
                item: Self.file,
                accelerationSource: .direct
            ) { _ in }
            XCTFail("Expected a clear Git LFS error")
        } catch let error as StudyRepositoryError {
            XCTAssertEqual(error, .gitLFSUnavailable)
            XCTAssertTrue(error.localizedDescription.contains("Git LFS"))
        }
    }

    @MainActor
    func testLocalMarkdownLoadsForInAppReader() async throws {
        let directory = Self.temporaryDirectory()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let localURL = directory.appendingPathComponent("README.md")
        try Data("# 标题\n\n正文".utf8).write(to: localURL)
        let file = DownloadedStudyFile(
            repositoryID: "cs",
            path: "README.md",
            name: "README.md",
            localURL: localURL,
            size: 17,
            downloadedAt: Date()
        )
        let service = Self.makeService(contentRemote: RepositoryContentStub(items: []))

        let document = try await service.loadLocalMarkdown(file)

        XCTAssertEqual(document.title, "README.md")
        XCTAssertEqual(document.path, "README.md")
        XCTAssertEqual(document.origin, .local)
        XCTAssertTrue(document.content.contains("# 标题"))
    }

    @MainActor
    func testRemoteMarkdownUsesSelectedContentSourceWithoutPersistingDownload() async throws {
        let fileRemote = RepositoryFileStub(data: Data("# Remote\n\nBody".utf8))
        let downloads = RepositoryDownloadStoreStub()
        let service = StudyRepositoryService(
            contentRemote: RepositoryContentStub(items: []),
            fileRemote: fileRemote,
            cache: InMemoryDataStore(),
            downloads: downloads
        )
        let item = GitHubContentItem(
            name: "README.md",
            path: "docs/README.md",
            type: "file",
            size: 15,
            downloadURL: nil,
            htmlURL: nil
        )

        let document = try await service.loadRemoteMarkdown(
            repositoryID: "cs",
            item: item,
            accelerationSource: .ghProxy
        )
        let urls = await fileRemote.urls
        let records = try await downloads.files()

        XCTAssertEqual(urls.first?.host, "gh-proxy.com")
        XCTAssertEqual(document.origin, .remote)
        XCTAssertEqual(document.content, "# Remote\n\nBody")
        XCTAssertTrue(records.isEmpty)
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

private struct RepositoryRecordedFileRequest: Sendable {
    let url: URL
    let headers: [String: String]
}

private actor RepositoryLFSFileStub: RepositoryFileRemoteDataSource {
    let pointer: Data
    let payload: Data
    let lfsURL: URL
    private(set) var requests: [RepositoryRecordedFileRequest] = []

    init(pointer: Data, payload: Data, lfsURL: URL) {
        self.pointer = pointer
        self.payload = payload
        self.lfsURL = lfsURL
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
        requests.append(RepositoryRecordedFileRequest(url: url, headers: headers))
        await progress(0)
        await progress(1)
        return url == lfsURL ? payload : pointer
    }
}

private struct RepositoryLFSRemoteStub: RepositoryGitLFSRemoteDataSource {
    let action: RepositoryGitLFSDownload?

    func resolveDownload(
        repository: StudyRepositoryConfiguration,
        pointer: RepositoryGitLFSPointer
    ) async throws -> RepositoryGitLFSDownload? {
        action
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
