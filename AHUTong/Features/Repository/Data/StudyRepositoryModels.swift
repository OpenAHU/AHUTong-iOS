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

    func downloadURLs(for path: String) -> [URL] {
        let components = path.split(separator: "/").map(String.init)
        let cdnRoot = URL(string: "https://cdn.jsdelivr.net/gh/\(owner)/\(repository)@\(branch)")!
        let rawRoot = URL(string: "https://raw.githubusercontent.com/\(owner)/\(repository)/\(branch)")!
        return [cdnRoot, rawRoot].map { root in
            components.reduce(root) { $0.appendingPathComponent($1) }
        }
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

enum RepositoryLoadPolicy: Sendable {
    case cacheFirst
    case refresh
}

enum StudyRepositoryError: Error, Equatable, Sendable {
    case unknownRepository
    case invalidResponse
    case emptyDownload
    case downloadFailed
}
