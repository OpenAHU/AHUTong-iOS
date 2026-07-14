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

private struct CampusCookie: Decodable, Sendable {
    let name: String
    let value: String
    let domain: String
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
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.httpBody = body
        request.timeoutInterval = 30
        request.setValue("XMLHttpRequest", forHTTPHeaderField: "X-Requested-With")
        if let contentType { request.setValue(contentType, forHTTPHeaderField: "Content-Type") }

        let rawCookies = try await campusAPI.cookiesFlat()
        let cookies = (try? JSONDecoder().decode([CampusCookie].self, from: Data(rawCookies.utf8))) ?? []
        let host = url.host?.lowercased() ?? ""
        let header = cookies
            .filter { cookie in
                let domain = cookie.domain.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
                return host == domain || host.hasSuffix(".(domain)")
            }
            .map { "\($0.name)=\($0.value)" }
            .joined(separator: "; ")
        if !header.isEmpty { request.setValue(header, forHTTPHeaderField: "Cookie") }

        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw CampusWebError.invalidResponse }
        let finalPath = response.url?.path.lowercased() ?? ""
        if response.statusCode == 401 || response.statusCode == 403 || finalPath.contains("tologin") || finalPath.contains("/cas/login") {
            throw CampusWebError.unauthorized
        }
        guard (200..<300).contains(response.statusCode) else {
            throw CampusWebError.server("校园服务请求失败（\(response.statusCode)）")
        }
        return data
    }
}

extension URL {
    func appendingQueryItems(_ items: [URLQueryItem]) -> URL {
        var components = URLComponents(url: self, resolvingAgainstBaseURL: false)
        components?.queryItems = items
        return components?.url ?? self
    }
}
