import Foundation

enum CampusCardLoginError: LocalizedError, Equatable, Sendable {
    case invalidCaptcha
    case missingSchoolSession
    case invalidResponse
    case rejected(String)

    var errorDescription: String? {
        switch self {
        case .invalidCaptcha: "请输入四位图形验证码"
        case .missingSchoolSession: "校方验证码会话已失效，请刷新页面后重试"
        case .invalidResponse: "校方登录返回了无法识别的结果，请重试"
        case let .rejected(message): message.isEmpty ? "校方未接受本次登录，请检查验证码后重试" : message
        }
    }
}

struct CampusCardLoginClient: Sendable {
    static let endpoint = URL(string: "https://adwmh.ahu.edu.cn/user/login")!

    private let session: URLSession

    init(session: URLSession = Self.makeSession()) {
        self.session = session
    }

    func login(
        credentials: LoginCredentials,
        captcha: String,
        cookies: [CampusCookie]
    ) async throws -> [CampusCookie] {
        let code = captcha.trimmingCharacters(in: .whitespacesAndNewlines)
        guard code.range(of: "^[A-Za-z0-9]{4}$", options: .regularExpression) != nil else {
            throw CampusCardLoginError.invalidCaptcha
        }
        let schoolCookies = cookies.filter { $0.matches(Self.endpoint) && !$0.value.isEmpty }
        guard schoolCookies.contains(where: {
            $0.domain.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: ".")) == "adwmh.ahu.edu.cn"
        }) else {
            throw CampusCardLoginError.missingSchoolSession
        }

        var form = URLComponents()
        form.queryItems = [
            URLQueryItem(name: "username", value: credentials.studentID),
            URLQueryItem(name: "pwd", value: credentials.password),
            URLQueryItem(name: "flag", value: "0"),
            URLQueryItem(name: "imgcode", value: code)
        ]
        guard let body = form.percentEncodedQuery?.data(using: .utf8) else {
            throw CampusCardLoginError.invalidResponse
        }

        var request = URLRequest(url: Self.endpoint)
        request.httpMethod = "POST"
        request.httpBody = body
        request.httpShouldHandleCookies = false
        request.timeoutInterval = 20
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("XMLHttpRequest", forHTTPHeaderField: "X-Requested-With")
        request.setValue(
            schoolCookies.map { "\($0.name)=\($0.value)" }.joined(separator: "; "),
            forHTTPHeaderField: "Cookie"
        )

        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse,
              response.url?.scheme == "https",
              response.url?.host?.lowercased() == "adwmh.ahu.edu.cn",
              response.url?.path == "/user/login",
              response.statusCode == 200,
              data.count <= 64_000 else {
            throw CampusCardLoginError.invalidResponse
        }
        let result = try JSONDecoder().decode(LoginResponse.self, from: data)
        guard result.code == 10_000 else {
            throw CampusCardLoginError.rejected(
                String((result.msg ?? "").trimmingCharacters(in: .whitespacesAndNewlines).prefix(240))
            )
        }

        let fields = response.allHeaderFields.reduce(into: [String: String]()) { values, item in
            guard let name = item.key as? String else { return }
            values[name] = String(describing: item.value)
        }
        let received = HTTPCookie.cookies(withResponseHeaderFields: fields, for: Self.endpoint)
        let accepted = CampusWebCookiePolicy.cookies(from: received, scope: .campusCard)
            .filter { !$0.value.isEmpty }
        return CampusCookieMerger.merge(existing: cookies, incoming: accepted)
    }

    private struct LoginResponse: Decodable {
        let code: Int
        let msg: String?
    }

    private static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpShouldSetCookies = false
        configuration.httpCookieAcceptPolicy = .never
        configuration.urlCache = nil
        return URLSession(configuration: configuration, delegate: CampusCardRedirectBlocker(), delegateQueue: nil)
    }
}

private final class CampusCardRedirectBlocker: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
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
