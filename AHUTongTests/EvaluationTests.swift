import Foundation
import XCTest
@testable import AHUTong

final class EvaluationTokenParserTests: XCTestCase {
    func testParsesPercentEncodedTokenFromRedirectFragment() throws {
        let location = "https://jw.ahu.edu.cn/evaluation-student-frontend/"
            + "#/home?bizTypeId=2&token=seed%2Bvalue%3D&other=1"

        XCTAssertEqual(
            try EvaluationTokenParser.token(from: location),
            "seed+value="
        )
    }

    func testParsesTokenFromOrdinaryQueryAndRejectsMissingToken() throws {
        XCTAssertEqual(
            try EvaluationTokenParser.token(
                from: "https://jw.ahu.edu.cn/evaluation-student-frontend/?token=query-token"
            ),
            "query-token"
        )
        XCTAssertThrowsError(
            try EvaluationTokenParser.token(
                from: "https://jw.ahu.edu.cn/evaluation-student-frontend/#/home"
            )
        ) { error in
            XCTAssertEqual(error as? EvaluationModelError, .invalidEntryRedirect)
        }
    }
}

final class EvaluationSessionRetryPolicyTests: XCTestCase {
    func testRenewsForNonzeroBusinessEnvelopeCodeOnly() {
        XCTAssertFalse(EvaluationSessionRetryPolicy.shouldRenew(forEnvelopeCode: 0))
        XCTAssertTrue(EvaluationSessionRetryPolicy.shouldRenew(forEnvelopeCode: 401))
        XCTAssertTrue(EvaluationSessionRetryPolicy.shouldRenew(forEnvelopeCode: -1))
    }
}

final class EvaluationModelDecodingTests: XCTestCase {
    func testDecodesNestedPendingTaskEnvelope() throws {
        let data = Data(
            """
            {
              "code": 0,
              "msg": "",
              "data": {
                "data": [{
                  "lessonId": "lesson-1",
                  "courseName": "操作系统",
                  "lessonNameZh": "操作系统-01",
                  "taskList": [{
                    "evaluationQuestionnaireId": "questionnaire-1",
                    "evaluationQuestionnaireName": "课堂教学质量评价",
                    "timeStatus": true,
                    "stdSumTaskId": "task-fallback",
                    "teachers": [{
                      "stdSumTaskId": "task-teacher",
                      "teacherId": "teacher-1",
                      "teacherName": "张老师",
                      "status": "TO_REVIEW"
                    }]
                  }]
                }]
              }
            }
            """.utf8
        )

        let envelope = try JSONDecoder().decode(
            EvaluationAPIEnvelope<EvaluationSearchResult>.self,
            from: data
        )

        XCTAssertEqual(envelope.code, 0)
        XCTAssertEqual(envelope.data?.items.first?.courseName, "操作系统")
        XCTAssertEqual(envelope.data?.items.first?.tasks.first?.questionnaireID, "questionnaire-1")
        XCTAssertEqual(envelope.data?.items.first?.tasks.first?.teachers.first?.name, "张老师")
        XCTAssertTrue(envelope.data?.items.first?.tasks.first?.teachers.first?.needsReview == true)
    }

    func testDecodesRadioAndTextQuestionModels() throws {
        let data = Data(
            """
            [{
              "index": 1,
              "attribute": {
                "id": 101,
                "typeId": 1,
                "questionItemNameZh": "教师备课是否充分",
                "required": true,
                "enableScore": true
              },
              "options": [
                {"optionId": 1, "optionScore": 5, "value": "非常满意"},
                {"optionId": 2, "optionScore": 4, "value": "满意"}
              ],
              "optionSetting": {}
            }, {
              "index": 2,
              "attribute": {
                "id": 102,
                "typeId": 4,
                "questionItemNameZh": "意见建议",
                "required": true,
                "enableScore": false
              },
              "options": [],
              "optionSetting": {"maxWords": 200, "minWords": "1"}
            }]
            """.utf8
        )

        let questions = try JSONDecoder().decode([EvaluationQuestion].self, from: data)

        XCTAssertEqual(questions.map(\.attribute.typeID), [1, 4])
        XCTAssertEqual(questions[0].options.first?.score, 5)
        XCTAssertEqual(questions[1].setting.maximumWords, 200)
    }

