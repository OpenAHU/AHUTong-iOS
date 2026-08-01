import Foundation
import SwiftUI

enum CMBRechargeAcceptanceCheckID: String, CaseIterable, Sendable {
    case physicalDevice
    case accessToken
    case cookieIsolation
    case entryURL
    case redirectChain
    case chargeRoute
    case safetyBoundary

    var title: String {
        switch self {
        case .physicalDevice: "运行设备"
        case .accessToken: "校园卡凭证"
        case .cookieIsolation: "Cookie 隔离"
        case .entryURL: "校方充值入口"
        case .redirectChain: "受控跳转链"
        case .chargeRoute: "扣款前页面路由"
        case .safetyBoundary: "无扣款请求边界"
        }
    }
}

enum CMBRechargeAcceptanceOutcome: String, Equatable, Sendable {
    case pending
    case passed
    case warning
    case failed

    var symbol: String {
        switch self {
        case .pending: "○"
        case .passed: "✓"
        case .warning: "△"
        case .failed: "✕"
        }
    }
}

struct CMBRechargeAcceptanceCheck: Identifiable, Equatable, Sendable {
    let id: CMBRechargeAcceptanceCheckID
    var outcome: CMBRechargeAcceptanceOutcome
    var detail: String
}

enum CMBRechargeAcceptanceCompletion: Equatable, Sendable {
    case running
    case physicalDevicePassed
    case simulatorPreviewPassed
    case failed

    var title: String {
        switch self {
        case .running: "验收进行中"
        case .physicalDevicePassed: "实体机扣款前探测通过"
        case .simulatorPreviewPassed: "模拟器扣款前预检通过"
        case .failed: "验收未通过"
        }
    }
}

enum CMBRechargeAcceptanceFailure: Error, Equatable, Sendable {
    case invalidBootstrap
    case missingRedirect
    case unsafeRedirect
    case unexpectedStatus(Int)
    case redirectLimit
    case chargeRouteNotReached
    case transportUnavailable

    var message: String {
        switch self {
        case .invalidBootstrap:
            "校园卡扣款前入口不符合安全契约"
        case .missingRedirect:
            "校方响应缺少下一跳地址"
        case .unsafeRedirect:
            "校方响应指向未获准的目标，已停止探测"
        case let .unexpectedStatus(statusCode):
            "校方扣款前链路返回异常状态（HTTP \(statusCode)）"
        case .redirectLimit:
            "校方跳转次数超过安全上限，已停止探测"
        case .chargeRouteNotReached:
            "HEAD 链路未到达已知扣款前页面；未执行网页脚本"
        case .transportUnavailable:
            "校方扣款前链路暂不可用，请检查网络后重试"
        }
    }
}

struct CMBRechargeAcceptanceSnapshot: Equatable, Sendable {
    let generatedAt: Date
    let isPhysicalDevice: Bool
    private(set) var checks: [CMBRechargeAcceptanceCheck]

    init(
        isPhysicalDevice: Bool,
        generatedAt: Date = Date()
    ) {
        self.generatedAt = generatedAt
        self.isPhysicalDevice = isPhysicalDevice
        checks = CMBRechargeAcceptanceCheckID.allCases.map { id in
            if id == .physicalDevice {
                return CMBRechargeAcceptanceCheck(
                    id: id,
                    outcome: isPhysicalDevice ? .passed : .warning,
                    detail: isPhysicalDevice ? "物理 iPhone" : "Simulator，仅能预检"
                )
            }
            return CMBRechargeAcceptanceCheck(
                id: id,
                outcome: .pending,
                detail: "等待检查"
            )
        }
    }

    var completion: CMBRechargeAcceptanceCompletion {
        if checks.contains(where: { $0.outcome == .failed }) {
            return .failed
        }
        let required: [CMBRechargeAcceptanceCheckID] = [
            .accessToken,
            .cookieIsolation,
            .entryURL,
            .redirectChain,
            .chargeRoute,
            .safetyBoundary
        ]
        guard required.allSatisfy({ outcome(for: $0) == .passed }) else {
            return .running
        }
        return isPhysicalDevice ? .physicalDevicePassed : .simulatorPreviewPassed
    }

