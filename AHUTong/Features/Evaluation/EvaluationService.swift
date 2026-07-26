import Foundation

struct EvaluationCatalog: Equatable, Sendable {
    let semesters: [EvaluationSemester]
    let currentSemesterID: String
}

struct EvaluationQuestionnaireForm: Equatable, Sendable {
    let questionnaire: EvaluationQuestionnaire
}

protocol EvaluationServicing: Sendable {
    func catalog() async throws -> EvaluationCatalog
    func tasks(semesterID: String) async throws -> [EvaluationCourseTask]
    func questionnaire(id: String) async throws -> EvaluationQuestionnaireForm
    func checkSubmit(_ request: EvaluationSubmitRequest) async throws -> String
    func submit(_ request: EvaluationSubmitRequest) async throws
}

actor DemoEvaluationService: EvaluationServicing {
    private let semesterID = "demo-2026-spring"
    private var submittedTaskIDs: Set<String> = []

    func catalog() async throws -> EvaluationCatalog {
        EvaluationCatalog(
            semesters: [
                EvaluationSemester(
                    id: semesterID,
                    name: "2025-2026 学年第二学期",
                    code: "2025-2026-2",
                    schoolYear: "2025-2026"
                )
            ],
            currentSemesterID: semesterID
        )
    }

    func tasks(semesterID: String) async throws -> [EvaluationCourseTask] {
        guard semesterID == self.semesterID else { return [] }
        let taskID = "demo-evaluation-task"
        return [
            EvaluationCourseTask(
                lessonID: "demo-evaluation-lesson",
                courseName: "移动应用开发",
                lessonName: "移动应用开发-01班",
                tasks: [
                    EvaluationTask(
                        questionnaireID: "demo-evaluation-questionnaire",
                        questionnaireName: "本科课堂教学评价",
                        isOpen: true,
                        taskID: taskID,
                        teachers: [
                            EvaluationTeacher(
                                taskID: taskID,
                                teacherID: "demo-teacher",
                                name: "张老师",
                                status: submittedTaskIDs.contains(taskID)
                                    ? "REVIEWED"
                                    : "TO_REVIEW"
                            )
                        ]
                    )
                ]
            )
        ]
    }

    func questionnaire(id: String) async throws -> EvaluationQuestionnaireForm {
        guard id == "demo-evaluation-questionnaire" else {
            throw EvaluationModelError.invalidQuestionnaire
        }
        return EvaluationQuestionnaireForm(
            questionnaire: EvaluationQuestionnaire(
                id: id,
                name: "本科课堂教学评价",
                enabled: true,
                questions: [
                    EvaluationQuestion(
                        index: 1,
                        attribute: EvaluationQuestionAttribute(
                            id: 1,
                            typeID: 1,
                            title: "教师教学态度认真，课程内容清晰",
                            isRequired: true,
                            enablesScore: true
                        ),
                        options: [
                            EvaluationOption(id: 101, score: 5, value: "非常满意"),
                            EvaluationOption(id: 102, score: 4, value: "满意"),
                            EvaluationOption(id: 103, score: 3, value: "一般")
                        ]
                    ),
                    EvaluationQuestion(
                        index: 2,
                        attribute: EvaluationQuestionAttribute(
                            id: 2,
                            typeID: 4,
                            title: "请填写对本课程的建议",
                            isRequired: true
                        ),
                        options: [],
                        setting: EvaluationOptionSetting(maximumWords: 200)
                    )
                ]
            )
        )
    }

    func checkSubmit(_ request: EvaluationSubmitRequest) async throws -> String {
        request.questionnaire.answers.isEmpty ? "评教答案不能为空" : ""
    }

    func submit(_ request: EvaluationSubmitRequest) async throws {
        submittedTaskIDs.insert(request.taskID)
    }
}

enum EvaluationSessionRetryPolicy {
    static func shouldRenew(forEnvelopeCode code: Int) -> Bool {
        code != 0
    }
}

enum EvaluationTokenParser {
    static func token(from location: String) throws -> String {
        guard let components = URLComponents(string: location) else {
            throw EvaluationModelError.invalidEntryRedirect
        }
        if let token = components.queryItems?
            .first(where: { $0.name == "token" })?
            .value?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !token.isEmpty {
            return token
        }

        guard let fragment = components.percentEncodedFragment else {
            throw EvaluationModelError.invalidEntryRedirect
        }
        let rawQuery: Substring
        if let separator = fragment.firstIndex(of: "?") {
            rawQuery = fragment[fragment.index(after: separator)...]
        } else {
            rawQuery = Substring(fragment)
        }
        guard
            !rawQuery.isEmpty,
            let fragmentComponents = URLComponents(string: "https://evaluation.invalid/?\(rawQuery)"),
            let token = fragmentComponents.queryItems?
                .first(where: { $0.name == "token" })?
                .value?
                .trimmingCharacters(in: .whitespacesAndNewlines),
            !token.isEmpty
        else {
            throw EvaluationModelError.invalidEntryRedirect
        }
        return token
    }
}