    func testQuestionTitlePrefersNameAndFallsBackToLegacyField() throws {
        let data = Data(
            """
            [{
              "index": 1,
              "attribute": {
                "id": 101,
                "typeId": 1,
                "name": "线上实际题目",
                "questionItemNameZh": "旧题目",
                "required": true
              }
            }, {
              "index": 2,
              "attribute": {
                "id": 102,
                "typeId": 4,
                "questionItemNameZh": "兼容旧字段"
              }
            }]
            """.utf8
        )

        let questions = try JSONDecoder().decode([EvaluationQuestion].self, from: data)

        XCTAssertEqual(questions.map(\.attribute.title), ["线上实际题目", "兼容旧字段"])
    }
}

final class EvaluationSubmissionLogicTests: XCTestCase {
    func testRequiredValidationCoversRadioTextAndCompletion() {
        let questions = Self.questions

        XCTAssertEqual(
            EvaluationSubmissionLogic.requiredValidationMessage(
                questions: questions,
                optionAnswers: [:],
                textAnswers: [:]
            ),
            "请完成第 1 题"
        )
        XCTAssertEqual(
            EvaluationSubmissionLogic.requiredValidationMessage(
                questions: questions,
                optionAnswers: ["101": 1],
                textAnswers: [:]
            ),
            "请完成第 2 题"
        )
        XCTAssertNil(
            EvaluationSubmissionLogic.requiredValidationMessage(
                questions: questions,
                optionAnswers: ["101": 1],
                textAnswers: ["102": "课程内容清晰"]
            )
        )
    }

    func testBuildsServerSubmitRequestWithTeacherTaskAndAnonymousFlag() throws {
        let target = Self.target(teacherTaskID: "teacher-task")
        let questionnaire = EvaluationQuestionnaire(
            id: "questionnaire-1",
            name: "课堂教学质量评价",
            enabled: true,
            questions: Self.questions
        )

        let request = EvaluationSubmissionLogic.buildRequest(
            target: target,
            questionnaire: questionnaire,
            optionAnswers: ["101": 2],
            textAnswers: ["102": "建议增加实践环节"],
            anonymous: true
        )

        XCTAssertEqual(request.taskID, "teacher-task")
        XCTAssertTrue(request.isAnonymous)
        XCTAssertEqual(request.questionnaire.answers[0].score, 4)
        XCTAssertEqual(request.questionnaire.answers[0].options.first?.optionID, "2")
        XCTAssertEqual(request.questionnaire.answers[1].answer, "建议增加实践环节")

        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(request)) as? [String: Any]
        )
        XCTAssertEqual(object["stdSumTaskId"] as? String, "teacher-task")
        XCTAssertEqual(object["anonymous"] as? Bool, true)
        XCTAssertNotNil(object["evaluationQuestionnaireRes"])
    }

    func testPresetResolvesRadioTextAndAvoidsUniformDefaultChoice() {
        let secondRadio = EvaluationQuestion(
            index: 2,
            attribute: EvaluationQuestionAttribute(
                id: 103,
                typeID: 1,
                title: "课堂互动是否充分",
                isRequired: true,
                enablesScore: true
            ),
            options: [
                EvaluationOption(id: 11, score: 5, value: "非常满意"),
                EvaluationOption(id: 12, score: 4, value: "满意")
            ]
        )
        let text = Self.questions[1]
        let questions = [Self.questions[0], secondRadio, text]

        let answers = EvaluationSubmissionLogic.answers(
            applying: EvaluationPreset(),
            to: questions
        )

        XCTAssertEqual(answers.options["101"], 1)
        XCTAssertEqual(answers.options["103"], 12)
        XCTAssertEqual(answers.text["102"], EvaluationPreset.defaultComment)
    }

    static let questions = [
        EvaluationQuestion(
            index: 1,
            attribute: EvaluationQuestionAttribute(
                id: 101,
                typeID: 1,
                title: "教师备课是否充分",
                isRequired: true,
                enablesScore: true
            ),
            options: [
                EvaluationOption(id: 1, score: 5, value: "非常满意"),
                EvaluationOption(id: 2, score: 4, value: "满意")
            ]
        ),
        EvaluationQuestion(
            index: 2,
            attribute: EvaluationQuestionAttribute(
                id: 102,
                typeID: 4,
                title: "意见建议",
                isRequired: true,
                enablesScore: false
            ),
            options: [],
            setting: EvaluationOptionSetting(maximumWords: 200, minimumWords: "1")
        )
    ]

    static func target(teacherTaskID: String) -> EvaluationSubmissionTarget {
        let teacher = EvaluationTeacher(
            taskID: teacherTaskID,
            teacherID: "teacher-1",
            name: "张老师",
            status: "TO_REVIEW"
        )
        let task = EvaluationTask(
            questionnaireID: "questionnaire-1",
            questionnaireName: "课堂教学质量评价",
            isOpen: true,
            taskID: "fallback-task",
            teachers: [teacher]
        )
        let course = EvaluationCourseTask(
            lessonID: "lesson-1",
            courseName: "操作系统",
            lessonName: "操作系统-01",
            tasks: [task]
        )
        return EvaluationSubmissionTarget(course: course, task: task, teacher: teacher)
    }
}