    var exportText: String {
        let formatter = ISO8601DateFormatter()
        let lines = checks.map { check in
            "\(check.outcome.symbol) \(check.id.title)：\(check.detail)"
        }
        return ([
            "AHUTong iOS 招商银行充值扣款前 HEAD 探测",
            "时间：\(formatter.string(from: generatedAt))",
            "结论：\(completion.title)",
            "安全声明：仅发送 HEAD；不执行 JavaScript、不加载网页资源、不提交请求体。",
            "隐私声明：本报告不包含账号、Token、Cookie 值、金额、订单号或查询参数。"
        ] + lines).joined(separator: "\n")
    }

    mutating func recordBootstrap(
        entryURL: URL,
        cookies: [CampusCookie]
    ) {
        guard CMBRechargeAcceptancePolicy.isValidEntryURL(entryURL) else {
            recordFailure(.invalidBootstrap)
            return
        }
        set(
            .accessToken,
            outcome: .passed,
            detail: "已取得一次性凭证（未记录内容）"
        )
        set(
            .entryURL,
            outcome: .passed,
            detail: CMBRechargeAcceptancePolicy.sanitizedRoute(entryURL)
        )
        let eligibleCount = CMBRechargeAcceptancePolicy.eligibleCookies(cookies).count
        set(
            .cookieIsolation,
            outcome: .passed,
            detail: eligibleCount == 0
                ? "无匹配 Cookie；本次不会发送 Cookie"
                : "仅内存筛选 \(eligibleCount) 个匹配 Cookie（未记录名称和值）"
        )
        set(
            .safetyBoundary,
            outcome: .passed,
            detail: "临时会话仅允许 HEAD；无请求体、JavaScript、资源加载或自动跳转"
        )
    }

    mutating func recordRedirect(
        from sourceURL: URL,
        statusCode: Int,
        to destinationURL: URL,
        hop: Int
    ) {
        guard !checks.contains(where: { $0.outcome == .failed }) else { return }
        set(
            .redirectChain,
            outcome: .passed,
            detail: "第 \(hop) 跳 HTTP \(statusCode)："
                + "\(CMBRechargeAcceptancePolicy.sanitizedRoute(sourceURL)) → "
                + CMBRechargeAcceptancePolicy.sanitizedRoute(destinationURL)
        )
    }

    mutating func recordChargeRoute(
        _ url: URL,
        statusCode: Int,
        hopCount: Int
    ) {
        guard !checks.contains(where: { $0.outcome == .failed }) else { return }
        set(
            .redirectChain,
            outcome: .passed,
            detail: "\(hopCount) 次受控跳转；最终 HTTP \(statusCode)"
        )
        set(
            .chargeRoute,
            outcome: .passed,
            detail: CMBRechargeAcceptancePolicy.sanitizedRoute(url)
        )
    }

    mutating func recordFailure(_ failure: CMBRechargeAcceptanceFailure) {
        guard !checks.contains(where: { $0.outcome == .failed }) else { return }
        switch failure {
        case .invalidBootstrap:
            set(.entryURL, outcome: .failed, detail: failure.message)
        case .missingRedirect, .unsafeRedirect, .redirectLimit:
            set(.redirectChain, outcome: .failed, detail: failure.message)
        case .unexpectedStatus, .chargeRouteNotReached, .transportUnavailable:
            set(.chargeRoute, outcome: .failed, detail: failure.message)
        }
    }

    private func outcome(
        for id: CMBRechargeAcceptanceCheckID
    ) -> CMBRechargeAcceptanceOutcome? {
        checks.first(where: { $0.id == id })?.outcome
    }

    private mutating func set(
        _ id: CMBRechargeAcceptanceCheckID,
        outcome: CMBRechargeAcceptanceOutcome,
        detail: String
    ) {
        guard let index = checks.firstIndex(where: { $0.id == id }) else { return }
        checks[index].outcome = outcome
        checks[index].detail = detail
    }
}

enum CMBRechargeAcceptancePolicy {
    static let maximumRedirects = 8
    private static let allowedHosts: Set<String> = [
        "ycard.ahu.edu.cn",
        "epay92.ahu.edu.cn"
    ]

    static func isAllowedURL(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "https",
              let host = url.host?.lowercased(),
              allowedHosts.contains(host),
              url.user == nil,
              url.password == nil,
              url.port == nil || url.port == 443 else {
            return false
        }
        return true
    }

