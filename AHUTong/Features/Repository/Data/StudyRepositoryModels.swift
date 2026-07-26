import Foundation

struct StudyRepositoryConfiguration: Hashable, Identifiable, Sendable {
    let id: String
    let name: String
    let owner: String
    let repository: String
    let branch: String

    var githubURL: URL {
        URL(string: "https://github.com/\(owner)/\(repository)")!
    }

    var gitLFSBatchURL: URL {
        URL(string: "https://github.com/\(owner)/\(repository).git/info/lfs/objects/batch")!
    }

    func rawURL(for path: String) -> URL {
        let components = path.split(separator: "/").map(String.init)
        let rawRoot = URL(string: "https://raw.githubusercontent.com/\(owner)/\(repository)/\(branch)")!
        return components.reduce(rawRoot) { $0.appendingPathComponent($1) }
    }

    func cdnURL(for path: String) -> URL {
        let components = path.split(separator: "/").map(String.init)
        let cdnRoot = URL(string: "https://cdn.jsdelivr.net/gh/\(owner)/\(repository)@\(branch)")!
        return components.reduce(cdnRoot) { $0.appendingPathComponent($1) }
    }

    func downloadURLs(
        for path: String,
        source: RepositoryAccelerationSource = .jsDelivr
    ) -> [URL] {
        let rawURL = rawURL(for: path)
        let cdnURL = cdnURL(for: path)
        return source.prioritizedURLs(rawURL: rawURL, cdnURL: cdnURL)
    }
}

enum RepositoryAccelerationSource: String, CaseIterable, Codable, Identifiable, Sendable {
    case jsDelivr = "jsdelivr"
    case moeyy
    case ghProxy = "gh-proxy"
    case direct

    var id: String { rawValue }

    var name: String {
        switch self {
        case .jsDelivr: "jsDelivr"
        case .moeyy: "Moeyy"
        case .ghProxy: "gh-proxy"
        case .direct: "GitHub 直连"
        }
    }

    var detail: String {
        switch self {
        case .jsDelivr: "默认优先使用 jsDelivr CDN"
        case .moeyy: "通过 github.moeyy.xyz 加速 GitHub 原始文件"
        case .ghProxy: "通过 gh-proxy.com 加速 GitHub 原始文件"
        case .direct: "不使用加速源，直接连接 GitHub"
        }
    }

    func prioritizedURLs(rawURL: URL, cdnURL: URL) -> [URL] {
        let selectedURL: URL
        switch self {
        case .jsDelivr:
            selectedURL = cdnURL
        case .moeyy:
            selectedURL = proxy(rawURL, prefix: "https://github.moeyy.xyz/") ?? rawURL
        case .ghProxy:
            selectedURL = proxy(rawURL, prefix: "https://gh-proxy.com/") ?? rawURL
        case .direct:
            selectedURL = rawURL
        }
        return [selectedURL, cdnURL, rawURL].reduce(into: []) { urls, candidate in
            if !urls.contains(candidate) { urls.append(candidate) }
        }
    }

    func prioritizedLFSURLs(for action: RepositoryGitLFSDownload) -> [URL] {
        guard action.headers.isEmpty else { return [action.url] }
        let proxiedURL: URL?
        switch self {
        case .moeyy:
            proxiedURL = proxy(action.url, prefix: "https://github.moeyy.xyz/")
        case .ghProxy:
            proxiedURL = proxy(action.url, prefix: "https://gh-proxy.com/")
        case .jsDelivr, .direct:
            proxiedURL = nil
        }
        return [proxiedURL, action.url].compactMap { $0 }.reduce(into: []) { urls, candidate in
            if !urls.contains(candidate) { urls.append(candidate) }
        }
    }

    private func proxy(_ url: URL, prefix: String) -> URL? {
        URL(string: prefix + url.absoluteString)
    }
}

enum RepositoryAccelerationPreferences {
    static let key = "repository.acceleration-source"
    static let defaultSource = RepositoryAccelerationSource.jsDelivr

    static func selectedSource(in defaults: UserDefaults = .standard) -> RepositoryAccelerationSource {
        guard let rawValue = defaults.string(forKey: key),
              let source = RepositoryAccelerationSource(rawValue: rawValue) else {
            return defaultSource
        }
        return source
    }

    static func save(_ source: RepositoryAccelerationSource, in defaults: UserDefaults = .standard) {
        defaults.set(source.rawValue, forKey: key)
    }
}