@MainActor
final class EvaluationBulkSubmissionTests: XCTestCase {
    func testBulkSubmissionContinuesAfterFailureAndReportsPartialResult() async {
        let first = EvaluationTeacher(
            taskID: "teacher-task-1",
            teacherID: "teacher-1",
            name: "张老师",
            status: "TO_REVIEW"
        )
        let second = EvaluationTeacher(
            taskID: "teacher-task-2",
            teacherID: "teacher-2",
            name: "李老师",
            status: "TO_REVIEW"
        )
        let task = EvaluationTask(
            questionnaireID: "questionnaire-1",
            questionnaireName: "课堂教学质量评价",
            isOpen: true,
            taskID: "fallback-task",
            teachers: [first, second]
        )
        let course = EvaluationCourseTask(
            lessonID: "lesson-1",
            courseName: "操作系统",
            lessonName: "操作系统-01",
            tasks: [task]
        )
        let questionnaire = EvaluationQuestionnaire(
            id: "questionnaire-1",
            name: "课堂教学质量评价",
            enabled: true,
            questions: EvaluationSubmissionLogicTests.questions
        )
        let service = MockEvaluationService(
            courses: [course],
            questionnaire: questionnaire,
            failingTaskIDs: ["teacher-task-2"]
        )
        let suite = "EvaluationTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let model = EvaluationViewModel(
            service: service,
            presetStore: EvaluationPresetStore(defaults: defaults)
        )

        await model.load()
        await model.submitAllWithPreset()

        XCTAssertEqual(
            model.bulkState,
            .partiallyFailed(
                completed: 1,
                total: 2,
                firstError: "mock failure"
            )
        )
        let submittedTaskIDs = await service.submittedTaskIDs()
        XCTAssertEqual(submittedTaskIDs, ["teacher-task-1", "teacher-task-2"])
    }
}

private actor MockEvaluationService: EvaluationServicing {
    private let courses: [EvaluationCourseTask]
    private let form: EvaluationQuestionnaireForm
    private let failingTaskIDs: Set<String>
    private var submissions: [String] = []

    init(
        courses: [EvaluationCourseTask],
        questionnaire: EvaluationQuestionnaire,
        failingTaskIDs: Set<String>
    ) {
        self.courses = courses
        form = EvaluationQuestionnaireForm(questionnaire: questionnaire)
        self.failingTaskIDs = failingTaskIDs
    }

    func catalog() async throws -> EvaluationCatalog {
        EvaluationCatalog(
            semesters: [
                EvaluationSemester(
                    id: "semester-1",
                    name: "2025-2026学年第二学期"
                )
            ],
            currentSemesterID: "semester-1"
        )
    }

    func tasks(semesterID: String) async throws -> [EvaluationCourseTask] {
        courses
    }

    func questionnaire(id: String) async throws -> EvaluationQuestionnaireForm {
        form
    }

    func checkSubmit(_ request: EvaluationSubmitRequest) async throws -> String {
        ""
    }

    func submit(_ request: EvaluationSubmitRequest) async throws {
        submissions.append(request.taskID)
        if failingTaskIDs.contains(request.taskID) {
            throw EvaluationModelError.server("mock failure")
        }
    }

    func submittedTaskIDs() -> [String] {
        submissions
    }
}
