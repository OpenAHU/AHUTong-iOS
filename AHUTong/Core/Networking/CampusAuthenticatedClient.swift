import Foundation

extension Notification.Name {
    static let campusSessionExpired = Notification.Name("AHUTong.campusSessionExpired")
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
        let matchesPath = url.path.hasPrefix(path ?? "/")
        let matchesSecurity = secure != true || url.scheme?.lowercased() == "https"
        return matchesDomain && matchesPath && matchesSecurity
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

struct CampusHTTPResponse: Sendable {
    let data: Data
    let statusCode: Int
    let finalURL: URL?
    let headers: [String: String]

    func header(_ name: String) -> String? {
        headers.first { $0.key.caseInsensitiveCompare(name) == .orderedSame }?.value
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
    private let logger = RedactingLogger(category: "campus-web")

    init(campusAPI: any CampusCoreAPI, session: URLSession = .shared) {
        self.campusAPI = campusAPI
        self.session = session
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
            notifiesSessionExpiry: true
        ).data
    }

    func response(
        url: URL,
        method: String = "GET",
        body: Data? = nil,
        contentType: String? = nil,
        headers: [String: String] = [:],
        followsRedirects: Bool = true,
        refreshesSessionOnUnauthorized: Bool = true
    ) async throws -> CampusHTTPResponse {
        try await response(
            url: url,
            method: method,
            body: body,
            contentType: contentType,
            headers: headers,
            followsRedirects: followsRedirects,
            mayRefreshSession: refreshesSessionOnUnauthorized,
            notifiesSessionExpiry: refreshesSessionOnUnauthorized
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
        notifiesSessionExpiry: Bool
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
        let finalPath = response.url?.path.lowercased() ?? ""
        let responseHeaders = response.allHeaderFields.reduce(into: [String: String]()) { result, item in
            guard let key = item.key as? String else { return }
            result[key] = String(describing: item.value)
        }
        let redirectPath = responseHeaders.first {
            $0.key.caseInsensitiveCompare("Location") == .orderedSame
        }?.value.lowercased() ?? ""
        if response.statusCode == 401
            || response.statusCode == 403
            || finalPath.contains("tologin")
            || finalPath.contains("/cas/login")
            || redirectPath.contains("tologin")
            || redirectPath.contains("/cas/login") {
            if mayRefreshSession {
                logger.notice("Campus web session expired; refreshing path=\(url.path)")
                do {
                    try await campusAPI.refreshSession()
                } catch {
                    if let coreError = error as? CampusCoreError,
                       coreError == .credentialsUnavailable || coreError == .unauthorized {
                        await notifySessionExpired()
                    }
                    throw error
                }
                return try await self.response(
                    url: url,
                    method: method,
                    body: body,
                    contentType: contentType,
                    headers: headers,
                    followsRedirects: followsRedirects,
                    mayRefreshSession: false,
                    notifiesSessionExpiry: notifiesSessionExpiry
                )
            }
            if notifiesSessionExpiry { await notifySessionExpired() }
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
        for cookie in received {
            let updated = CampusCookie(
                name: cookie.name,
                value: cookie.value,
                domain: cookie.domain,
                path: cookie.path,
                secure: cookie.isSecure,
                httpOnly: cookie.properties?[HTTPCookiePropertyKey(rawValue: "HttpOnly")] != nil
            )
            merged.removeAll {
                $0.name == updated.name
                    && $0.domain.caseInsensitiveCompare(updated.domain) == .orderedSame
                    && ($0.path ?? "/") == (updated.path ?? "/")
            }
            merged.append(updated)
        }
        let json = String(decoding: try JSONEncoder().encode(merged), as: UTF8.self)
        try await campusAPI.initialize(cookiesJSON: json)
        try await campusAPI.persistSessionCookies()
    }

    private func notifySessionExpired() async {
        await MainActor.run {
            NotificationCenter.default.post(name: .campusSessionExpired, object: nil)
        }
    }
}

extension URL {
    func appendingQueryItems(_ items: [URLQueryItem]) -> URL {
        var components = URLComponents(url: self, resolvingAgainstBaseURL: false)
        components?.queryItems = items
        return components?.url ?? self
    }
}
