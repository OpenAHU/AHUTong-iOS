import Foundation

struct AppUpdateResult: Equatable, Sendable {
    let message: String
    let destination: URL?
}

struct AppUpdateChecker: Sendable {
    private let transport: any NetworkTransport
    private let releaseURL = URL(string: "https://api.github.com/repos/OpenAHU/AHUTong-iOS/releases/latest")!
    private let workflowURL = URL(string: "https://api.github.com/repos/OpenAHU/AHUTong-iOS/actions/workflows/ios-unsigned-ipa.yml/runs?status=success&per_page=1")!

    init(transport: any NetworkTransport = URLSessionTransport()) {
        self.transport = transport
    }

    func check(currentVersion: String) async throws -> AppUpdateResult {
        let (releaseData, releaseResponse) = try await request(releaseURL)
        if (200..<300).contains(releaseResponse.statusCode) {
            let release = try JSONDecoder().decode(Release.self, from: releaseData)
            let latest = release.tagName.trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
            if Self.compare(latest, currentVersion) == .orderedDescending {
                return AppUpdateResult(message: "发现新版本 \(release.tagName)：\(release.name ?? release.body ?? "请查看发布说明")", destination: release.htmlURL)
            }
            return AppUpdateResult(message: "当前已是最新正式版本（\(currentVersion)）", destination: release.htmlURL)
        }

        guard releaseResponse.statusCode == 404 else {
            throw NetworkError.unacceptableStatusCode(releaseResponse.statusCode)
        }
        let (workflowData, workflowResponse) = try await request(workflowURL)
        guard (200..<300).contains(workflowResponse.statusCode) else {
            throw NetworkError.unacceptableStatusCode(workflowResponse.statusCode)
        }
        let runs = try JSONDecoder().decode(WorkflowRuns.self, from: workflowData)
        guard let run = runs.workflowRuns.first else {
            return AppUpdateResult(message: "当前仓库还没有可用的正式 Release 或测试构建。", destination: nil)
        }
        return AppUpdateResult(
            message: "当前仓库尚未发布正式 Release；最新可下载测试构建为 GitHub Actions #\(run.runNumber)。",
            destination: run.htmlURL
        )
    }

    private func request(_ url: URL) async throws -> (Data, HTTPURLResponse) {
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("AHUTong-iOS", forHTTPHeaderField: "User-Agent")
        return try await transport.data(for: request)
    }

    static func compare(_ lhs: String, _ rhs: String) -> ComparisonResult {
        let left = lhs.split(separator: ".").map { Int($0.prefix { $0.isNumber }) ?? 0 }
        let right = rhs.split(separator: ".").map { Int($0.prefix { $0.isNumber }) ?? 0 }
        for index in 0..<max(left.count, right.count) {
            let l = index < left.count ? left[index] : 0
            let r = index < right.count ? right[index] : 0
            if l != r { return l < r ? .orderedAscending : .orderedDescending }
        }
        return .orderedSame
    }

    private struct Release: Decodable {
        let tagName: String
        let name: String?
        let body: String?
        let htmlURL: URL

        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case name, body
            case htmlURL = "html_url"
        }
    }

    private struct WorkflowRuns: Decodable {
        let workflowRuns: [WorkflowRun]
        enum CodingKeys: String, CodingKey { case workflowRuns = "workflow_runs" }
    }

    private struct WorkflowRun: Decodable {
        let runNumber: Int
        let htmlURL: URL
        enum CodingKeys: String, CodingKey {
            case runNumber = "run_number"
            case htmlURL = "html_url"
        }
    }
}
