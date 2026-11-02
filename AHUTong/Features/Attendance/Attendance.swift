import Foundation

struct AttendanceRecord: Equatable, Sendable {
    let courseName: String
    let courseCode: String
    let teacher: String
    let room: String
    let building: String
    let section: String
    let classDate: String
    let startTime: String
    let endTime: String
    let punchTime: String
    let status: Int
    let canAppeal: Bool
    var statusText: String {
        switch status { case 1: "正常"; case 2: "迟到"; case 3: "缺勤"; case 5: "请假"; default: "其他" }
    }
}

struct AttendancePage: Sendable {
    let totalCount: Int
    let records: [AttendanceRecord]
}

enum AttendanceContract {
    static let appsURL = URL(string: "https://adwmh.ahu.edu.cn/commapp/myapp")!
    static let pageURL = URL(string: "https://kqcard.ahu.edu.cn/attendance-student/classWater/getClassWaterPage")!

    static func payload(status: Int, page: Int) throws -> Data {
        try JSONSerialization.data(withJSONObject: [
            "classWaterBean": ["status": status], "current": page, "pageSize": 10,
            "subjectBean": ["sCode": ""], "timeCondition": ""
        ])
    }

    static func parsePage(_ data: Data) throws -> AttendancePage {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              root["code"] as? Int == 200, let page = root["data"] as? [String: Any],
              let list = page["list"] as? [[String: Any]] else { throw CampusWebError.invalidResponse }
        return AttendancePage(totalCount: page["totalCount"] as? Int ?? list.count, records: list.map { item in
            func object(_ key: String) -> [String: Any] { item[key] as? [String: Any] ?? [:] }
            func text(_ object: [String: Any], _ key: String) -> String { object[key] as? String ?? "" }
            let subject = object("subjectBean"), water = object("classWaterBean"), account = object("accountBean")
            let detail = object("accountDetailEntity"), building = text(object("buildBean"), "name")
            let punch = text(water, "operdate"), checkDate = text(account, "checkdate")
            let date = checkDate.count >= 10 ? checkDate : (punch.count >= 10 ? String(punch.prefix(10)) : text(detail, "timingdate_startdate"))
            let start = account["startJc"] as? Int ?? 0, end = account["endJc"] as? Int ?? 0
            let fallback = text(water, "jc")
            let section = start > 0 ? (end > start ? "第\(start)-\(end)节" : "第\(start)节") : (fallback.isEmpty ? "" : "第\(fallback)节")
            let room = text(object("roomBean"), "roomnum")
            return AttendanceRecord(courseName: text(subject, "sName"), courseCode: text(subject, "sCode"),
                teacher: text(item, "teachNameList"), room: room.isEmpty ? building : room, building: building,
                section: section, classDate: date, startTime: text(detail, "lessonstime_start_starttime"),
                endTime: text(detail, "lessonstime_end_endtime"), punchTime: punch,
                status: water["status"] as? Int ?? 0, canAppeal: text(item, "isSupportAppeal") == "1")
        })
    }

    static func entryURL(_ data: Data) throws -> URL {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any], root["code"] as? Int == 10000 else {
            throw CampusWebError.unauthorized
        }
        func find(_ value: Any) -> [String: Any]? {
            if let object = value as? [String: Any] {
                if object["name"] as? String == "教务考勤" || object["id"] as? Int == 2035 { return object }
                for child in object.values { if let result = find(child) { return result } }
            } else if let array = value as? [Any] {
                for child in array { if let result = find(child) { return result } }
            }
            return nil
        }
        guard let entry = find(root["object"] ?? []),
              let link = ["lk", "url", "appUrl"].compactMap({ entry[$0] as? String }).first(where: { !$0.isEmpty }) else {
            throw CampusWebError.server("校方暂未提供教务考勤入口")
        }
        return try portalURL(link, relativeTo: appsURL)
    }

    static func portalURL(_ raw: String, relativeTo base: URL) throws -> URL {
        guard let url = URL(string: raw.replacingOccurrences(of: "&amp;", with: "&"), relativeTo: base)?.absoluteURL,
              var parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
              ["https", "http"].contains(parts.scheme?.lowercased() ?? ""),
              ["one.ahu.edu.cn", "adwmh.ahu.edu.cn", "kqcard.ahu.edu.cn"].contains(parts.host?.lowercased() ?? ""),
              parts.user == nil, parts.password == nil,
              parts.port == nil || parts.port == 443 || (parts.scheme == "http" && parts.port == 80) else {
            throw CampusWebError.server("教务考勤跳转地址不受信任")
        }
        parts.scheme = "https"; parts.port = nil
        guard let result = parts.url else { throw CampusWebError.invalidResponse }
        return result
    }

    static func token(in url: URL) -> String? {
        // The credential belongs only to the final kqcard callback.
        guard url.host?.lowercased() == "kqcard.ahu.edu.cn" else { return nil }
        var items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        if let fragment = url.fragment, let query = fragment.firstIndex(of: "?") {
            items += URLComponents(string: "https://kqcard.ahu.edu.cn/?" + fragment[fragment.index(after: query)...])?.queryItems ?? []
        }
        guard let value = items.first(where: { $0.name == "token" })?.value,
              !value.isEmpty, value.utf8.count <= 16_384,
              !value.contains(where: { $0.isWhitespace || $0.isNewline }) else { return nil }
        return value
    }

    static func scriptRedirect(_ data: Data) -> String? {
        let body = String(decoding: data, as: UTF8.self)
        let regex = try! NSRegularExpression(pattern: #"location\.href\s*=\s*["']([^"']+)["']"#)
        guard let match = regex.firstMatch(in: body, range: NSRange(body.startIndex..., in: body)),
              let range = Range(match.range(at: 1), in: body) else { return nil }
        return String(body[range])
    }

    static func expiry(of token: String, now: Date) -> Date {
        let parts = token.split(separator: ".")
        if parts.count > 1 {
            var value = String(parts[1]).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
            value += String(repeating: "=", count: (4 - value.count % 4) % 4)
            if let data = Data(base64Encoded: value), let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let expiry = json["exp"] as? Double, expiry > 0 { return Date(timeIntervalSince1970: expiry) }
        }
        return now.addingTimeInterval(600)
    }
}

