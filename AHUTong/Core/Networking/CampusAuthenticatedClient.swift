import Foundation

extension Notification.Name {
    static let campusCredentialsRejected = Notification.Name("AHUTong.campusCredentialsRejected")
    static let campusReauthenticationRequired = Notification.Name("AHUTong.campusReauthenticationRequired")
}

enum CampusWebError: LocalizedError, Equatable, Sendable {
    case unauthorized
    case invalidResponse
    case server(String)

    var errorDescription: String? {
        switch self {
        case .unauthorized: "登录状态已失效，请重新登录"
        case .invalidResponse: "校园服务返回了无法识别的数据"
        case let .server(message): message
        }
    }
}

struct CampusCookie: Codable, Equatable, Sendable {
    let name: String
    let value: String
    let domain: String
    let path: String?
    let secure: Bool?
    let httpOnly: Bool?

    enum CodingKeys: String, CodingKey {
        case name, value, domain, path, secure
        case httpOnly = "http_only"
    }

    func matches(_ url: URL) -> Bool {
        let host = url.host?.lowercased() ?? ""
        let normalizedDomain = domain.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
        let matchesDomain = host == normalizedDomain || host.hasSuffix(".\(normalizedDomain)")
        let requestPath = url.path.isEmpty ? "/" : url.path
        let cookiePath = Self.normalizedPath(path)
        let matchesPath = requestPath == cookiePath
            || (requestPath.hasPrefix(cookiePath)
                && (cookiePath.hasSuffix("/")
                    || requestPath.dropFirst(cookiePath.count).first == "/"))
        let matchesSecurity = secure != true || url.scheme?.lowercased() == "https"
        return matchesDomain && matchesPath && matchesSecurity
    }

    static func normalizedPath(_ path: String?) -> String {
        guard let path,
              !path.isEmpty,
              path.hasPrefix("/") else {
            return "/"
        }
        return path
    }

    func isScoped(to serviceURL: URL) -> Bool {
        guard matches(serviceURL) else { return false }
        let cookiePath = (path ?? "/").trimmingCharacters(in: .whitespacesAndNewlines)
        guard cookiePath != "/", !cookiePath.isEmpty else {
            // Root cookies carry the shared CAS/JWXT session. Clearing them
            // for one feature would log every other campus service out.
            return false
        }
        let normalizedCookiePath = cookiePath.hasSuffix("/")
            ? String(cookiePath.dropLast())
            : cookiePath
        let normalizedServicePath = serviceURL.path.hasSuffix("/")
            ? String(serviceURL.path.dropLast())
            : serviceURL.path
        return normalizedServicePath == normalizedCookiePath
            || normalizedServicePath.hasPrefix("\(normalizedCookiePath)/")
    }
}

enum CampusCookieResponsePolicy {
    static func merge(
        _ received: [HTTPCookie],
        into cookies: inout [CampusCookie],
        now: Date = Date(),
        identityIsAllowed: (CampusCookie) -> Bool = { _ in true },
        storedCookieIsAllowed: (CampusCookie) -> Bool = { _ in true }
    ) {
        for receivedCookie in received {
            let cookie = CampusCookie(
                name: receivedCookie.name,
                value: receivedCookie.value,
                domain: receivedCookie.domain,
                path: receivedCookie.path,
                secure: receivedCookie.isSecure,
                httpOnly: receivedCookie.properties?[
                    HTTPCookiePropertyKey(rawValue: "HttpOnly")
                ] != nil
            )
            guard identityIsAllowed(cookie) else { continue }
            cookies.removeAll { hasSameIdentity($0, cookie) }
            guard !shouldDelete(receivedCookie, now: now),
                  storedCookieIsAllowed(cookie) else {
                continue
            }
            cookies.append(cookie)
        }
    }

    static func shouldDelete(
        _ cookie: HTTPCookie,
        now: Date = Date()
    ) -> Bool {
        if cookie.value.isEmpty { return true }
        if let expiresDate = cookie.expiresDate, expiresDate <= now {
            return true
        }
        guard let maximumAge = cookie.properties?[.maximumAge] else {
            return false
        }
        if let value = maximumAge as? NSNumber {
            return value.doubleValue <= 0
        }
        if let value = maximumAge as? String,
           let seconds = Double(value.trimmingCharacters(
               in: .whitespacesAndNewlines
           )) {
            return seconds <= 0
        }
        return false
    }

    private static func hasSameIdentity(
        _ lhs: CampusCookie,
        _ rhs: CampusCookie
    ) -> Bool {
        lhs.name == rhs.name
            && normalizedDomain(lhs.domain) == normalizedDomain(rhs.domain)
            && CampusCookie.normalizedPath(lhs.path)
                == CampusCookie.normalizedPath(rhs.path)
    }

