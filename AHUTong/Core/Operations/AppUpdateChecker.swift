import Foundation

struct AppUpdateResult: Equatable, Sendable {
    let message: String
    let destination: URL?
}

struct InstalledBuild: Sendable {
    let actionsRun: Int
    let builtAt: Date?

    static var current: Self {
        let metadata = Bundle.main.url(forResource: "AHUTongBuild", withExtension: "plist")
            .flatMap { NSDictionary(contentsOf: $0) }
        return Self(actionsRun: metadata?["actionsRun"] as? Int ?? 0,
                    builtAt: metadata?["builtAt"] as? Date)
    }

    func precedes(run: Int, createdAt: Date) -> Bool {
        if actionsRun > 0 { return run > actionsRun }
        return builtAt.map { createdAt > $0 } ?? false
    }
}

struct ActionsUpdate: Equatable, Identifiable, Sendable {
    let id: Int
    let runNumber: Int
    let destination: URL
    var message: String { "测试构建 #\(runNumber) 已可下载。安装前需自行签名。" }
}

struct AppUpdateChecker: Sendable {
    private let transport: any NetworkTransport
    private let repository = "https://api.github.com/repos/OpenAHU/AHUTong-iOS"

    init(transport: any NetworkTransport = URLSessionTransport()) { self.transport = transport }

    func check(currentVersion: String, installed: InstalledBuild = .current) async throws -> AppUpdateResult {
        let (data, response) = try await request("\(repository)/releases/latest")
        if response.statusCode == 200 {
            let release = try JSONDecoder().decode(Release.self, from: data)
            let latest = release.tagName.trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
            if Self.compare(latest, currentVersion) == .orderedDescending {
                return AppUpdateResult(message: "发现新版本 \(release.tagName)：\(release.name ?? "请查看发布说明")", destination: release.htmlURL)
            }
        } else if response.statusCode != 404 {
            throw NetworkError.unacceptableStatusCode(response.statusCode)
        }
        if let update = try await availableActionsUpdate(installed: installed) {
            return AppUpdateResult(message: update.message, destination: update.destination)
        }
        return AppUpdateResult(message: "暂没有更新的可用版本。当前版本 \(currentVersion)。", destination: nil)
    }

    func availableActionsUpdate(installed: InstalledBuild, now: Date = Date()) async throws -> ActionsUpdate? {
        let runs: WorkflowRuns = try await decode("\(repository)/actions/workflows/ios-unsigned-ipa.yml/runs?status=success&per_page=5")
        for run in runs.workflowRuns.sorted(by: { $0.runNumber > $1.runNumber }) {
            guard run.conclusion == "success", installed.precedes(run: run.runNumber, createdAt: run.createdAt) else { continue }
            let artifacts: Artifacts = try await decode("\(repository)/actions/runs/\(run.id)/artifacts")
            guard artifacts.artifacts.contains(where: {
                $0.name == "AHUTong-unsigned-ipa-\(run.runNumber)" && !$0.expired && $0.sizeInBytes > 0 && $0.expiresAt > now
            }) else { continue }
            return ActionsUpdate(id: run.id, runNumber: run.runNumber,
                                 destination: URL(string: "https://github.com/OpenAHU/AHUTong-iOS/actions/runs/\(run.id)")!)
        }
        return nil
    }

    private func decode<Value: Decodable>(_ url: String) async throws -> Value {
        let (data, response) = try await request(url)
        guard response.statusCode == 200 else { throw NetworkError.unacceptableStatusCode(response.statusCode) }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(Value.self, from: data)
    }

    private func request(_ url: String) async throws -> (Data, HTTPURLResponse) {
        var request = URLRequest(url: URL(string: url)!, timeoutInterval: 15)
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
        let htmlURL: URL
        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name", name, htmlURL = "html_url"
        }
    }
    private struct WorkflowRuns: Decodable { let workflowRuns: [WorkflowRun] }
    private struct WorkflowRun: Decodable {
        let id: Int
        let runNumber: Int
        let createdAt: Date
        let conclusion: String?
    }
    private struct Artifacts: Decodable { let artifacts: [Artifact] }
    private struct Artifact: Decodable {
        let name: String
        let expired: Bool
        let sizeInBytes: Int
        let expiresAt: Date
    }
}

/// Foreground checks are throttled independently from the persistent prompt marker.
/// Failed requests and deferred presentation never consume a build's notification.
@MainActor
final class AppUpdateMonitor: ObservableObject {
    @Published private(set) var available: ActionsUpdate?
    private let checker: AppUpdateChecker
    private let defaults: UserDefaults
    private var checking = false
    private var lastCheck: Date?
    private let marker = "updates.last-presented-actions-run"

    init(checker: AppUpdateChecker = AppUpdateChecker(), defaults: UserDefaults = .standard) {
        self.checker = checker; self.defaults = defaults
    }

    func check(installed: InstalledBuild = .current, now: Date = Date()) async {
        guard !checking, lastCheck.map({ now.timeIntervalSince($0) >= 3_600 }) ?? true else { return }
        checking = true; lastCheck = now
        defer { checking = false }
        do {
            let candidate = try await checker.availableActionsUpdate(installed: installed, now: now)
            available = candidate.flatMap { $0.runNumber > defaults.integer(forKey: marker) ? $0 : nil }
        } catch {
            // Automatic checks are advisory; the manual settings action reports errors.
        }
    }

    func markPresented(_ update: ActionsUpdate) {
        defaults.set(max(update.runNumber, defaults.integer(forKey: marker)), forKey: marker)
        available = nil
    }
}
