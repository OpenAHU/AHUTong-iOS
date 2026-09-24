import Foundation

struct CampusCardCaptchaImage: Sendable {
    let data: Data
    let cookies: [CampusCookie]
}

enum CampusCardCaptchaFetchError: LocalizedError, Equatable, Sendable {
    case missingSchoolSession
    case network
    case redirected
    case status(Int)
    case invalidImage

    var errorDescription: String? {
        switch self {
        case .missingSchoolSession: "校方验证码会话 Cookie 缺失"
        case .network: "校方验证码图片网络请求失败"
        case .redirected: "校方验证码图片请求被重定向"
        case let .status(code): "校方验证码图片返回 HTTP \(code)"
        case .invalidImage: "校方验证码接口未返回有效图片"
        }
    }
}

struct CampusCardCaptchaClient: Sendable {
    static let endpoint = URL(string: "https://adwmh.ahu.edu.cn/remind/authcode")!

    private let session: URLSession

    init(session: URLSession = Self.makeSession()) {
        self.session = session
    }

    func fetch(cookies: [CampusCookie]) async throws -> CampusCardCaptchaImage {
        let schoolCookies = cookies.filter { $0.matches(Self.endpoint) && !$0.value.isEmpty }
        guard schoolCookies.contains(where: {
            $0.domain.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
                == "adwmh.ahu.edu.cn"
        }) else {
            throw CampusCardCaptchaFetchError.missingSchoolSession
        }

        var request = URLRequest(url: Self.endpoint, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData)
        request.httpMethod = "GET"
        request.httpShouldHandleCookies = false
        request.timeoutInterval = 10
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        request.setValue("no-cache", forHTTPHeaderField: "Pragma")
        request.setValue(
            schoolCookies.map { "\($0.name)=\($0.value)" }.joined(separator: "; "),
            forHTTPHeaderField: "Cookie"
        )

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw CampusCardCaptchaFetchError.network
        }
        guard let response = response as? HTTPURLResponse,
              response.url?.scheme == "https",
              response.url?.host?.lowercased() == "adwmh.ahu.edu.cn",
              response.url?.path == "/remind/authcode" else {
            throw CampusCardCaptchaFetchError.redirected
        }
        guard response.statusCode == 200 else {
            if (300..<400).contains(response.statusCode) {
                throw CampusCardCaptchaFetchError.redirected
            }
            throw CampusCardCaptchaFetchError.status(response.statusCode)
        }
        guard data.count <= 256_000, Self.isSupportedImage(data) else {
            throw CampusCardCaptchaFetchError.invalidImage
        }

        let fields = response.allHeaderFields.reduce(into: [String: String]()) { result, item in
            guard let name = item.key as? String else { return }
            result[name] = String(describing: item.value)
        }
        let received = HTTPCookie.cookies(withResponseHeaderFields: fields, for: Self.endpoint)
        let accepted = CampusWebCookiePolicy.cookies(from: received, scope: .campusCard)
        return CampusCardCaptchaImage(
            data: data,
            cookies: CampusCookieMerger.merge(existing: schoolCookies, incoming: accepted)
        )
    }

    private static func isSupportedImage(_ data: Data) -> Bool {
        let bytes = [UInt8](data.prefix(12))
        if bytes.starts(with: [0xFF, 0xD8, 0xFF]) { return true }
        if bytes.starts(with: [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]) { return true }
        if bytes.starts(with: Array("GIF87a".utf8)) || bytes.starts(with: Array("GIF89a".utf8)) {
            return true
        }
        return bytes.count >= 12
            && bytes.starts(with: Array("RIFF".utf8))
            && Array(bytes[8..<12]) == Array("WEBP".utf8)
    }

    private static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpShouldSetCookies = false
        configuration.httpCookieAcceptPolicy = .never
        configuration.urlCache = nil
        return URLSession(
            configuration: configuration,
            delegate: CampusCaptchaRedirectBlocker(),
            delegateQueue: nil
        )
    }
}

private final class CampusCaptchaRedirectBlocker: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
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