actor EvaluationRemoteService: EvaluationServicing {
    private struct SessionContext: Sendable {
        let token: String
        let currentSemesterID: String
    }

    private struct IgnoredPayload: Decodable, Sendable {
        init(from decoder: Decoder) throws {}
    }

    private static let entryURL = URL(
        string: "https://jw.ahu.edu.cn/student/for-std/extra-system/student-summation-forstudent/index"
    )!
    private static let serviceURL = URL(
        string: "https://jw.ahu.edu.cn/eams5-evaluation-service/"
    )!
    private static let evaluationReferer = "https://jw.ahu.edu.cn/evaluation-student-frontend/?bizTypeId=2"
    private static let studentReferer = "https://jw.ahu.edu.cn/student/home"
    private static let userAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) "
        + "AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1"

    private let client: CampusAuthenticatedClient
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()
    private var sessionContext: SessionContext?

    init(client: CampusAuthenticatedClient) {
        self.client = client
    }

    func catalog() async throws -> EvaluationCatalog {
        let envelope: EvaluationAPIEnvelope<[EvaluationSemester]> = try await authorizedEnvelope(
            path: "api/v1/common/drop-down/stu_semester",
            queryItems: [
                URLQueryItem(name: "enabled", value: "true"),
                URLQueryItem(name: "idc_", value: "self")
            ]
        )
        let semesters = try requireData(envelope, fallback: "加载评教学期失败")
        let currentSemesterID = sessionContext?.currentSemesterID ?? ""
        return EvaluationCatalog(semesters: semesters, currentSemesterID: currentSemesterID)
    }

    func tasks(semesterID: String) async throws -> [EvaluationCourseTask] {
        let envelope: EvaluationAPIEnvelope<EvaluationSearchResult> = try await authorizedEnvelope(
            path: "api/v1/for-student/student-summation-forstudent/search",
            queryItems: [
                URLQueryItem(name: "queryPage__", value: "1,50"),
                URLQueryItem(name: "orderBy", value: ""),
                URLQueryItem(name: "semesterId", value: semesterID),
                URLQueryItem(name: "evaluated", value: "false")
            ]
        )
        return try requireData(envelope, fallback: "加载待评课程失败").items
    }

    func questionnaire(id: String) async throws -> EvaluationQuestionnaireForm {
        let envelope: EvaluationAPIEnvelope<EvaluationQuestionnairePayload> = try await authorizedEnvelope(
            path: "api/v1/for-student/student-summation-forstudent/search-questionnaire/\(id)"
        )
        let payload = try requireData(envelope, fallback: "加载评教问卷失败")
        guard let data = payload.questionsJSON.data(using: .utf8) else {
            throw EvaluationModelError.invalidQuestionnaire
        }
        do {
            let questions = try decoder.decode([EvaluationQuestion].self, from: data)
            return EvaluationQuestionnaireForm(
                questionnaire: EvaluationQuestionnaire(
                    id: payload.id,
                    name: payload.name,
                    enabled: payload.enabled,
                    questions: questions
                )
            )
        } catch {
            throw EvaluationModelError.invalidQuestionnaire
        }
    }

    func checkSubmit(_ request: EvaluationSubmitRequest) async throws -> String {
        let body = try encoder.encode(request)
        let envelope: EvaluationAPIEnvelope<String> = try await authorizedEnvelope(
            path: "api/v1/for-student/student-summation-forstudent/check-submit",
            method: "POST",
            body: body
        )
        try requireSuccess(envelope, fallback: "提交检查失败")
        return envelope.data ?? ""
    }

    func submit(_ request: EvaluationSubmitRequest) async throws {
        let body = try encoder.encode(request)
        let envelope: EvaluationAPIEnvelope<IgnoredPayload> = try await authorizedEnvelope(
            path: "api/v1/for-student/student-summation-forstudent/submit",
            method: "POST",
            body: body
        )
        try requireSuccess(envelope, fallback: "提交评教失败")
    }

    private func authorizedEnvelope<Value: Decodable & Sendable>(
        path: String,
        queryItems: [URLQueryItem] = [],
        method: String = "GET",
        body: Data? = nil
    ) async throws -> EvaluationAPIEnvelope<Value> {
        let initial = try await ensureSession()
        do {
            let envelope: EvaluationAPIEnvelope<Value> = try await requestEnvelope(
                path: path,
                queryItems: queryItems,
                method: method,
                body: body,
                token: initial.token
            )
            guard EvaluationSessionRetryPolicy.shouldRenew(forEnvelopeCode: envelope.code) else {
                return envelope
            }
            return try await retryEnvelopeAfterRenewingSession(
                path: path,
                queryItems: queryItems,
                method: method,
                body: body
            )
        } catch CampusWebError.unauthorized {
            return try await retryEnvelopeAfterRenewingSession(
                path: path,
                queryItems: queryItems,
                method: method,
                body: body
            )
        }
    }

    private func retryEnvelopeAfterRenewingSession<Value: Decodable & Sendable>(
        path: String,
        queryItems: [URLQueryItem],
        method: String,
        body: Data?
    ) async throws -> EvaluationAPIEnvelope<Value> {
        sessionContext = nil
        let renewed = try await bootstrap()
        return try await requestEnvelope(
            path: path,
            queryItems: queryItems,
            method: method,
            body: body,
            token: renewed.token
        )
    }

    private func ensureSession() async throws -> SessionContext {
        if let sessionContext {
            return sessionContext
        }
        return try await bootstrap()
    }

    private func bootstrap() async throws -> SessionContext {
        let entryResponse = try await client.response(
            url: Self.entryURL,
            headers: entryHeaders,
            followsRedirects: false,
            refreshesSessionOnUnauthorized: true
        )
        guard
            (300..<400).contains(entryResponse.statusCode),
            let location = entryResponse.header("Location")
        else {
            throw EvaluationModelError.invalidEntryRedirect
        }
        let seedToken = try EvaluationTokenParser.token(from: location)
        _ = try await client.clearCookies(scopedTo: Self.serviceURL)

        let renewBody = try encoder.encode(["token": seedToken])
        let renewEnvelope: EvaluationAPIEnvelope<EvaluationLoginResult> = try await requestEnvelope(
            path: "token/renew",
            method: "POST",
            body: renewBody,
            token: seedToken
        )
        let login = try requireData(renewEnvelope, fallback: "评教凭证续期失败")
        guard !login.token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw EvaluationModelError.server("评教凭证续期失败")
        }
        let renewedToken = login.token

        let accountEnvelope: EvaluationAPIEnvelope<EvaluationAccount> = try await requestEnvelope(
            path: "api/v1/poa/sys-auth/account/get-by-login-name",
            queryItems: [URLQueryItem(name: "token", value: renewedToken)],
            token: renewedToken
        )
        let account = try requireData(accountEnvelope, fallback: "评教身份初始化失败")

        let yearEnvelope: EvaluationAPIEnvelope<IgnoredPayload> = try await requestEnvelope(
            path: "api/v1/common/home/current-year",
            queryItems: [URLQueryItem(name: "token", value: renewedToken)],
            token: renewedToken
        )
        try requireSuccess(yearEnvelope, fallback: "评教学年初始化失败")

        let identity = account.currentIdentity.isEmpty ? "STUDENT" : account.currentIdentity
        let menuEnvelope = try await homeMenu(identity: identity, token: renewedToken)
        try requireSuccess(menuEnvelope, fallback: "评教菜单初始化失败")

        let context = SessionContext(
            token: renewedToken,
            currentSemesterID: account.currentSemesterID
        )
        sessionContext = context
        return context
    }

    private func homeMenu(
        identity: String,
        token: String
    ) async throws -> EvaluationAPIEnvelope<IgnoredPayload> {
        do {
            return try await requestEnvelope(
                path: "api/v1/common/home/menu",
                queryItems: [URLQueryItem(name: "identity", value: identity)],
                token: token
            )
        } catch CampusWebError.unauthorized {
            _ = try await client.clearCookies(scopedTo: Self.serviceURL)
            return try await requestEnvelope(
                path: "api/v1/common/home/menu",
                queryItems: [URLQueryItem(name: "identity", value: identity)],
                token: token
            )
        }
    }

    private func requestEnvelope<Value: Decodable & Sendable>(
        path: String,
        queryItems: [URLQueryItem] = [],
        method: String = "GET",
        body: Data? = nil,
        token: String
    ) async throws -> EvaluationAPIEnvelope<Value> {
        let url = Self.serviceURL
            .appending(path: path)
            .appendingQueryItems(queryItems)
        var headers = apiHeaders
        headers["Authorization"] = token
        if method != "GET" {
            headers["Origin"] = "https://jw.ahu.edu.cn"
        }
        let response = try await client.response(
            url: url,
            method: method,
            body: body,
            contentType: body == nil ? nil : "application/json;charset=UTF-8",
            headers: headers,
            followsRedirects: true,
            refreshesSessionOnUnauthorized: false
        )
        do {
            return try decoder.decode(EvaluationAPIEnvelope<Value>.self, from: response.data)
        } catch {
            throw CampusWebError.invalidResponse
        }
    }

    private func requireSuccess<Value: Decodable & Sendable>(
        _ envelope: EvaluationAPIEnvelope<Value>,
        fallback: String
    ) throws {
        guard envelope.code == 0 else {
            throw EvaluationModelError.server(envelope.message.isEmpty ? fallback : envelope.message)
        }
    }

    private func requireData<Value: Decodable & Sendable>(
        _ envelope: EvaluationAPIEnvelope<Value>,
        fallback: String
    ) throws -> Value {
        try requireSuccess(envelope, fallback: fallback)
        guard let value = envelope.data else {
            throw EvaluationModelError.server(fallback)
        }
        return value
    }

    private var entryHeaders: [String: String] {
        [
            "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
            "Accept-Language": "zh-CN,zh;q=0.9",
            "Referer": Self.studentReferer,
            "User-Agent": Self.userAgent
        ]
    }

    private var apiHeaders: [String: String] {
        [
            "Accept": "application/json, text/plain, */*",
            "Accept-Language": "zh-CN,zh;q=0.9",
            "Referer": Self.evaluationReferer,
            "User-Agent": Self.userAgent
        ]
    }
}