    static func isValidEntryURL(_ url: URL) -> Bool {
        guard isAllowedURL(url),
              url.host?.lowercased() == "ycard.ahu.edu.cn",
              url.path == "/berserker-base/redirect",
              url.fragment == nil,
              let items = URLComponents(
                  url: url,
                  resolvingAgainstBaseURL: false
              )?.queryItems,
              Set(items.map(\.name)).count == items.count else {
            return false
        }
        let values = Dictionary(uniqueKeysWithValues:
            items.map { ($0.name, $0.value ?? "") }
        )
        return Set(values.keys) == [
            "appId",
            "loginFrom",
            "synAccessSource",
            "synjones-auth",
            "type"
        ]
            && values["appId"] == "253"
            && values["loginFrom"] == "h5"
            && values["synAccessSource"] == "h5"
            && !(values["synjones-auth"] ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .isEmpty
            && values["type"] == "app"
    }

    static func isChargeRoute(_ url: URL) -> Bool {
        guard isAllowedURL(url) else { return false }
        return hasPathPrefix(url.path, prefix: "/cashier-mobile/charge")
            || hasPathPrefix(url.path, prefix: "/charge-app")
    }

    static func makeHEADRequest(
        url: URL,
        cookies: [CampusCookie]
    ) throws -> URLRequest {
        guard isAllowedURL(url) else {
            throw CMBRechargeAcceptanceFailure.unsafeRedirect
        }
        var request = URLRequest(
            url: url,
            cachePolicy: .reloadIgnoringLocalAndRemoteCacheData,
            timeoutInterval: 15
        )
        request.httpMethod = "HEAD"
        request.httpBody = nil
        request.httpShouldHandleCookies = false
        request.setValue("no-store", forHTTPHeaderField: "Cache-Control")
        request.setValue(
            "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
            forHTTPHeaderField: "Accept"
        )
        if let header = cookieHeader(cookies, for: url) {
            request.setValue(header, forHTTPHeaderField: "Cookie")
        }
        return request
    }

    static func eligibleCookies(
        _ cookies: [CampusCookie]
    ) -> [CampusCookie] {
        cookies.filter { cookie in
            guard CampusCookieWebBridge.isTrustedSchoolCookie(cookie),
                  cookie.secure != false,
                  isSafeCookieName(cookie.name),
                  isSafeCookieValue(cookie.value) else {
                return false
            }
            let domain = normalizedDomain(cookie.domain)
            return allowedHosts.contains { host in
                host == domain || host.hasSuffix(".\(domain)")
            }
        }
    }

    static func mergeResponseCookies(
        _ response: HTTPURLResponse,
        requestURL: URL,
        into cookies: inout [CampusCookie]
    ) {
        let fields = response.allHeaderFields.reduce(into: [String: String]()) {
            result,
            item in
            guard let key = item.key as? String else { return }
            result[key] = String(describing: item.value)
        }
        let additions = HTTPCookie.cookies(
            withResponseHeaderFields: fields,
            for: response.url ?? requestURL
        )
        CampusCookieResponsePolicy.merge(
            additions,
            into: &cookies,
            identityIsAllowed: { cookie in
                guard CampusCookieWebBridge.isTrustedSchoolCookie(cookie),
                      isSafeCookieName(cookie.name) else {
                    return false
                }
                let domain = normalizedDomain(cookie.domain)
                return allowedHosts.contains { host in
                    host == domain || host.hasSuffix(".\(domain)")
                }
            },
            storedCookieIsAllowed: { cookie in
                eligibleCookies([cookie]).count == 1
            }
        )
    }

    static func sanitizedRoute(_ url: URL) -> String {
        guard let host = url.host?.lowercased() else {
            return "受控校方 HTTPS 路由"
        }
        return "https://\(host)\(url.path)"
    }

    private static func cookieHeader(
        _ cookies: [CampusCookie],
        for url: URL
    ) -> String? {
        var identities = Set<String>()
        let values = eligibleCookies(cookies)
            .filter { $0.matches(url) }
            .filter { cookie in
                let identity = [
                    cookie.name,
                    normalizedDomain(cookie.domain),
                    cookie.path ?? "/"
                ].joined(separator: "|")
                return identities.insert(identity).inserted
            }
            .map { "\($0.name)=\($0.value)" }
        return values.isEmpty ? nil : values.joined(separator: "; ")
    }

    private static func hasPathPrefix(
        _ path: String,
        prefix: String
    ) -> Bool {
        path == prefix || path.hasPrefix("\(prefix)/")
    }

    private static func normalizedDomain(_ value: String) -> String {
        value.lowercased().trimmingCharacters(
            in: CharacterSet(charactersIn: ".")
        )
    }

    private static func isSafeCookieName(_ value: String) -> Bool {
        !value.isEmpty && value.unicodeScalars.allSatisfy { scalar in
            scalar.value > 0x20
                && scalar.value < 0x7F
                && !"()<>@,;:\\\"/[]?={} \t".unicodeScalars.contains(scalar)
        }
    }

    private static func isSafeCookieValue(_ value: String) -> Bool {
        value.unicodeScalars.allSatisfy { scalar in
            let code = scalar.value
            return code == 0x21
                || (0x23...0x2B).contains(code)
                || (0x2D...0x3A).contains(code)
                || (0x3C...0x5B).contains(code)
                || (0x5D...0x7E).contains(code)
        }
    }
}

protocol CMBRechargeAcceptanceTransport: Sendable {
    func response(for request: URLRequest) async throws -> HTTPURLResponse
}

private final class CMBRechargeNoRedirectDelegate:
    NSObject,
    URLSessionTaskDelegate,
    @unchecked Sendable
{
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping @Sendable (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }
}

final class URLSessionCMBRechargeAcceptanceTransport:
    CMBRechargeAcceptanceTransport,
    @unchecked Sendable
{
    private let session: URLSession

    init() {
        self.session = URLSession(
            configuration: Self.makeConfiguration(),
            delegate: CMBRechargeNoRedirectDelegate(),
            delegateQueue: nil
        )
    }

    init(configuration: URLSessionConfiguration) {
        session = URLSession(
            configuration: configuration,
            delegate: CMBRechargeNoRedirectDelegate(),
            delegateQueue: nil
        )
    }

    deinit {
        session.invalidateAndCancel()
    }

    func response(for request: URLRequest) async throws -> HTTPURLResponse {
        let (_, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else {
            throw CMBRechargeAcceptanceFailure.transportUnavailable
        }
        return response
    }

    static func makeConfiguration() -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        configuration.urlCache = nil
        configuration.urlCredentialStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.httpCookieStorage = nil
        configuration.httpCookieAcceptPolicy = .never
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 30
        configuration.waitsForConnectivity = false
        return configuration
    }
}

struct CMBRechargeAcceptanceService: Sendable {
    private let transport: any CMBRechargeAcceptanceTransport
    private let now: @Sendable () -> Date