    private static func normalizedDomain(_ value: String) -> String {
        value.lowercased().trimmingCharacters(
            in: CharacterSet(charactersIn: ".")
        )
    }

}

struct CampusHTTPResponse: Sendable {
    let data: Data
    let statusCode: Int
    let finalURL: URL?
    let headers: [String: String]

    func header(_ name: String) -> String? {
        headers.first { $0.key.caseInsensitiveCompare(name) == .orderedSame }?.value
    }
}

enum CampusSessionExpiryDetector {
    static func isExpiredURL(_ url: URL?) -> Bool {
        isLoginURL(url)
    }

    static func isExpired(response: HTTPURLResponse, data: Data) -> Bool {
        if response.statusCode == 401 || response.statusCode == 403 {
            return true
        }

        if isExpiredURL(response.url) {
            return true
        }

        let redirect = response.value(forHTTPHeaderField: "Location")
        if isLoginLocation(redirect) {
            return true
        }

        return isLoginHTML(
            data,
            contentType: response.value(forHTTPHeaderField: "Content-Type")
        )
    }

    private static func isLoginURL(_ url: URL?) -> Bool {
        guard let url else { return false }
        let path = url.path.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let schoolHost = url.host?.lowercased().hasSuffix(".ahu.edu.cn") == true
            || url.host?.lowercased() == "ahu.edu.cn"
        return path.hasSuffix("cas/login")
            || path.hasSuffix("student/sso/login")
            || (schoolHost && path == "login")
            || path.contains("tologin")
            || path.hasSuffix("refer")
    }

    private static func isLoginLocation(_ location: String?) -> Bool {
        guard let location else { return false }
        let value = location.lowercased()
        if value == "/login" || value.hasPrefix("/login?") {
            return true
        }
        if let url = URL(string: value),
           url.host?.hasSuffix(".ahu.edu.cn") == true,
           url.path == "/login" {
            return true
        }
        return value.contains("/cas/login")
            || value.contains("/student/sso/login")
            || value.contains("tologin")
            || value.contains("/refer")
    }

    private static func isLoginHTML(_ data: Data, contentType: String?) -> Bool {
        guard !data.isEmpty else { return false }
        let prefix = String(decoding: data.prefix(128 * 1024), as: UTF8.self)
        let trimmed = prefix.trimmingCharacters(in: .whitespacesAndNewlines)
        let looksLikeHTML = contentType?.localizedCaseInsensitiveContains("text/html") == true
            || trimmed.hasPrefix("<!DOCTYPE html")
            || trimmed.hasPrefix("<!doctype html")
            || trimmed.hasPrefix("<html")
        guard looksLikeHTML else { return false }
        let lowercase = prefix.lowercased()
        return lowercase.contains("id=\"loginform\"")
            || lowercase.contains("id='loginform'")
            || prefix.contains("<title>登入页面</title>")
            || ((lowercase.contains("name=\"username\"")
                || lowercase.contains("name='username'"))
                && (lowercase.contains("name=\"password\"")
                    || lowercase.contains("name='password'"))
                && (lowercase.contains("/cas/") || lowercase.contains("login")))
    }
}

private final class CampusRedirectBlockingDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
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

