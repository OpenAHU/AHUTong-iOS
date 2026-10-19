import Foundation

struct ProgramCompletion: Codable, Equatable, Sendable {
    let programName: String
    let progress: String
    let required: Double
    let passed: Double
    let taking: Double
    let unfinished: Double
    let auditPublished: Bool
    let modules: [CompletionModule]
    let outerCourses: [CompletionCourse]
    var progressTitle: String { progress.isEmpty || progress == "—" ? "学分完成率" : "完成进度" }
    var progressText: String {
        guard progress.isEmpty || progress == "—" else { return progress }
        guard required > 0 else { return "—" }
        return min(1, max(0, passed / required)).formatted(.percent.precision(.fractionLength(1)))
    }
}

struct CompletionModule: Codable, Equatable, Sendable {
    let name: String
    let required: Double
    let passed: Double
    let courses: [CompletionCourse]
    let children: [CompletionModule]
}

struct CompletionCourse: Codable, Equatable, Sendable {
    let name: String
    let code: String
    let credits: Double
    let status: String
    let grade: String?
    let terms: String?
    let remark: String?

    var completed: Bool { ["PASSED", "REPAIRED", "SKIP"].contains(status) }
    var statusText: String {
        switch status {
        case "PASSED": "已通过"
        case "REPAIRED": "已认定"
        case "SKIP": "免修"
        case "TAKING": "在修"
        case "FAILED": "未通过"
        case "UNREPAIRED": "未修读"
        default: "待完成"
        }
    }
}

enum ProgramCompletionParser {
    /// Parses the school's JavaScript data literal without executing scripts.
    /// Only mapped course/credit fields can enter the account-scoped cache.
    static func parse(_ html: String) throws -> ProgramCompletion {
        let pattern = #"(?i)(?:(?:var|let|const)\s+)?(?:window\s*\.\s*)?\bmodel\s*[=:]\s*\{"#
        guard let range = html.range(of: pattern, options: .regularExpression) else {
            throw CampusWebError.server("未找到培养方案数据，教务页面可能已变更")
        }
        let start = html.index(before: range.upperBound)
        let chars = Array(html[start...])
        var depth = 0
        var quote: Character?
        var escaped = false
        var end: Int?
        for (i, ch) in chars.enumerated() {
            if let q = quote {
                if escaped { escaped = false }
                else if ch == "\\" { escaped = true }
                else if ch == q { quote = nil }
                continue
            }
            if ch == "\"" || ch == "'" { quote = ch }
            else if ch == "{" { depth += 1 }
            else if ch == "}" { depth -= 1; if depth == 0 { end = i; break } }
        }
        guard let end else { throw CampusWebError.invalidResponse }
        let literal = Array(chars[0...end])
        var json = ""
        json.reserveCapacity(literal.count + 512)
        var i = 0
        while i < literal.count {
            let c = literal[i]
            if c == "'" || c == "\"" {
                let delimiter = c
                var value = ""
                i += 1
                var closed = false
                while i < literal.count {
                    let v = literal[i]; i += 1
                    if v == delimiter { closed = true; break }
                    if v == "\\", i < literal.count {
                        let next = literal[i]; i += 1
                        switch next {
                        case "'": value += "'"
                        case "\"": value += "\""
                        case "\\": value += "\\"
                        case "n": value += "\n"
                        case "r": value += "\r"
                        case "t": value += "\t"
                        case "b": value += "\u{8}"
                        case "f": value += "\u{c}"
                        case "/": value += "/"
                        case "u":
                            guard i + 4 <= literal.count, let first = UInt32(String(literal[i..<i+4]), radix: 16) else { throw CampusWebError.invalidResponse }
                            i += 4
                            let scalar: UInt32
                            if (0xD800...0xDBFF).contains(first) {
                                guard i + 6 <= literal.count, literal[i] == "\\", literal[i+1] == "u",
                                      let second = UInt32(String(literal[i+2..<i+6]), radix: 16), (0xDC00...0xDFFF).contains(second) else { throw CampusWebError.invalidResponse }
                                scalar = 0x10000 + (first - 0xD800) * 1024 + second - 0xDC00; i += 6
                            } else { scalar = first }
                            guard let unicode = UnicodeScalar(scalar) else { throw CampusWebError.invalidResponse }
                            value.unicodeScalars.append(unicode)
                        default: throw CampusWebError.invalidResponse
                        }
                    } else { value.append(v) }
                }
                guard closed else { throw CampusWebError.invalidResponse }
                json += String(decoding: try JSONEncoder().encode(value), as: UTF8.self)
            } else if c.isLetter || c == "$" || c == "_" {
                let tokenStart = i
                while i < literal.count && (literal[i].isLetter || literal[i].isNumber || literal[i] == "$" || literal[i] == "_") { i += 1 }
                let token = String(literal[tokenStart..<i])
                var lookahead = i
                while lookahead < literal.count && literal[lookahead].isWhitespace { lookahead += 1 }
                if lookahead < literal.count && literal[lookahead] == ":" {
                    json += String(decoding: try JSONEncoder().encode(token), as: UTF8.self)
                } else if token == "undefined" { json += "null" }
                else if ["true", "false", "null"].contains(token) { json += token }
                else { throw CampusWebError.invalidResponse }
            } else { json.append(c); i += 1 }
        }
        let model = try JSONDecoder().decode(RawModel.self, from: Data(json.utf8))
        guard (model.requireInfo?.credits ?? 0) > 0 || !(model.moduleList ?? []).isEmpty else {
            throw CampusWebError.server("培养方案数据格式已变更")
        }
        return ProgramCompletion(
            programName: model.program?.nameZh ?? "培养方案", progress: model.completionSummary?.completeProgress ?? "—",
            required: model.requireInfo?.credits ?? 0, passed: model.completionSummary?.passedCredits ?? 0,
            taking: model.completionSummary?.takingCredits ?? 0, unfinished: model.completionSummary?.failedCredits ?? 0,
            auditPublished: model.result?.published ?? false, modules: (model.moduleList ?? []).map(\.domain),
            outerCourses: (model.outerCourseList ?? []).map(\.domain)
        )
    }

