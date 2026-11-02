import Foundation

struct CanteenWindowReport: Encodable, Sendable {
    let terminal: String
    let merchant: String
    let suggestedName: String
    let sampleCount: Int
}

protocol CanteenCommunityRemote: Sendable {
    var canContribute: Bool { get }
    func windowNames() async throws -> [String: String]
    func upload(_ transactions: [CanteenTransaction]) async throws
    func report(_ report: CanteenWindowReport) async throws
}

struct CanteenContributionFailure: LocalizedError {
    let sent: Int
    let total: Int
    let reason: String
    var errorDescription: String? {
        sent == 0 ? reason : "已提交 \(sent)/\(total) 笔。\(reason)；再次提交会由服务器去重。"
    }
}

struct OfficialCanteenCommunityRemote: CanteenCommunityRemote {
    private let session: URLSession
    private let writeKey: String
    var canContribute: Bool { !writeKey.isEmpty }
    init(session: URLSession? = nil, writeKey: String? = nil) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil; configuration.httpShouldSetCookies = false
        configuration.urlCredentialStorage = nil; configuration.urlCache = nil
        self.session = session ?? URLSession(configuration: configuration, delegate: CanteenNoRedirect(), delegateQueue: nil)
        let encoded = Bundle.main.object(forInfoDictionaryKey: "AHUTongCanteenWriteKey") as? String ?? ""
        self.writeKey = writeKey ?? Data(base64Encoded: encoded).flatMap { String(data: $0, encoding: .utf8) } ?? ""
    }
    func windowNames() async throws -> [String: String] {
        let url = URL(string: "https://inchangejiang.cn/api/canteen/window-map")!
        let (data, response) = try await session.diagnosticData(for: request(url))
        guard let response = response as? HTTPURLResponse, response.url == url,
              response.statusCode == 200, data.count <= 2_000_000 else { throw CampusWebError.invalidResponse }
        struct Mapping: Decodable { let entries: [Entry] }
        struct Entry: Decodable { let terminal: String; let name: String? }
        var names: [String: String] = [:]
        for entry in try JSONDecoder().decode(Mapping.self, from: data).entries {
            if let name = entry.name?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty { names[entry.terminal] = name }
        }
        return names
    }
    func upload(_ transactions: [CanteenTransaction]) async throws {
        struct Batch: Encodable { let txns: [CanteenTransaction] }
        var sent = 0
        for start in stride(from: 0, to: transactions.count, by: 400) {
            try Task.checkCancellation()
            let batch = Array(transactions[start..<min(start + 400, transactions.count)])
            do { try await post("txns", body: Batch(txns: batch)); sent += batch.count }
            catch is CancellationError { throw CancellationError() }
            catch { throw CanteenContributionFailure(sent: sent, total: transactions.count, reason: error.localizedDescription) }
        }
    }
    func report(_ report: CanteenWindowReport) async throws {
        guard !report.suggestedName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, report.suggestedName.count <= 20 else {
            throw CampusWebError.server("窗口名称请填写 1–20 个字")
        }
        try await post("window-report", body: report)
    }
    private func request(_ url: URL) -> URLRequest {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData)
        request.timeoutInterval = 20; request.httpShouldHandleCookies = false
        return request
    }
    private func post<T: Encodable>(_ path: String, body: T) async throws {
        guard canContribute else { throw CampusWebError.server("此安装包暂未配置贡献服务") }
        let url = URL(string: "https://inchangejiang.cn/api/canteen/\(path)")!
        var request = request(url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(writeKey, forHTTPHeaderField: "X-Api-Key")
        request.httpBody = try JSONEncoder().encode(body)
        let (_, response) = try await session.diagnosticData(for: request)
        guard let response = response as? HTTPURLResponse, response.url == url else { throw CampusWebError.invalidResponse }
        switch response.statusCode {
        case 204: return
        case 401, 403: throw CampusWebError.server("贡献服务授权暂不可用，请更新 App 后重试")
        case 422: throw CampusWebError.server("服务器未接受这些记录，请稍后更新 App 再试")
        case 429: throw CampusWebError.server("提交较频繁，请稍后再试")
        default: throw CampusWebError.server("提交未确认，请检查网络后重试")
        }
    }
}

private final class CanteenNoRedirect: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
}
