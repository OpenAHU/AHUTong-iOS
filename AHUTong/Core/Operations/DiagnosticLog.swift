import Foundation

enum DiagnosticLogCategory: String, CaseIterable, Identifiable, Sendable {
    case runtime, error, network
    var id: Self { self }
    var title: String { switch self { case .runtime: "运行记录"; case .error: "错误信息"; case .network: "网络详情" } }
}

/// Consent-gated process memory. A request keeps its starting generation so
/// switching accounts cannot append the old account's response to the new log.
final class DiagnosticLog: @unchecked Sendable {
    static let shared = DiagnosticLog()
    struct Entry: Sendable { let category: DiagnosticLogCategory; let time: TimeInterval; let text: String }
    private let lock = NSLock()
    private var entries: [Entry] = []
    private var bytes = 0
    private var enabled = false
    private var revision = 0
    private let maximumBytes: Int
    private let lifetime: TimeInterval
    private let clock: @Sendable () -> TimeInterval

    init(maximumBytes: Int = 5 * 1024 * 1024, lifetime: TimeInterval = 600,
         clock: @escaping @Sendable () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }) {
        self.maximumBytes = maximumBytes; self.lifetime = lifetime; self.clock = clock
    }
    var generation: Int { lock.withLock { revision } }
    var activeGeneration: Int? { lock.withLock { enabled ? revision : nil } }
    func setEnabled(_ value: Bool) {
        lock.withLock { enabled = value; reset() }
    }
    func clear() { lock.withLock { reset() } }
    private func reset() { revision += 1; entries.removeAll(); bytes = 0 }
    private func prune(at now: TimeInterval) {
        while let first = entries.first, now - first.time >= lifetime || bytes > maximumBytes {
            bytes -= first.text.utf8.count; entries.removeFirst()
        }
    }
    @discardableResult
    func append(_ category: DiagnosticLogCategory, text: String, generation: Int) -> Bool {
        lock.withLock {
            guard enabled, revision == generation, text.utf8.count <= maximumBytes else { return false }
            let now = clock()
            entries.append(Entry(category: category, time: now, text: text)); bytes += text.utf8.count
            prune(at: now)
            return true
        }
    }
    func snapshot(_ category: DiagnosticLogCategory, maxCharacters: Int? = nil) -> String {
        lock.withLock {
            prune(at: clock())
            let text = entries.filter { $0.category == category }.map(\.text).joined(separator: "\n")
            return maxCharacters.map { String(text.suffix($0)) } ?? text
        }
    }
}

enum DiagnosticText {
    private static let hidden = "[已隐藏]"
    private static let passwordKeys = ["password", "passwd", "pwd", "pwddefaultencryptsalt", "encryptpassword", "encryptedpassword", "passwordencrypt", "rsa", "pincode", "paypassword", "writekey", "secret", "qrcode", "qrdata", "paycode"]
    private static let identityKeys = ["studentid", "studentno", "username", "account", "userid", "token", "accesstoken", "authorization", "cookie", "setcookie", "email", "phone"]