enum StudyRepositoryCatalog {
    static let repositories: [StudyRepositoryConfiguration] = [
        .init(id: "cs", name: "计算机科学与技术学院", owner: "Kaltsit-cell", repository: "AHU-CS-Repository", branch: "master"),
        .init(id: "ai", name: "人工智能学院", owner: "DylanAo", repository: "AHU-AI-Repository", branch: "main"),
        .init(id: "ic", name: "集成电路学院", owner: "Tonyseth", repository: "AHU-IC-Design-personal-Repository", branch: "main"),
        .init(id: "ee", name: "电子信息工程学院", owner: "HarryWeasley3", repository: "AHU-EE-Repository", branch: "main"),
        .init(id: "internet", name: "互联网学院", owner: "Zeraora-807", repository: "AHU-Internet-Exams-Archive", branch: "main"),
        .init(id: "sbi", name: "石溪学院", owner: "UponNoise", repository: "AHU_SBI_DMT", branch: "main")
    ]

    static func repository(id: String) -> StudyRepositoryConfiguration? {
        repositories.first(where: { $0.id == id })
    }
}

struct RepositoryBreadcrumbItem: Equatable, Identifiable, Sendable {
    let label: String
    let path: String

    var id: String { path.isEmpty ? "repository-root" : path }
}

struct RepositoryVirtualLocation: Equatable, Sendable {
    let repositoryID: String
    let relativePath: String
}

enum RepositoryPathPresentation {
    static func virtualPath(repositoryID: String, relativePath: String) -> String {
        let repositoryID = normalize(repositoryID)
        let relativePath = normalize(relativePath)
        guard !repositoryID.isEmpty else { return "" }
        if relativePath == repositoryID || relativePath.hasPrefix("\(repositoryID)/") {
            return relativePath
        }
        return relativePath.isEmpty ? repositoryID : "\(repositoryID)/\(relativePath)"
    }

    static func location(for virtualPath: String) -> RepositoryVirtualLocation? {
        let segments = segments(in: virtualPath)
        guard let repositoryID = segments.first,
              StudyRepositoryCatalog.repository(id: repositoryID) != nil else {
            return nil
        }
        return RepositoryVirtualLocation(
            repositoryID: repositoryID,
            relativePath: segments.dropFirst().joined(separator: "/")
        )
    }

    static func formatDisplayPath(repositoryID: String, relativePath: String) -> String {
        formatDisplayPath(
            virtualPath: virtualPath(repositoryID: repositoryID, relativePath: relativePath)
        )
    }

    static func formatDisplayPath(virtualPath: String) -> String {
        let segments = segments(in: virtualPath)
        guard let repositoryID = segments.first else { return "学习资料" }
        let repositoryTitle = StudyRepositoryCatalog.repository(id: repositoryID)?.name
            ?? repositoryID
        var relativeSegments = Array(segments.dropFirst())
        if relativeSegments.first == repositoryTitle {
            relativeSegments.removeFirst()
        }
        return ([repositoryTitle] + relativeSegments).joined(separator: "/")
    }

    static func breadcrumbs(for virtualPath: String) -> [RepositoryBreadcrumbItem] {
        let normalizedPath = normalize(virtualPath)
        let pathSegments = segments(in: normalizedPath)
        var items = [RepositoryBreadcrumbItem(label: "学习资料", path: "")]
        guard let repositoryID = pathSegments.first else { return items }

        let repositoryTitle = StudyRepositoryCatalog.repository(id: repositoryID)?.name
            ?? repositoryID
        items.append(RepositoryBreadcrumbItem(label: repositoryTitle, path: repositoryID))

        let actualRelativeSegments = Array(pathSegments.dropFirst())
        let hasDuplicatedRepositoryTitle = actualRelativeSegments.first == repositoryTitle
        let visibleRelativeSegments = hasDuplicatedRepositoryTitle
            ? Array(actualRelativeSegments.dropFirst())
            : actualRelativeSegments

        for index in visibleRelativeSegments.indices {
            let visibleCount = index + 1
            let actualCount = hasDuplicatedRepositoryTitle ? visibleCount + 1 : visibleCount
            let actualPath = ([repositoryID] + Array(actualRelativeSegments.prefix(actualCount)))
                .joined(separator: "/")
            items.append(
                RepositoryBreadcrumbItem(
                    label: visibleRelativeSegments[index],
                    path: actualPath
                )
            )
        }
        return items
    }