    init(
        transport: (any CMBRechargeAcceptanceTransport)? = nil,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.transport = transport
            ?? URLSessionCMBRechargeAcceptanceTransport()
        self.now = now
    }

    func probe(
        entryURL: URL,
        cookies: [CampusCookie],
        isPhysicalDevice: Bool
    ) async -> CMBRechargeAcceptanceSnapshot {
        var snapshot = CMBRechargeAcceptanceSnapshot(
            isPhysicalDevice: isPhysicalDevice,
            generatedAt: now()
        )
        snapshot.recordBootstrap(entryURL: entryURL, cookies: cookies)
        guard snapshot.completion != .failed else { return snapshot }

        var currentURL = entryURL
        var cookieJar = CMBRechargeAcceptancePolicy.eligibleCookies(cookies)
        var redirectCount = 0

        do {
            while redirectCount <= CMBRechargeAcceptancePolicy.maximumRedirects {
                try Task.checkCancellation()
                let request = try CMBRechargeAcceptancePolicy.makeHEADRequest(
                    url: currentURL,
                    cookies: cookieJar
                )
                let response = try await transport.response(for: request)
                try Task.checkCancellation()
                guard response.url == currentURL else {
                    snapshot.recordFailure(.unsafeRedirect)
                    return snapshot
                }
                CMBRechargeAcceptancePolicy.mergeResponseCookies(
                    response,
                    requestURL: currentURL,
                    into: &cookieJar
                )

                if (300..<400).contains(response.statusCode) {
                    guard redirectCount < CMBRechargeAcceptancePolicy.maximumRedirects else {
                        snapshot.recordFailure(.redirectLimit)
                        return snapshot
                    }
                    guard let rawLocation = response.value(
                        forHTTPHeaderField: "Location"
                    ),
                    let destinationURL = URL(
                        string: rawLocation,
                        relativeTo: currentURL
                    )?.absoluteURL else {
                        snapshot.recordFailure(.missingRedirect)
                        return snapshot
                    }
                    guard CMBRechargeAcceptancePolicy.isAllowedURL(destinationURL) else {
                        snapshot.recordFailure(.unsafeRedirect)
                        return snapshot
                    }
                    redirectCount += 1
                    snapshot.recordRedirect(
                        from: currentURL,
                        statusCode: response.statusCode,
                        to: destinationURL,
                        hop: redirectCount
                    )
                    currentURL = destinationURL
                    continue
                }

                guard (200..<300).contains(response.statusCode) else {
                    snapshot.recordFailure(.unexpectedStatus(response.statusCode))
                    return snapshot
                }
                guard CMBRechargeAcceptancePolicy.isChargeRoute(currentURL) else {
                    snapshot.recordFailure(.chargeRouteNotReached)
                    return snapshot
                }
                snapshot.recordChargeRoute(
                    currentURL,
                    statusCode: response.statusCode,
                    hopCount: redirectCount
                )
                return snapshot
            }
        } catch is CancellationError {
            return snapshot
        } catch let failure as CMBRechargeAcceptanceFailure {
            snapshot.recordFailure(failure)
            return snapshot
        } catch {
            snapshot.recordFailure(.transportUnavailable)
            return snapshot
        }

        snapshot.recordFailure(.redirectLimit)
        return snapshot
    }
}

enum CMBRechargeAcceptanceServiceFactory {
    static func make(
        isDemoSession: Bool = AppRuntime.isDemoSession
    ) -> CMBRechargeAcceptanceService {
        if isDemoSession {
            return CMBRechargeAcceptanceService(
                transport: DemoCMBRechargeAcceptanceTransport(),
                now: { Date(timeIntervalSince1970: 1_785_552_000) }
            )
        }
        return CMBRechargeAcceptanceService()
    }
}

private actor DemoCMBRechargeAcceptanceTransport:
    CMBRechargeAcceptanceTransport
{
    func response(for request: URLRequest) async throws -> HTTPURLResponse {
        guard let url = request.url else {
            throw CMBRechargeAcceptanceFailure.transportUnavailable
        }
        let location: String?
        let statusCode: Int
        if url.host?.lowercased() == "ycard.ahu.edu.cn" {
            statusCode = 302
            location = "https://epay92.ahu.edu.cn/charge-app"
        } else {
            statusCode = 200
            location = nil
        }
        return HTTPURLResponse(
            url: url,
            statusCode: statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: location.map { ["Location": $0] }
        )!
    }
}

@MainActor
final class CMBRechargeAcceptanceModel: ObservableObject {
    @Published private(set) var snapshot: CMBRechargeAcceptanceSnapshot