protocol AttendanceRemote: Sendable {
    func page(status: Int, page: Int) async throws -> AttendancePage
}

/// One screen owns this client. SSO cookies and the attendance JWT stay in
/// memory and never enter diagnostics, a URL log, or the on-disk cache.
actor OfficialAttendanceRemote: AttendanceRemote {
    private let api: any CampusCoreAPI
    private let client: CampusAuthenticatedClient
    private let session: URLSession
    private var cachedToken: (value: String, expiry: Date)?

    init(api: any CampusCoreAPI, session: URLSession? = nil) {
        self.api = api
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil; configuration.httpShouldSetCookies = false
        configuration.urlCredentialStorage = nil; configuration.urlCache = nil
        let session = session ?? URLSession(configuration: configuration, delegate: AttendanceRedirectBlocker(), delegateQueue: nil)
        self.session = session
        client = CampusAuthenticatedClient(campusAPI: api, session: session)
    }

    func page(status: Int, page: Int) async throws -> AttendancePage {
        for attempt in 0...1 {
            let token = try await token()
            var request = URLRequest(url: AttendanceContract.pageURL)
            request.httpMethod = "POST"; request.httpBody = try AttendanceContract.payload(status: status, page: page)
            request.timeoutInterval = 30; request.httpShouldHandleCookies = false
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("bearer " + token, forHTTPHeaderField: "synjones-auth")
            // School service credential, identical to the public Android client.
            request.setValue("Basic YWN0aXZpdHk6YWN0aXZpdHlfc2VjcmV0", forHTTPHeaderField: "Authorization")
            let (data, response) = try await session.diagnosticData(for: request)
            try Task.checkCancellation()
            guard let response = response as? HTTPURLResponse else { throw CampusWebError.invalidResponse }
            if response.statusCode == 401, attempt == 0 { cachedToken = nil; continue }
            guard response.statusCode == 200, response.url == AttendanceContract.pageURL else { throw CampusWebError.server("考勤查询失败，请稍后重试") }
            return try AttendanceContract.parsePage(data)
        }
        throw CampusWebError.unauthorized
    }

    private func entryURL() async throws -> URL {
        let apps = try await client.response(url: AttendanceContract.appsURL, followsRedirects: false)
        do { return try AttendanceContract.entryURL(apps.data) }
        catch CampusWebError.unauthorized {
            // ADWMH can report expiry in a 200 JSON body, independently of CAS.
            try await SessionRefreshCoordinator.shared.refresh(scope: .campusCard) { [api] in
                try await api.refreshSession(scope: .campusCard)
            }
            let fresh = try await client.response(url: AttendanceContract.appsURL, followsRedirects: false,
                                                  refreshesSessionOnUnauthorized: false)
            return try AttendanceContract.entryURL(fresh.data)
        }
    }

    private func token() async throws -> String {
        if let token = cachedToken, token.expiry.timeIntervalSinceNow > 60 { return token.value }
        for attempt in 0...1 {
            do {
                var url = try await entryURL()
                var cookies = try JSONDecoder().decode([CampusCookie].self, from: Data(try await api.cookiesFlat().utf8))
                for _ in 0..<10 {
                    if let token = AttendanceContract.token(in: url) {
                        cachedToken = (token, AttendanceContract.expiry(of: token, now: Date()))
                        return token
                    }
                    var request = URLRequest(url: url)
                    request.timeoutInterval = 30; request.httpShouldHandleCookies = false
                    request.setValue(cookies.filter { $0.matches(url) }.map { "\($0.name)=\($0.value)" }.joined(separator: "; "), forHTTPHeaderField: "Cookie")
                    let (data, response) = try await session.diagnosticData(for: request)
                    try Task.checkCancellation()
                    guard let response = response as? HTTPURLResponse, response.url == url else { throw CampusWebError.invalidResponse }
                    let fields = response.allHeaderFields.reduce(into: [String: String]()) { $0[String(describing: $1.key)] = String(describing: $1.value) }
                    CampusCookieResponsePolicy.merge(HTTPCookie.cookies(withResponseHeaderFields: fields, for: url), into: &cookies,
                        identityIsAllowed: { $0.matches(url) })
                    guard (200..<400).contains(response.statusCode) else { throw CampusWebError.server("教务考勤登录服务暂不可用") }
                    guard let target = response.value(forHTTPHeaderField: "Location") ?? AttendanceContract.scriptRedirect(data) else {
                        throw CampusWebError.unauthorized
                    }
                    url = try AttendanceContract.portalURL(target, relativeTo: url)
                }
                throw CampusWebError.server("教务考勤跳转次数过多")
            } catch CampusWebError.unauthorized where attempt == 0 {
                try await SessionRefreshCoordinator.shared.refresh(scope: .academic) { [api] in try await api.refreshSession(scope: .academic) }
            }
        }
        throw CampusWebError.unauthorized
    }
}

private final class AttendanceRedirectBlocker: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}