    static func redacted(_ text: String, includeIdentity: Bool = true) -> String {
        let keys = passwordKeys + (includeIdentity ? identityKeys : [])
        func sensitive(_ key: String) -> Bool {
            let normalized = key.lowercased().filter { $0.isLetter || $0.isNumber }
            return keys.contains(where: { normalized.contains($0) })
        }
        func scrub(_ value: Any) -> Any {
            if let object = value as? [String: Any] { return object.reduce(into: [String: Any]()) { result, pair in result[pair.key] = sensitive(pair.key) ? hidden : scrub(pair.value) } }
            if let array = value as? [Any] { return array.map(scrub) }
            return value
        }
        var output = text
        if let data = text.data(using: .utf8), let json = try? JSONSerialization.jsonObject(with: data),
           let cleaned = try? JSONSerialization.data(withJSONObject: scrub(json), options: [.sortedKeys]),
           let value = String(data: cleaned, encoding: .utf8) { output = value }
        let names = keys.map(NSRegularExpression.escapedPattern(for:)).joined(separator: "|")
        output = replace(output, pattern: "(?i)([\\\"']?[\\w.-]*(?:\(names))[\\w.-]*[\\\"']?\\s*[:=]\\s*)(\\\"(?:\\\\.|[^\\\"\\\\])*\\\"|'[^']*'|[^&\\s,;}]+)", template: "$1\(hidden)")
        output = replace(output, pattern: "(?i)\\bBasic\\s+[A-Za-z0-9+/=_-]+", template: "Basic \(hidden)")
        if includeIdentity {
            let pattern = #"https?://[^\s\"<>]+"#
            if let expression = try? NSRegularExpression(pattern: pattern) {
                for match in expression.matches(in: output, range: NSRange(output.startIndex..., in: output)).reversed() {
                    if let range = Range(match.range, in: output) { output.replaceSubrange(range, with: endpoint(URL(string: String(output[range])))) }
                }
            }
            output = replace(output, pattern: "(?i)(authorization|proxy-authorization|cookie|set-cookie|synjones-auth)\\s*[:=][^\\r\\n]*", template: "$1: \(hidden)")
            output = replace(output, pattern: "(?i)\\bBearer\\s+[^\\s,;\\\"]+", template: "Bearer \(hidden)")
            output = replace(output, pattern: "[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}", template: "[邮箱已隐藏]")
            output = replace(output, pattern: "\\b[A-Za-z]?\\d{8,14}\\b", template: "[账号已隐藏]")
        }
        return output
    }
    static func endpoint(_ url: URL?) -> String {
        guard let url, var parts = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return "unknown" }
        parts.user = nil; parts.password = nil; parts.query = nil; parts.fragment = nil
        return replace(parts.string ?? "unknown", pattern: "\\b[A-Za-z]?\\d{8,14}\\b", template: "[账号已隐藏]")
    }
    static func body(_ data: Data?, contentType: String?) -> String {
        guard let data, !data.isEmpty else { return "" }
        guard data.count <= 256 * 1024 else { return "[正文超过256KiB，未采集]" }
        let type = contentType?.lowercased() ?? ""
        guard !type.contains("multipart"), !type.contains("image"), !type.contains("octet-stream"),
              let text = String(data: data, encoding: .utf8) else { return "[二进制正文未采集]" }
        // HTML login pages can contain credentials in attributes and scripts.
        guard !type.contains("html"), !text.trimmingCharacters(in: .whitespaces).hasPrefix("<") else { return "[HTML正文未采集]" }
        return redacted(text, includeIdentity: false)
    }
    static func headers(_ values: [String: String]) -> String {
        values.sorted { $0.key < $1.key }.map { key, value in
            let lower = key.lowercased()
            return "\(key): \(lower.contains("key") || lower.contains("secret") ? hidden : value)"
        }.joined(separator: "\n")
    }
    private static func replace(_ input: String, pattern: String, template: String) -> String {
        input.replacingOccurrences(of: pattern, with: template, options: .regularExpression)
    }
}

extension URLSession {
    /// Wraps only App-owned data requests; never intercepts Sentry, WebKit or a
    /// streamed download. Bodies stay in memory until the user selects them.
    func diagnosticData(for request: URLRequest, delegate: (any URLSessionTaskDelegate)? = nil) async throws -> (Data, URLResponse) {
        guard let generation = DiagnosticLog.shared.activeGeneration else { return try await data(for: request, delegate: delegate) }
        let started = ProcessInfo.processInfo.systemUptime
        let span = AppDiagnostics.shared.startNetwork(request, generation: generation)
        do {
            let (data, response) = try await self.data(for: request, delegate: delegate)
            AppDiagnostics.shared.recordNetwork(request, response: response as? HTTPURLResponse, data: data,
                error: nil, generation: generation, started: started, span: span)
            return (data, response)
        } catch {
            AppDiagnostics.shared.recordNetwork(request, response: nil, data: nil, error: error,
                generation: generation, started: started, span: span)
            throw error
        }
    }
}
