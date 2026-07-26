import Foundation

struct EvaluationAPIEnvelope<Value: Decodable & Sendable>: Decodable, Sendable {
    let code: Int
    let message: String
    let data: Value?

    enum CodingKeys: String, CodingKey {
        case code
        case message = "msg"
        case data
    }
}

struct EvaluationLoginResult: Decodable, Sendable {
    let token: String
}

struct EvaluationAccount: Decodable, Sendable {
    let currentIdentity: String
    let currentSemesterID: String

    enum CodingKeys: String, CodingKey {
        case currentIdentity
        case currentSemesterID = "currentSemesterId"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        currentIdentity = try container.decodeIfPresent(String.self, forKey: .currentIdentity) ?? "STUDENT"
        currentSemesterID = try container.decodeIfPresent(String.self, forKey: .currentSemesterID) ?? ""
    }
}

struct EvaluationSemester: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let name: String
    let code: String
    let schoolYear: String

    enum CodingKeys: String, CodingKey {
        case id
        case name = "nameZh"
        case code
        case schoolYear
    }

    init(id: String, name: String, code: String = "", schoolYear: String = "") {
        self.id = id
        self.name = name
        self.code = code
        self.schoolYear = schoolYear
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id) ?? ""
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        code = try container.decodeIfPresent(String.self, forKey: .code) ?? ""
        schoolYear = try container.decodeIfPresent(String.self, forKey: .schoolYear) ?? ""
    }
}

struct EvaluationSearchResult: Decodable, Sendable {
    let items: [EvaluationCourseTask]

    enum CodingKeys: String, CodingKey {
        case items = "data"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        items = try container.decodeIfPresent([EvaluationCourseTask].self, forKey: .items) ?? []
    }
}

struct EvaluationCourseTask: Codable, Equatable, Identifiable, Sendable {
    let lessonID: String
    let courseName: String
    let lessonName: String
    let tasks: [EvaluationTask]

    var id: String { lessonID.isEmpty ? "\(courseName)|\(lessonName)" : lessonID }

    enum CodingKeys: String, CodingKey {
        case lessonID = "lessonId"
        case courseName
        case lessonName = "lessonNameZh"
        case tasks = "taskList"
    }

    init(
        lessonID: String,
        courseName: String,
        lessonName: String,
        tasks: [EvaluationTask]
    ) {
        self.lessonID = lessonID
        self.courseName = courseName
        self.lessonName = lessonName
        self.tasks = tasks
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        lessonID = try container.decodeIfPresent(String.self, forKey: .lessonID) ?? ""
        courseName = try container.decodeIfPresent(String.self, forKey: .courseName) ?? ""
        lessonName = try container.decodeIfPresent(String.self, forKey: .lessonName) ?? ""
        tasks = try container.decodeIfPresent([EvaluationTask].self, forKey: .tasks) ?? []
    }
}

struct EvaluationTask: Codable, Equatable, Identifiable, Sendable {
    let questionnaireID: String
    let questionnaireName: String
    let isOpen: Bool
    let taskID: String
    let teachers: [EvaluationTeacher]

    var id: String { taskID.isEmpty ? questionnaireID : taskID }

    enum CodingKeys: String, CodingKey {
        case questionnaireID = "evaluationQuestionnaireId"
        case questionnaireName = "evaluationQuestionnaireName"
        case isOpen = "timeStatus"
        case taskID = "stdSumTaskId"
        case teachers
    }

    init(
        questionnaireID: String,
        questionnaireName: String,
        isOpen: Bool,
        taskID: String,
        teachers: [EvaluationTeacher]
    ) {
        self.questionnaireID = questionnaireID
        self.questionnaireName = questionnaireName
        self.isOpen = isOpen
        self.taskID = taskID
        self.teachers = teachers
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        questionnaireID = try container.decodeIfPresent(String.self, forKey: .questionnaireID) ?? ""
        questionnaireName = try container.decodeIfPresent(String.self, forKey: .questionnaireName) ?? ""
        isOpen = try container.decodeIfPresent(Bool.self, forKey: .isOpen) ?? false
        taskID = try container.decodeIfPresent(String.self, forKey: .taskID) ?? ""
        teachers = try container.decodeIfPresent([EvaluationTeacher].self, forKey: .teachers) ?? []
    }
}