    private struct Summary: Decodable { let passedCredits: Double?; let takingCredits: Double?; let failedCredits: Double?; let completeProgress: String? }
    private struct Requirement: Decodable { let credits: Double? }
    private struct Program: Decodable { let nameZh: String? }
    private struct Result: Decodable { let published: Bool? }
    private struct TypedName: Decodable {
        let name: String?
        enum CodingKeys: String, CodingKey { case name = "$name" }
    }
    private struct RawCourse: Decodable {
        let nameZh: String?; let code: String?; let credits: Double?; let gradeStr: String?
        let termsContent: String?; let remark: String?; let resultType: TypedName?; let finalResultType: TypedName?
        var domain: CompletionCourse {
            CompletionCourse(name: nameZh ?? "未命名课程", code: code ?? "", credits: credits ?? 0,
                             status: resultType?.name ?? finalResultType?.name ?? "UNKNOWN", grade: gradeStr, terms: termsContent, remark: remark)
        }
    }
    private struct RawModule: Decodable {
        let nameZh: String?; let requireInfo: Requirement?; let completionSummary: Summary?
        let courseList: [RawCourse]?; let children: [RawModule]?
        var domain: CompletionModule {
            CompletionModule(name: nameZh ?? "课程模块", required: requireInfo?.credits ?? 0,
                             passed: completionSummary?.passedCredits ?? 0, courses: (courseList ?? []).map(\.domain), children: (children ?? []).map(\.domain))
        }
    }
    private struct RawModel: Decodable {
        let program: Program?; let result: Result?; let requireInfo: Requirement?; let completionSummary: Summary?
        let moduleList: [RawModule]?; let outerCourseList: [RawCourse]?
    }
}

protocol ProgramCompletionRemote: Sendable {
    func load(profileID: String?) async throws -> ProgramCompletion
}

struct OfficialProgramCompletionRemote: ProgramCompletionRemote {
    private let client: CampusAuthenticatedClient
    init(api: any CampusCoreAPI, session: URLSession? = nil) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCredentialStorage = nil
        configuration.urlCache = nil
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 30
        client = CampusAuthenticatedClient(campusAPI: api, session: session ?? URLSession(configuration: configuration))
    }
    func load(profileID: String?) async throws -> ProgramCompletion {
        let base = URL(string: "https://jw.ahu.edu.cn/student/for-std/program-completion-preview")!
        let url: URL
        if let profileID, !profileID.isEmpty {
            guard profileID.allSatisfy(\.isNumber) else { throw CampusWebError.invalidResponse }
            url = base.appendingPathComponent("info").appendingPathComponent(profileID)
        } else { url = base }
        var response = try await client.response(url: url, followsRedirects: false)
        if (300..<400).contains(response.statusCode) {
            guard let location = response.header("Location"),
                  let destination = URL(string: location, relativeTo: url)?.absoluteURL,
                  destination.scheme == "https", destination.host == "jw.ahu.edu.cn",
                  destination.user == nil, destination.password == nil,
                  destination.port == nil || destination.port == 443,
                  destination.query == nil, destination.fragment == nil,
                  destination.path == base.path + "/info/" + destination.lastPathComponent,
                  !destination.lastPathComponent.isEmpty, destination.lastPathComponent.allSatisfy(\.isNumber) else {
                throw CampusWebError.invalidResponse
            }
            response = try await client.response(url: destination, followsRedirects: false)
        }
        guard response.statusCode == 200 else { throw CampusWebError.invalidResponse }
        return try ProgramCompletionParser.parse(String(decoding: response.data, as: UTF8.self))
    }
}
