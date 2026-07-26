import Foundation

private struct RustServerDescriptor: Decodable {
    let ok: Bool
    let port: UInt16?
    let token: String?
    let error: String?
}

private struct CookieDump: Decodable {
    let cookies: String
}

private struct CampusCardTokenResponse: Decodable {
    let accessToken: String

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
    }
}

actor RustLocalServer {
    static let shared = RustLocalServer()

    private var descriptor: RustServerDescriptor?

    func start() throws -> (baseURL: URL, token: String) {
        if let descriptor,
           let port = descriptor.port,
           let token = descriptor.token,
           let url = URL(string: "http://127.0.0.1:\(port)") {
            return (url, token)
        }

        guard let pointer = ahutong_start_server(0) else {
            throw CampusCoreError.serverStartup("Rust FFI 未返回服务信息")
        }
        defer { ahutong_free_string(pointer) }

        let data = Data(String(cString: pointer).utf8)
        let decoded = try JSONDecoder().decode(RustServerDescriptor.self, from: data)
        guard decoded.ok,
              let port = decoded.port,
              let token = decoded.token,
              let url = URL(string: "http://127.0.0.1:\(port)") else {
            throw CampusCoreError.serverStartup(decoded.error ?? "未知错误")
        }
        descriptor = decoded
        return (url, token)
    }
}

protocol CampusCoreAPI: Sendable {
    func initialize(cookiesJSON: String) async throws
    func login(studentID: String, password: String) async throws -> User
    func dumpCookies() async throws -> String
    func cookiesFlat() async throws -> String
    func schedule() async throws -> [Course]
    func nextSchedule() async throws -> [Course]
    func currentWeek() async throws -> Int
    func exams() async throws -> [CampusExam]
    func grades() async throws -> CampusGradeReport
    func grades(studentID: String) async throws -> CampusGradeReport
    func gradeProfiles() async throws -> [CampusGradeStudentProfile]
    func gradeRank(studentID: String) async throws -> CampusGradeRankInfo?
    func cardBalance() async throws -> Double
    func cardQRCode() async throws -> String
    func cardAccessToken() async throws -> String
    func refreshSession() async throws
    func persistSessionCookies() async throws
}

extension CampusCoreAPI {
    func nextSchedule() async throws -> [Course] { try await schedule() }
    func grades(studentID: String) async throws -> CampusGradeReport { try await grades() }
    func gradeProfiles() async throws -> [CampusGradeStudentProfile] { [] }
    func gradeRank(studentID: String) async throws -> CampusGradeRankInfo? { nil }
    func cardAccessToken() async throws -> String { throw CampusCoreError.credentialsUnavailable }
    func refreshSession() async throws { throw CampusCoreError.credentialsUnavailable }
    func persistSessionCookies() async throws { throw CampusCoreError.invalidResponse }
}