actor CampusAuthenticatedClient {
    private let campusAPI: any CampusCoreAPI
    private let session: URLSession
    private let refreshCoordinator: SessionRefreshCoordinator
    private let logger = RedactingLogger(category: "campus-web")

    init(
        campusAPI: any CampusCoreAPI,
        session: URLSession = .shared,
        refreshCoordinator: SessionRefreshCoordinator = .shared
    ) {
        self.campusAPI = campusAPI
        self.session = session
        self.refreshCoordinator = refreshCoordinator
    }

    func data(
        url: URL,
        method: String = "GET",
        body: Data? = nil,
        contentType: String? = nil
    ) async throws -> Data {
        try await response(
            url: url,
            method: method,
            body: body,
            contentType: contentType,
            headers: [:],
            followsRedirects: true,
            mayRefreshSession: true,
            retryPolicy: .automatic(forHTTPMethod: method)
        ).data
    }

    func response(
        url: URL,
        method: String = "GET",
        body: Data? = nil,
        contentType: String? = nil,
        headers: [String: String] = [:],
        followsRedirects: Bool = true,
        refreshesSessionOnUnauthorized: Bool = true,
        retryPolicy: CampusRequestRetryPolicy? = nil
    ) async throws -> CampusHTTPResponse {
        try await response(
            url: url,
            method: method,
            body: body,
            contentType: contentType,
            headers: headers,
            followsRedirects: followsRedirects,
            mayRefreshSession: refreshesSessionOnUnauthorized,
            retryPolicy: retryPolicy ?? .automatic(forHTTPMethod: method)
        )
    }

    @discardableResult
    func clearCookies(matching url: URL) async throws -> Int {
        try await clearCookies { $0.matches(url) }
    }

    @discardableResult
    func clearCookies(scopedTo serviceURL: URL) async throws -> Int {
        try await clearCookies { $0.isScoped(to: serviceURL) }
    }

    private func clearCookies(
        where shouldRemove: (CampusCookie) -> Bool
    ) async throws -> Int {
        let rawCookies = try await campusAPI.cookiesFlat()
        let cookies: [CampusCookie]
        do {
            cookies = try JSONDecoder().decode([CampusCookie].self, from: Data(rawCookies.utf8))
        } catch {
            throw CampusWebError.invalidResponse
        }
        let retained = cookies.filter { !shouldRemove($0) }
        let removedCount = cookies.count - retained.count
        guard removedCount > 0 else { return 0 }
        let json = String(decoding: try JSONEncoder().encode(retained), as: UTF8.self)
        try await campusAPI.initialize(cookiesJSON: json)
        try await campusAPI.persistSessionCookies()
        return removedCount
    }

    private func response(
        url: URL,
        method: String,
        body: Data?,
        contentType: String?,
        headers: [String: String],
        followsRedirects: Bool,
        mayRefreshSession: Bool,
        retryPolicy: CampusRequestRetryPolicy
    ) async throws -> CampusHTTPResponse {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.httpBody = body
        request.timeoutInterval = 30
        request.setValue("XMLHttpRequest", forHTTPHeaderField: "X-Requested-With")
        if let contentType { request.setValue(contentType, forHTTPHeaderField: "Content-Type") }
        headers.forEach { request.setValue($0.value, forHTTPHeaderField: $0.key) }

        let rawCookies = try await campusAPI.cookiesFlat()
        let cookies = (try? JSONDecoder().decode([CampusCookie].self, from: Data(rawCookies.utf8))) ?? []
        let header = cookies
            .filter { $0.matches(url) }
            .map { "\($0.name)=\($0.value)" }
            .joined(separator: "; ")
        if !header.isEmpty { request.setValue(header, forHTTPHeaderField: "Cookie") }

        let redirectDelegate = followsRedirects ? nil : CampusRedirectBlockingDelegate()
        let (data, response) = try await session.data(for: request, delegate: redirectDelegate)
        guard let response = response as? HTTPURLResponse else { throw CampusWebError.invalidResponse }
        try await persistResponseCookies(response, for: response.url ?? url, existing: cookies)
        let responseHeaders = response.allHeaderFields.reduce(into: [String: String]()) { result, item in
            guard let key = item.key as? String else { return }
            result[key] = String(describing: item.value)
        }
        if CampusSessionExpiryDetector.isExpired(response: response, data: data) {
            if mayRefreshSession {
                logger.notice("Campus web session expired; refreshing path=\(url.path)")
                try await refreshCoordinator.refresh { [campusAPI] in
                    try await campusAPI.refreshSession()
                }
                guard retryPolicy.allowsAutomaticRetry else {
                    throw CampusWebError.unauthorized
                }
                return try await self.response(
                    url: url,
                    method: method,
                    body: body,
                    contentType: contentType,
                    headers: headers,
                    followsRedirects: followsRedirects,
                    mayRefreshSession: false,
                    retryPolicy: retryPolicy
                )
            }
            if retryPolicy.allowsAutomaticRetry {
                await campusAPI.invalidateStoredSession()
            }
            throw CampusWebError.unauthorized
        }
        let acceptedRedirect = !followsRedirects && (300..<400).contains(response.statusCode)
        guard (200..<300).contains(response.statusCode) || acceptedRedirect else {
            logger.notice("Campus web request failed status=\(response.statusCode) path=\(url.path)")
            throw CampusWebError.server("校园服务请求失败（\(response.statusCode)）")
        }
        return CampusHTTPResponse(
            data: data,
            statusCode: response.statusCode,
            finalURL: response.url,
            headers: responseHeaders
        )
    }

    private func persistResponseCookies(
        _ response: HTTPURLResponse,
        for url: URL,
        existing: [CampusCookie]
    ) async throws {
        let fields = response.allHeaderFields.reduce(into: [String: String]()) { result, item in
            guard let key = item.key as? String, let value = item.value as? String else { return }
            result[key] = value
        }
        let received = HTTPCookie.cookies(withResponseHeaderFields: fields, for: url)
        guard !received.isEmpty else { return }

        var merged = existing
        CampusCookieResponsePolicy.merge(received, into: &merged)
        let json = String(decoding: try JSONEncoder().encode(merged), as: UTF8.self)
        try await campusAPI.initialize(cookiesJSON: json)
        try await campusAPI.persistSessionCookies()
    }

}

extension URL {
    func appendingQueryItems(_ items: [URLQueryItem]) -> URL {
        var components = URLComponents(url: self, resolvingAgainstBaseURL: false)
        components?.queryItems = items
        return components?.url ?? self
    }
}
