import Foundation

struct OfficialPaymentPortalProbeReport: Equatable, Sendable {
    let statusCode: Int
    let redirectHost: String
    let redirectPath: String
    let elapsedMilliseconds: Int
    let checkedAt: Date

    var accessibilitySummary: String {
        "通过，HTTP \(statusCode)，\(redirectHost)\(redirectPath)，未发起扣款请求"
    }
}

enum OfficialPaymentPortalProbeFailure: Equatable, Sendable {
    case cancelled
    case timedOut
    case offline
    case transportUnavailable
    case unexpectedStatus(Int)
    case missingRedirect
    case unsafeRedirect
    case invalidDemoConfiguration

    var message: String {
        switch self {
        case .cancelled:
            "探测已取消"
        case .timedOut:
            "连接学校官方入口超时，请稍后重试"
        case .offline:
            "当前网络不可用，请检查网络后重试"
        case .transportUnavailable:
            "无法读取学校官方入口响应，请稍后重试"
        case let .unexpectedStatus(statusCode):
            "学校官方入口返回了非预期状态（HTTP \(statusCode)）"
        case .missingRedirect:
            "学校官方入口没有返回预期的登录跳转"
        case .unsafeRedirect:
            "学校官方入口返回了未通过校方 HTTPS 白名单的跳转"
        case .invalidDemoConfiguration:
            "测试探测参数无效，未执行网络请求"
        }
    }

    var logCode: String {
        switch self {
        case .cancelled: "cancelled"
        case .timedOut: "timed_out"
        case .offline: "offline"
        case .transportUnavailable: "transport_unavailable"
        case let .unexpectedStatus(statusCode): "unexpected_status_\(statusCode)"
        case .missingRedirect: "missing_redirect"
        case .unsafeRedirect: "unsafe_redirect"
        case .invalidDemoConfiguration: "invalid_demo_configuration"
        }
    }
}

enum OfficialPaymentPortalProbeOutcome: Equatable, Sendable {
    case passed(OfficialPaymentPortalProbeReport)
    case failed(OfficialPaymentPortalProbeFailure)
}

enum OfficialPaymentPortalProbePhase: Equatable, Sendable {
    case idle
    case running
    case passed(OfficialPaymentPortalProbeReport)
    case failed(OfficialPaymentPortalProbeFailure)
}

protocol OfficialPaymentPortalProbing: Sendable {
    func probe() async -> OfficialPaymentPortalProbeOutcome
}

protocol OfficialPaymentPortalProbeTransport: Sendable {
    func response(for request: URLRequest) async throws -> HTTPURLResponse
}

private enum OfficialPaymentPortalProbeTransportError: Error, Sendable {
    case invalidResponse
}

private final class OfficialPaymentPortalNoRedirectDelegate:
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