struct EvaluationTeacher: Codable, Equatable, Identifiable, Sendable {
    let taskID: String
    let teacherID: String
    let name: String
    let status: String

    var id: String {
        let stable = taskID.isEmpty ? teacherID : taskID
        return stable.isEmpty ? name : stable
    }

    var needsReview: Bool { status == "TO_REVIEW" }

    enum CodingKeys: String, CodingKey {
        case taskID = "stdSumTaskId"
        case teacherID = "teacherId"
        case name = "teacherName"
        case status
    }

    init(taskID: String, teacherID: String, name: String, status: String) {
        self.taskID = taskID
        self.teacherID = teacherID
        self.name = name
        self.status = status
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        taskID = try container.decodeIfPresent(String.self, forKey: .taskID) ?? ""
        teacherID = try container.decodeIfPresent(String.self, forKey: .teacherID) ?? ""
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        status = try container.decodeIfPresent(String.self, forKey: .status) ?? ""
    }
}

struct EvaluationQuestionnairePayload: Decodable, Sendable {
    let id: String
    let name: String
    let enabled: Bool
    let questionsJSON: String

    enum CodingKeys: String, CodingKey {
        case id
        case name = "nameZh"
        case enabled = "enable"
        case questionsJSON = "questions"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id) ?? ""
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        questionsJSON = try container.decodeIfPresent(String.self, forKey: .questionsJSON) ?? "[]"
    }
}

struct EvaluationQuestionnaire: Equatable, Sendable {
    let id: String
    let name: String
    let enabled: Bool
    let questions: [EvaluationQuestion]
}

struct EvaluationQuestion: Codable, Equatable, Identifiable, Sendable {
    let index: Int
    let attribute: EvaluationQuestionAttribute
    let options: [EvaluationOption]
    let setting: EvaluationOptionSetting

    var id: String { String(attribute.id) }

    enum CodingKeys: String, CodingKey {
        case index
        case attribute
        case options
        case setting = "optionSetting"
    }

    init(
        index: Int,
        attribute: EvaluationQuestionAttribute,
        options: [EvaluationOption],
        setting: EvaluationOptionSetting = .init()
    ) {
        self.index = index
        self.attribute = attribute
        self.options = options
        self.setting = setting
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        index = try container.decodeIfPresent(Int.self, forKey: .index) ?? 0
        attribute = try container.decodeIfPresent(EvaluationQuestionAttribute.self, forKey: .attribute) ?? .init()
        options = try container.decodeIfPresent([EvaluationOption].self, forKey: .options) ?? []
        setting = try container.decodeIfPresent(EvaluationOptionSetting.self, forKey: .setting) ?? .init()
    }
}

struct EvaluationQuestionAttribute: Codable, Equatable, Sendable {
    let id: Int
    let typeID: Int
    let title: String
    let isRequired: Bool
    let enablesScore: Bool

    enum CodingKeys: String, CodingKey {
        case id
        case typeID = "typeId"
        case title = "name"
        case legacyTitle = "questionItemNameZh"
        case isRequired = "required"
        case enablesScore = "enableScore"
    }

    init(
        id: Int = 0,
        typeID: Int = 0,
        title: String = "",
        isRequired: Bool = false,
        enablesScore: Bool = false
    ) {
        self.id = id
        self.typeID = typeID
        self.title = title
        self.isRequired = isRequired
        self.enablesScore = enablesScore
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(Int.self, forKey: .id) ?? 0
        typeID = try container.decodeIfPresent(Int.self, forKey: .typeID) ?? 0
        let preferredTitle = try container.decodeIfPresent(String.self, forKey: .title)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let legacyTitle = try container.decodeIfPresent(String.self, forKey: .legacyTitle)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        title = preferredTitle?.isEmpty == false ? preferredTitle! : legacyTitle ?? ""
        isRequired = try container.decodeIfPresent(Bool.self, forKey: .isRequired) ?? false
        enablesScore = try container.decodeIfPresent(Bool.self, forKey: .enablesScore) ?? false
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(typeID, forKey: .typeID)
        try container.encode(title, forKey: .title)
        try container.encode(isRequired, forKey: .isRequired)
        try container.encode(enablesScore, forKey: .enablesScore)
    }
}

struct EvaluationOption: Codable, Equatable, Identifiable, Sendable {
    let id: Int
    let score: Double
    let value: String

