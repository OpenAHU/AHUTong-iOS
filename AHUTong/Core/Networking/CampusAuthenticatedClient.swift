import Foundation

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
}

actor CampusAuthenticatedClient {
    private let campusAPI: any CampusCoreAPI
    private let session: URLSession

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
        try await data(
            url: url,
            method: method,
            body: body,
            contentType: contentType,
            mayRefreshSession: true
        )
    }

    private func data(
        url: URL,
        method: String,
        body: Data?,
        contentType: String?,
        mayRefreshSession: Bool
    ) async throws -> Data {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.httpBody = body
        request.timeoutInterval = 30
        request.setValue("XMLHttpRequest", forHTTPHeaderField: "X-Requested-With")
        if let contentType { request.setValue(contentType, forHTTPHeaderField: "Content-Type") }

        let rawCookies = try await campusAPI.cookiesFlat()
        let cookies = (try? JSONDecoder().decode([CampusCookie].self, from: Data(rawCookies.utf8))) ?? []
        let header = cookies
            .filter { $0.matches(url) }
            .map { "\($0.name)=\($0.value)" }
            .joined(separator: "; ")
        if !header.isEmpty { request.setValue(header, forHTTPHeaderField: "Cookie") }

        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw CampusWebError.invalidResponse }
        try await persistResponseCookies(response, for: url, existing: cookies)
        let finalPath = response.url?.path.lowercased() ?? ""
        if response.statusCode == 401 || response.statusCode == 403 || finalPath.contains("tologin") || finalPath.contains("/cas/login") {
            if mayRefreshSession {
                try await campusAPI.refreshSession()
                return try await self.data(
                    url: url,
                    method: method,
                    body: body,
                    contentType: contentType,
                    mayRefreshSession: false
                )
            }
            throw CampusWebError.unauthorized
        }
        guard (200..<300).contains(response.statusCode) else {
            throw CampusWebError.server("校园服务请求失败（\(response.statusCode)）")
        }
        return data
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
}

extension URL {
    func appendingQueryItems(_ items: [URLQueryItem]) -> URL {
        var components = URLComponents(url: self, resolvingAgainstBaseURL: false)
        components?.queryItems = items
        return components?.url ?? self
    }
}