    private static func normalize(_ path: String) -> String {
        path
            .replacingOccurrences(of: "\\", with: "/")
            .split(separator: "/", omittingEmptySubsequences: true)
            .joined(separator: "/")
    }

    private static func segments(in path: String) -> [String] {
        normalize(path).split(separator: "/").map(String.init)
    }
}

struct GitHubContentItem: Codable, Hashable, Identifiable, Sendable {
    let name: String
    let path: String
    let type: String
    let size: Int64
    let downloadURL: URL?
    let htmlURL: URL?

    var id: String { path }
    var isDirectory: Bool { type == "dir" }

    enum CodingKeys: String, CodingKey {
        case name, path, type, size
        case downloadURL = "download_url"
        case htmlURL = "html_url"
    }
}

enum RepositoryDirectorySource: String, Codable, Equatable, Sendable {
    case cache
    case remote
    case staleCache
}

struct RepositoryDirectorySnapshot: Equatable, Sendable {
    let items: [GitHubContentItem]
    let source: RepositoryDirectorySource
    let updatedAt: Date
}

struct RepositoryDirectoryCacheEntry: Codable, Sendable {
    let items: [GitHubContentItem]
    let updatedAt: Date
}

struct DownloadedStudyFile: Codable, Hashable, Identifiable, Sendable {
    let repositoryID: String
    let path: String
    let name: String
    let localURL: URL
    let size: Int64
    let downloadedAt: Date

    var id: String { "\(repositoryID):\(path)" }
}

enum RepositoryMarkdownOrigin: Equatable, Sendable {
    case remote
    case local
}

struct RepositoryMarkdownDocument: Equatable, Sendable {
    let title: String
    let path: String
    let content: String
    let origin: RepositoryMarkdownOrigin
}

enum RepositoryMarkdownSupport {
    static func isMarkdownFile(_ name: String) -> Bool {
        switch URL(fileURLWithPath: name).pathExtension.lowercased() {
        case "md", "markdown", "mdown", "mkd":
            true
        default:
            false
        }
    }
}

struct RepositoryGitLFSPointer: Equatable, Sendable {
    static let signature = "version https://git-lfs.github.com/spec/v1"
    static let maximumPointerBytes = 1_024

    let oid: String
    let size: Int64

    static func parse(_ data: Data) -> RepositoryGitLFSPointer? {
        guard !data.isEmpty,
              data.count <= maximumPointerBytes,
              let content = String(data: data, encoding: .utf8) else {
            return nil
        }
        let lines = content
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard lines.first == signature else { return nil }

        guard let oidLine = lines.first(where: { $0.hasPrefix("oid sha256:") }) else {
            return nil
        }
        let oid = String(oidLine.dropFirst("oid sha256:".count))
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard oid.count == 64,
              oid.unicodeScalars.allSatisfy({
                  CharacterSet(charactersIn: "0123456789abcdef").contains($0)
              }) else {
            return nil
        }

        guard let sizeLine = lines.first(where: { $0.hasPrefix("size ") }),
              let size = Int64(
                  String(sizeLine.dropFirst("size ".count))
                      .trimmingCharacters(in: .whitespaces)
              ),
              size > 0 else {
            return nil
        }
        return RepositoryGitLFSPointer(oid: oid, size: size)
    }
}

struct RepositoryGitLFSDownload: Equatable, Sendable {
    let url: URL
    let headers: [String: String]
}

enum RepositoryLoadPolicy: Sendable {
    case cacheFirst
    case refresh
}

enum StudyRepositoryError: Error, Equatable, Sendable {
    case unknownRepository
    case invalidResponse
    case emptyDownload
    case downloadFailed
    case invalidMarkdown
    case gitLFSUnavailable
    case gitLFSIntegrityCheckFailed
}

extension StudyRepositoryError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .unknownRepository:
            "找不到对应的学习资料仓库。"
        case .invalidResponse:
            "学习资料服务返回了无效响应。"
        case .emptyDownload:
            "下载内容为空。"
        case .downloadFailed:
            "下载失败，请稍后重试。"
        case .invalidMarkdown:
            "Markdown 内容无法按 UTF-8 解码。"
        case .gitLFSUnavailable:
            "该文件由 Git LFS 托管，当前无法取得真实文件，请切换加速源或稍后重试。"
        case .gitLFSIntegrityCheckFailed:
            "Git LFS 文件完整性校验失败，已拒绝保存。"
        }
    }
}