    enum CodingKeys: String, CodingKey {
        case id = "optionId"
        case score = "optionScore"
        case value
    }

    init(id: Int, score: Double = 0, value: String) {
        self.id = id
        self.score = score
        self.value = value
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(Int.self, forKey: .id) ?? 0
        score = try container.decodeIfPresent(Double.self, forKey: .score) ?? 0
        value = try container.decodeIfPresent(String.self, forKey: .value) ?? ""
    }
}

struct EvaluationOptionSetting: Codable, Equatable, Sendable {
    let maximumWords: Int?
    let minimumWords: String?

    enum CodingKeys: String, CodingKey {
        case maximumWords = "maxWords"
        case minimumWords = "minWords"
    }

    init(maximumWords: Int? = nil, minimumWords: String? = nil) {
        self.maximumWords = maximumWords
        self.minimumWords = minimumWords
    }
}

struct EvaluationPreset: Codable, Equatable, Sendable {
    var optionIndexes: [String: Int]
    var textAnswers: [String: String]
    var isAnonymous: Bool

    static let defaultComment = "老师授课认真负责，课堂内容清晰，学习收获较多。"

    init(
        optionIndexes: [String: Int] = [:],
        textAnswers: [String: String] = [:],
        isAnonymous: Bool = false
    ) {
        self.optionIndexes = optionIndexes
        self.textAnswers = textAnswers
        self.isAnonymous = isAnonymous
    }
}

struct EvaluationSubmitRequest: Codable, Equatable, Sendable {
    let id: String?
    let taskID: String
    let isAnonymous: Bool
    let questionnaire: EvaluationQuestionnaireResponse

    enum CodingKeys: String, CodingKey {
        case id
        case taskID = "stdSumTaskId"
        case isAnonymous = "anonymous"
        case questionnaire = "evaluationQuestionnaireRes"
    }
}

struct EvaluationQuestionnaireResponse: Codable, Equatable, Sendable {
    let id: String?
    let questionnaireID: String
    let questionnaireName: String
    let enabled: Bool
    let answer: String
    let score: Double
    let answers: [EvaluationQuestionAnswer]

    enum CodingKeys: String, CodingKey {
        case id
        case questionnaireID = "questionnaireId"
        case questionnaireName
        case enabled = "enable"
        case answer
        case score
        case answers = "questionAnsSaveList"
    }
}

struct EvaluationQuestionAnswer: Codable, Equatable, Sendable {
    let questionID: String
    let questionnaireID: String
    let type: String
    let score: Double
    let answer: String?
    let options: [EvaluationAnswerOption]

    enum CodingKeys: String, CodingKey {
        case questionID = "questionId"
        case questionnaireID = "questionnaireId"
        case type
        case score
        case answer
        case options = "questionAnsExpSaveList"
    }
}

struct EvaluationAnswerOption: Codable, Equatable, Sendable {
    let optionID: String
    let questionnaireID: String
    let value: String?
    let score: Double?

    enum CodingKeys: String, CodingKey {
        case optionID = "optionId"
        case questionnaireID = "questionnaireId"
        case value
        case score
    }
}

enum EvaluationModelError: LocalizedError, Equatable {
    case invalidEntryRedirect
    case invalidQuestionnaire
    case server(String)

    var errorDescription: String? {
        switch self {
        case .invalidEntryRedirect: "评教入口未返回有效登录凭证"
        case .invalidQuestionnaire: "评教问卷格式无法识别"
        case let .server(message): message
        }
    }
}

enum GradeEvaluationGate {
    static let message = "请先完成评教"

    static func isRequired(_ payload: String?) -> Bool {
        guard let source = payload, !source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return false
        }
        let plain = displayText(source)
            .replacingOccurrences(of: #"\s+"#, with: "", options: .regularExpression)
        let lower = source.lowercased()
        let mentionsEvaluation = plain.contains("评教")
            || plain.contains("评价")
            || plain.contains("教学质量")
        let instructsFirst = plain.contains("请先")
            || plain.contains("先完成")
            || plain.contains("完成后")
        return (mentionsEvaluation && instructsFirst)
            || lower.contains("student-summation")
            || lower.contains("summation-forstudent")
    }

    static func displayText(_ payload: String?) -> String {
        guard let payload else { return "" }
        return payload
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&#160;", with: " ")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