final class URLSessionOfficialPaymentPortalProbeTransport:
    OfficialPaymentPortalProbeTransport,
    @unchecked Sendable
{
    private let redirectDelegate: OfficialPaymentPortalNoRedirectDelegate
    private let session: URLSession

    init() {
        let redirectDelegate = OfficialPaymentPortalNoRedirectDelegate()
        self.redirectDelegate = redirectDelegate
        session = URLSession(
            configuration: Self.makeConfiguration(),
            delegate: redirectDelegate,
            delegateQueue: nil
        )
    }

    init(configuration: URLSessionConfiguration) {
        let redirectDelegate = OfficialPaymentPortalNoRedirectDelegate()
        self.redirectDelegate = redirectDelegate
        session = URLSession(
            configuration: configuration,
            delegate: redirectDelegate,
            delegateQueue: nil
        )
    }

    deinit {
        session.invalidateAndCancel()
    }

    func response(for request: URLRequest) async throws -> HTTPURLResponse {
        let (_, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else {
            throw OfficialPaymentPortalProbeTransportError.invalidResponse
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
        configuration.timeoutIntervalForRequest = 12
        configuration.timeoutIntervalForResource = 12
        configuration.waitsForConnectivity = false
        return configuration
    }
}

struct OfficialPaymentPortalProbeService: OfficialPaymentPortalProbing {
    private let transport: any OfficialPaymentPortalProbeTransport
    private let now: @Sendable () -> Date
    private let logger = RedactingLogger(category: "payment-probe")

    init(
        transport: (any OfficialPaymentPortalProbeTransport)? = nil,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.transport = transport
            ?? URLSessionOfficialPaymentPortalProbeTransport()
        self.now = now
    }

    func probe() async -> OfficialPaymentPortalProbeOutcome {
        let startedAt = now()
        let request = Self.makeRequest()

        do {
            let response = try await transport.response(for: request)
            try Task.checkCancellation()
            let outcome = Self.evaluate(
                response: response,
                elapsedMilliseconds: elapsedMilliseconds(since: startedAt),
                checkedAt: now()
            )
            log(outcome)
            return outcome
        } catch is CancellationError {
            return .failed(.cancelled)
        } catch let error as URLError {
            let failure = Self.failure(for: error)
            logger.notice(
                "official payment portal probe result=failed reason=\(failure.logCode)"
            )
            return .failed(failure)
        } catch {
            logger.notice(
                "official payment portal probe result=failed reason=transport_unavailable"
            )
            return .failed(.transportUnavailable)
        }
    }

    static func makeRequest() -> URLRequest {
        var request = URLRequest(
            url: OfficialSchoolPaymentPortal.loginURL,
            cachePolicy: .reloadIgnoringLocalAndRemoteCacheData,
            timeoutInterval: 12
        )
        request.httpMethod = "HEAD"
        request.httpBody = nil
        request.httpShouldHandleCookies = false
        request.setValue("no-store", forHTTPHeaderField: "Cache-Control")
        request.setValue(
            "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
            forHTTPHeaderField: "Accept"
        )
        return request
    }

    static func evaluate(
        response: HTTPURLResponse,
        elapsedMilliseconds: Int,
        checkedAt: Date
    ) -> OfficialPaymentPortalProbeOutcome {
        guard response.url == OfficialSchoolPaymentPortal.loginURL else {
            return .failed(.unsafeRedirect)
        }
        guard response.statusCode == 302 else {
            return .failed(.unexpectedStatus(response.statusCode))
        }
        guard let location = response.value(forHTTPHeaderField: "Location"),
              let redirectURL = URL(
                  string: location,
                  relativeTo: response.url
              )?.absoluteURL else {
            return .failed(.missingRedirect)
        }
        guard redirectURL.scheme?.lowercased() == "https",
              redirectURL.host?.lowercased() == "ycard.ahu.edu.cn",
              redirectURL.port == nil || redirectURL.port == 443,
              redirectURL.user == nil,
              redirectURL.password == nil,
              redirectURL.path == "/berserker-auth/cas/login/neusoftCas",
              redirectURL.fragment == nil,
              hasExpectedRedirectQuery(redirectURL) else {
            return .failed(.unsafeRedirect)
        }

        return .passed(OfficialPaymentPortalProbeReport(
            statusCode: response.statusCode,
            redirectHost: "ycard.ahu.edu.cn",
            redirectPath: "/berserker-auth/cas/login/neusoftCas",
            elapsedMilliseconds: max(0, elapsedMilliseconds),
            checkedAt: checkedAt
        ))
    }

    private static func hasExpectedRedirectQuery(_ url: URL) -> Bool {
        guard let items = URLComponents(
            url: url,
            resolvingAgainstBaseURL: false
        )?.queryItems,
              items.count == 1,
              items[0].name == "redirectUrl",
              let rawTarget = items[0].value,
              let target = URL(string: rawTarget),
              target.scheme?.lowercased() == "https",
              target.host?.lowercased() == "ycard.ahu.edu.cn",
              target.port == nil || target.port == 443,
              target.user == nil,
              target.password == nil,
              target.path == "/plat/",
              target.fragment == nil,
              let targetItems = URLComponents(
                  url: target,
                  resolvingAgainstBaseURL: false
              )?.queryItems,
              targetItems.count == 1,
              targetItems[0].name == "name",
              targetItems[0].value == "loginTransit" else {
            return false
        }
        return true
    }

    private static func failure(
        for error: URLError
    ) -> OfficialPaymentPortalProbeFailure {
        switch error.code {
        case .cancelled:
            .cancelled
        case .timedOut:
            .timedOut
        case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed:
            .offline
        default:
            .transportUnavailable
        }
    }

    private func elapsedMilliseconds(since startedAt: Date) -> Int {
        Int(max(0, now().timeIntervalSince(startedAt) * 1_000))
    }

    private func log(_ outcome: OfficialPaymentPortalProbeOutcome) {
        switch outcome {
        case let .passed(report):
            logger.notice(
                "official payment portal probe result=passed status=\(report.statusCode) "
                    + "host=\(report.redirectHost) path=\(report.redirectPath)"
            )
        case let .failed(failure):
            logger.notice(
                "official payment portal probe result=failed reason=\(failure.logCode)"
            )
        }
    }
}

enum OfficialPaymentPortalProbeFactory {
    static func make(
        arguments: [String] = ProcessInfo.processInfo.arguments,
        isDemoSession: Bool = AppRuntime.isDemoSession
    ) -> any OfficialPaymentPortalProbing {
        let prefix = "--demo-payment-probe="
        guard isDemoSession else {
            return OfficialPaymentPortalProbeService()
        }
        guard let value = arguments
            .first(where: { $0.hasPrefix(prefix) })
            .map({ String($0.dropFirst(prefix.count)) }) else {
            return DemoOfficialPaymentPortalProbe(
                mode: .invalidConfiguration
            )
        }

        let mode: DemoOfficialPaymentPortalProbe.Mode = switch value {
        case "success": .success
        case "unsafe-redirect": .unsafeRedirect
        case "offline": .offline
        default: .invalidConfiguration
        }
        return DemoOfficialPaymentPortalProbe(mode: mode)
    }
}

struct DemoOfficialPaymentPortalProbe: OfficialPaymentPortalProbing {
    enum Mode: Sendable {
        case success
        case unsafeRedirect
        case offline
        case invalidConfiguration
    }

    let mode: Mode

    func probe() async -> OfficialPaymentPortalProbeOutcome {
        try? await Task.sleep(for: .milliseconds(180))
        guard !Task.isCancelled else { return .failed(.cancelled) }

        switch mode {
        case .success:
            return .passed(OfficialPaymentPortalProbeReport(
                statusCode: 302,
                redirectHost: "ycard.ahu.edu.cn",
                redirectPath: "/berserker-auth/cas/login/neusoftCas",
                elapsedMilliseconds: 180,
                checkedAt: Date(timeIntervalSince1970: 1_784_023_200)
            ))
        case .unsafeRedirect:
            return .failed(.unsafeRedirect)
        case .offline:
            return .failed(.offline)
        case .invalidConfiguration:
            return .failed(.invalidDemoConfiguration)
        }
    }
}