actor RustCampusCoreAPI: CampusCoreAPI {
    private let server: RustLocalServer
    private let session: URLSession
    private let sessionStore: CampusSessionStore
    private let credentialStore: CredentialStore
    private let gradeParser = CampusGradeParser()
    private let cardParser = CampusCardResponseParser()

    init(
        server: RustLocalServer = .shared,
        session: URLSession = .shared,
        sessionStore: CampusSessionStore = CampusSessionStore(),
        credentialStore: CredentialStore = CredentialStore()
    ) {
        self.server = server
        self.session = session
        self.sessionStore = sessionStore
        self.credentialStore = credentialStore
    }

    func initialize(cookiesJSON: String) async throws {
        try await RustPersistenceCoordinator.shared.configure(
            databaseURL: GuiXuDataStore.applicationDatabaseURL()
        )
        let body = try JSONEncoder().encode(["cookies_json": cookiesJSON])
        _ = try await request(path: "/init", method: "POST", body: body)
    }

    func login(studentID: String, password: String) async throws -> User {
        let body = try JSONEncoder().encode(["username": studentID, "password": password])
        let data = try await request(path: "/login", method: "POST", body: body)
        return try JSONDecoder().decode(User.self, from: data)
    }

    func dumpCookies() async throws -> String {
        let data = try await request(path: "/cookies/dump")
        return try JSONDecoder().decode(CookieDump.self, from: data).cookies
    }

    func cookiesFlat() async throws -> String {
        String(decoding: try await request(path: "/cookies/flat"), as: UTF8.self)
    }

    func schedule() async throws -> [Course] {
        let data = try await authenticatedRequest(path: "/schedule")
        return try JSONDecoder().decode([Course].self, from: data)
    }

    func nextSchedule() async throws -> [Course] {
        let data = try await authenticatedRequest(path: "/schedule/next")
        return try JSONDecoder().decode([Course].self, from: data)
    }

    func currentWeek() async throws -> Int {
        let data = try await authenticatedRequest(path: "/schedule/current-week")
        let object = try JSONSerialization.jsonObject(with: data)
        return Self.findWeek(in: object) ?? 1
    }

    func exams() async throws -> [CampusExam] {
        let data = try await authenticatedRequest(path: "/exam")
        return try JSONDecoder().decode([CampusExam].self, from: data)
    }

    func grades() async throws -> CampusGradeReport {
        try gradeParser.parse(try await authenticatedRequest(path: "/grade"))
    }

    func grades(studentID: String) async throws -> CampusGradeReport {
        let encoded = studentID.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? studentID
        return try gradeParser.parse(try await authenticatedRequest(path: "/grade?student_id=\(encoded)"))
    }

    func gradeProfiles() async throws -> [CampusGradeStudentProfile] {
        let data = try await authenticatedRequest(path: "/grade/profiles")
        return try JSONDecoder().decode([CampusGradeStudentProfile].self, from: data)
    }

    func gradeRank(studentID: String) async throws -> CampusGradeRankInfo? {
        let encoded = studentID.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? studentID
        let data = try await authenticatedRequest(path: "/grade/rank?student_id=\(encoded)")
        return try JSONDecoder().decode(CampusGradeRankInfo.self, from: data)
    }

    func cardBalance() async throws -> Double {
        try cardParser.balance(from: try await authenticatedRequest(path: "/ycard/balance"))
    }

    func cardQRCode() async throws -> String {
        try cardParser.qrPayload(from: try await authenticatedRequest(path: "/ycard/qrcode"))
    }

    func cardAccessToken() async throws -> String {
        let data = try await authenticatedRequest(path: "/ycard/refresh_token", method: "POST")
        let response = try JSONDecoder().decode(CampusCardTokenResponse.self, from: data)
        guard !response.accessToken.isEmpty else { throw CampusCoreError.invalidResponse }
        return response.accessToken
    }

    func refreshSession() async throws {
        guard let snapshot = try await sessionStore.load(),
              let credentials = try await credentialStore.credentials(for: snapshot.user.studentID) else {
            throw CampusCoreError.credentialsUnavailable
        }
        try await initialize(cookiesJSON: "")
        let user = try await login(studentID: credentials.studentID, password: credentials.password)
        let cookies = try await dumpCookies()
        try await sessionStore.save(CampusSessionSnapshot(user: user, cookiesJSON: cookies))
    }

    func persistSessionCookies() async throws {
        guard let snapshot = try await sessionStore.load() else { return }
        let cookies = try await dumpCookies()
        try await sessionStore.save(CampusSessionSnapshot(user: snapshot.user, cookiesJSON: cookies))
    }

    private func authenticatedRequest(path: String, method: String = "GET", body: Data? = nil) async throws -> Data {
        do {
            return try await request(path: path, method: method, body: body)
        } catch CampusCoreError.unauthorized {
            do {
                try await refreshSession()
                return try await request(path: path, method: method, body: body)
            } catch {
                if let coreError = error as? CampusCoreError,
                   coreError == .credentialsUnavailable || coreError == .unauthorized {
                    await MainActor.run {
                        NotificationCenter.default.post(name: .campusSessionExpired, object: nil)
                    }
                }
                throw error
            }
        }
    }

    private func request(path: String, method: String = "GET", body: Data? = nil) async throws -> Data {
        let service = try await server.start()
        let pieces = path.split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false)
        var components = URLComponents(
            url: service.baseURL.appendingPathComponent(String(pieces[0])),
            resolvingAgainstBaseURL: false
        )
        if pieces.count == 2 { components?.percentEncodedQuery = String(pieces[1]) }
        guard let endpoint = components?.url else { throw CampusCoreError.invalidResponse }
        var request = URLRequest(url: endpoint)
        request.httpMethod = method
        request.httpBody = body
        request.setValue(service.token, forHTTPHeaderField: "X-AHUTONG-TOKEN")
        if body != nil { request.setValue("application/json", forHTTPHeaderField: "Content-Type") }

        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else {
            throw CampusCoreError.invalidResponse
        }
        if response.statusCode == 401 { throw CampusCoreError.unauthorized }
        guard (200..<300).contains(response.statusCode) else {
            let message = Self.errorMessage(from: data) ?? "校园服务请求失败（\(response.statusCode)）"
            throw CampusCoreError.campus(message)
        }
        return data
    }

    private static func errorMessage(from data: Data) -> String? {
        guard let value = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return value["error"] as? String
    }

    private static func findWeek(in value: Any) -> Int? {
        if let number = value as? NSNumber { return number.intValue }
        if let string = value as? String, let week = Int(string) { return week }
        if let dictionary = value as? [String: Any] {
            for key in ["week", "currentWeek", "teachWeek"] {
                if let week = findWeek(in: dictionary[key] as Any) { return week }
            }
            for nested in dictionary.values {
                if let week = findWeek(in: nested) { return week }
            }
        }
        return nil
    }
}

struct RustScheduleRemoteDataSource: ScheduleRemoteDataSource {
    enum Scope: Sendable {
        case current
        case next
    }

    let api: any CampusCoreAPI
    let scope: Scope

    init(api: any CampusCoreAPI = RustCampusCoreAPI(), scope: Scope = .current) {
        self.api = api
        self.scope = scope
    }

    func fetchCourses(for semester: Semester) async throws -> [Course] {
        switch scope {
        case .current: try await api.schedule()
        case .next: try await api.nextSchedule()
        }
    }
}