    private let service: CMBRechargeAcceptanceService
    private var generation = 0

    init() {
        service = CMBRechargeAcceptanceService()
        snapshot = CMBRechargeAcceptanceSnapshot(
            isPhysicalDevice: Self.isPhysicalDevice
        )
    }

    init(isPhysicalDevice: Bool) {
        service = CMBRechargeAcceptanceService()
        snapshot = CMBRechargeAcceptanceSnapshot(
            isPhysicalDevice: isPhysicalDevice
        )
    }

    init(service: CMBRechargeAcceptanceService) {
        self.service = service
        snapshot = CMBRechargeAcceptanceSnapshot(
            isPhysicalDevice: Self.isPhysicalDevice
        )
    }

    init(
        service: CMBRechargeAcceptanceService,
        isPhysicalDevice: Bool
    ) {
        self.service = service
        snapshot = CMBRechargeAcceptanceSnapshot(
            isPhysicalDevice: isPhysicalDevice
        )
    }

    func run(entryURL: URL, cookies: [CampusCookie]) async {
        generation += 1
        let requestGeneration = generation
        snapshot = CMBRechargeAcceptanceSnapshot(
            isPhysicalDevice: snapshot.isPhysicalDevice
        )
        let result = await service.probe(
            entryURL: entryURL,
            cookies: cookies,
            isPhysicalDevice: snapshot.isPhysicalDevice
        )
        guard requestGeneration == generation, !Task.isCancelled else { return }
        snapshot = result
    }

    func reset() {
        generation += 1
        snapshot = CMBRechargeAcceptanceSnapshot(
            isPhysicalDevice: snapshot.isPhysicalDevice
        )
    }

    func recordBootstrapFailure() {
        generation += 1
        snapshot = CMBRechargeAcceptanceSnapshot(
            isPhysicalDevice: snapshot.isPhysicalDevice
        )
        snapshot.recordFailure(.invalidBootstrap)
    }

    private static var isPhysicalDevice: Bool {
#if targetEnvironment(simulator)
        false
#else
        true
#endif
    }
}
