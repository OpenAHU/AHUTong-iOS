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
    func schedule() async throws -> [Course]
    func currentWeek() async throws -> Int
    func exams() async throws -> [CampusExam]
    func grades() async throws -> CampusGradeReport
    func cardBalance() async throws -> Double
    func cardQRCode() async throws -> String
}

actor RustCampusCoreAPI: CampusCoreAPI {
    private let server: RustLocalServer
    private let session: URLSession
    private let gradeParser = CampusGradeParser()
    private let cardParser = CampusCardResponseParser()

    init(server: RustLocalServer = .shared, session: URLSession = .shared) {
        self.server = server
        self.session = session
    }

    func initialize(cookiesJSON: String) async throws {
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

    func schedule() async throws -> [Course] {
        let data = try await request(path: "/schedule")
        return try JSONDecoder().decode([Course].self, from: data)
    }

    func currentWeek() async throws -> Int {
        let data = try await request(path: "/schedule/current-week")
        let object = try JSONSerialization.jsonObject(with: data)
        return Self.findWeek(in: object) ?? 1
    }

    func exams() async throws -> [CampusExam] {
        let data = try await request(path: "/exam")
        return try JSONDecoder().decode([CampusExam].self, from: data)
    }

    func grades() async throws -> CampusGradeReport {
        try gradeParser.parse(try await request(path: "/grade"))
    }

    func cardBalance() async throws -> Double {
        try cardParser.balance(from: try await request(path: "/ycard/balance"))
    }

    func cardQRCode() async throws -> String {
        try cardParser.qrPayload(from: try await request(path: "/ycard/qrcode"))
    }

    private func request(path: String, method: String = "GET", body: Data? = nil) async throws -> Data {
        let service = try await server.start()
        var request = URLRequest(url: service.baseURL.appendingPathComponent(path))
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
    let api: any CampusCoreAPI

    init(api: any CampusCoreAPI = RustCampusCoreAPI()) {
        self.api = api
    }

    func fetchCourses(for semester: Semester) async throws -> [Course] {
        _ = semester
        return try await api.schedule()
    }
}
