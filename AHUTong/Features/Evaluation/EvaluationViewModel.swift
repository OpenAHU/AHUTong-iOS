import Combine
import Foundation

struct EvaluationSubmissionTarget: Equatable, Identifiable, Sendable {
    let course: EvaluationCourseTask
    let task: EvaluationTask
    let teacher: EvaluationTeacher

    var id: String {
        "\(course.id)|\(task.id)|\(teacher.id)"
    }

    var canSubmit: Bool {
        task.isOpen && teacher.needsReview
    }
}

enum EvaluationBulkSubmissionState: Equatable, Sendable {
    case idle
    case submitting(processed: Int, total: Int)
    case succeeded(count: Int)
    case partiallyFailed(completed: Int, total: Int, firstError: String)
    case failed(String)

    var isSubmitting: Bool {
        if case .submitting = self { return true }
        return false
    }

    var message: String? {
        switch self {
        case .idle, .submitting:
            nil
        case let .succeeded(count):
            "已按预设完成 \(count) 项评教"
        case let .partiallyFailed(completed, total, firstError):
            "已完成 \(completed)/\(total) 项，失败：\(firstError)"
        case let .failed(message):
            message
        }
    }
}

enum EvaluationSubmissionLogic {
    static func requiredValidationMessage(
        questions: [EvaluationQuestion],
        optionAnswers: [String: Int],
        textAnswers: [String: String]
    ) -> String? {
        let firstMissing = questions.first { question in
            guard question.attribute.isRequired else { return false }
            switch question.attribute.typeID {
            case 1:
                return optionAnswers[question.id] == nil
            case 4:
                return textAnswers[question.id]?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .isEmpty != false
            default:
                return true
            }
        }
        guard let firstMissing else { return nil }
        let number: Int
        if firstMissing.index > 0 {
            number = firstMissing.index
        } else {
            number = questions.firstIndex(of: firstMissing).map { $0 + 1 } ?? 1
        }
        return "请完成第 \(number) 题"
    }

    static func buildRequest(
        target: EvaluationSubmissionTarget,
        questionnaire: EvaluationQuestionnaire,
        optionAnswers: [String: Int],
        textAnswers: [String: String],
        anonymous: Bool
    ) -> EvaluationSubmitRequest {
        let answers = questionnaire.questions.map { question in
            let questionID = question.id
            switch question.attribute.typeID {
            case 1:
                let selectedID = optionAnswers[questionID]
                let option = question.options.first { $0.id == selectedID }
                return EvaluationQuestionAnswer(
                    questionID: questionID,
                    questionnaireID: questionnaire.id,
                    type: "1",
                    score: question.attribute.enablesScore ? option?.score ?? 0 : 0,
                    answer: nil,
                    options: [
                        EvaluationAnswerOption(
                            optionID: selectedID.map { String($0) } ?? "",
                            questionnaireID: questionnaire.id,
                            value: nil,
                            score: nil
                        )
                    ]
                )
            case 4:
                return EvaluationQuestionAnswer(
                    questionID: questionID,
                    questionnaireID: questionnaire.id,
                    type: "4",
                    score: 0,
                    answer: textAnswers[questionID] ?? "",
                    options: []
                )
            default:
                return EvaluationQuestionAnswer(
                    questionID: questionID,
                    questionnaireID: questionnaire.id,
                    type: String(question.attribute.typeID),
                    score: 0,
                    answer: nil,
                    options: []
                )
            }
        }
        return EvaluationSubmitRequest(
            id: nil,
            taskID: target.teacher.taskID.isEmpty ? target.task.taskID : target.teacher.taskID,
            isAnonymous: anonymous,
            questionnaire: EvaluationQuestionnaireResponse(
                id: nil,
                questionnaireID: questionnaire.id,
                questionnaireName: questionnaire.name.isEmpty
                    ? target.task.questionnaireName
                    : questionnaire.name,
                enabled: questionnaire.enabled,
                answer: "[]",
                score: 0,
                answers: answers
            )
        )
    }

    static func normalizedPreset(
        questions: [EvaluationQuestion],
        optionIndexes: [String: Int],
        textAnswers: [String: String],
        isAnonymous: Bool
    ) -> EvaluationPreset {
        var normalizedIndexes: [String: Int] = [:]
        let radioQuestions = questions.filter {
            $0.attribute.typeID == 1 && !$0.options.isEmpty
        }
        for question in radioQuestions {
            let upperBound = max(question.options.count - 1, 0)
            normalizedIndexes[question.id] = min(max(optionIndexes[question.id] ?? 0, 0), upperBound)
        }
        normalizedIndexes = ensureOneDifferentIndex(normalizedIndexes, questions: radioQuestions)

        let validQuestionIDs = Set(questions.map(\.id))
        let normalizedText = textAnswers.reduce(into: [String: String]()) { result, item in
            guard validQuestionIDs.contains(item.key) else { return }
            let value = item.value.trimmingCharacters(in: .whitespacesAndNewlines)
            result[item.key] = value.isEmpty ? EvaluationPreset.defaultComment : value
        }
        return EvaluationPreset(
            optionIndexes: normalizedIndexes,
            textAnswers: normalizedText,
            isAnonymous: isAnonymous
        )
    }

    static func answers(
        applying preset: EvaluationPreset,
        to questions: [EvaluationQuestion]
    ) -> (options: [String: Int], text: [String: String]) {
        let indexes = normalizedPreset(
            questions: questions,
            optionIndexes: preset.optionIndexes,
            textAnswers: preset.textAnswers,
            isAnonymous: preset.isAnonymous
        ).optionIndexes
        var options: [String: Int] = [:]
        var text: [String: String] = [:]
        for question in questions {
            switch question.attribute.typeID {
            case 1:
                guard !question.options.isEmpty else { continue }
                let index = min(max(indexes[question.id] ?? 0, 0), question.options.count - 1)
                options[question.id] = question.options[index].id
            case 4:
                let value = preset.textAnswers[question.id]?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                text[question.id] = value?.isEmpty == false ? value : EvaluationPreset.defaultComment
            default:
                continue
            }
        }
        return (options, text)
    }

    private static func ensureOneDifferentIndex(
        _ indexes: [String: Int],
        questions: [EvaluationQuestion]
    ) -> [String: Int] {
        guard
            indexes.count >= 2,
            Set(indexes.values).count == 1,
            questions.count >= 2,
            questions[1].options.count >= 2,
            let current = indexes[questions[1].id]
        else {
            return indexes
        }
        var result = indexes
        result[questions[1].id] = current == 0 ? 1 : 0
        return result
    }
}

@MainActor
final class EvaluationPresetStore {
    private let defaults: UserDefaults
    private let key: String

    init(
        defaults: UserDefaults = .standard,
        key: String? = nil,
        userID: String? = nil
    ) {
        self.defaults = defaults
        self.key = key
            ?? userID.map { AccountPreferenceKey.make("evaluation.preset.v1", userID: $0) }
            ?? "evaluation.preset.v1"
    }

    func load() -> EvaluationPreset {
        guard
            let data = defaults.data(forKey: key),
            let value = try? JSONDecoder().decode(EvaluationPreset.self, from: data)
        else {
            return EvaluationPreset()
        }
        return value
    }

    func save(_ preset: EvaluationPreset) {
        guard let data = try? JSONEncoder().encode(preset) else { return }
        defaults.set(data, forKey: key)
    }
}

@MainActor
final class EvaluationViewModel: ObservableObject {
    @Published private(set) var semesters: [EvaluationSemester] = []
    @Published private(set) var selectedSemesterID = ""
    @Published private(set) var taskState: LoadableState<[EvaluationCourseTask]> = .idle
    @Published private(set) var selectedTarget: EvaluationSubmissionTarget?
    @Published private(set) var questionnaireState: LoadableState<EvaluationQuestionnaire> = .idle
    @Published private(set) var optionAnswers: [String: Int] = [:]
    @Published private(set) var textAnswers: [String: String] = [:]
    @Published private(set) var isSubmitting = false
    @Published private(set) var bulkState: EvaluationBulkSubmissionState = .idle
    @Published private(set) var message: String?
    @Published private(set) var preset: EvaluationPreset
    @Published private(set) var presetQuestions: [EvaluationQuestion] = []
    @Published private(set) var isPresetLoading = false

    private let service: any EvaluationServicing
    private let presetStore: EvaluationPresetStore

    init(service: any EvaluationServicing, presetStore: EvaluationPresetStore? = nil) {
        self.service = service
        let resolvedStore = presetStore ?? EvaluationPresetStore()
        self.presetStore = resolvedStore
        preset = resolvedStore.load()
    }

    var tasks: [EvaluationCourseTask] {
        taskState.value ?? []
    }

    var targets: [EvaluationSubmissionTarget] {
        tasks.flatMap { course in
            course.tasks.flatMap { task in
                task.teachers.map {
                    EvaluationSubmissionTarget(course: course, task: task, teacher: $0)
                }
            }
        }
    }

    var pendingTargets: [EvaluationSubmissionTarget] {
        targets.filter(\.canSubmit)
    }

    func load() async {
        taskState = .loading
        message = nil
        do {
            let catalog = try await service.catalog()
            semesters = catalog.semesters
            selectedSemesterID = catalog.semesters.first {
                $0.id == catalog.currentSemesterID
            }?.id ?? catalog.semesters.first?.id ?? ""
            guard !selectedSemesterID.isEmpty else {
                taskState = .empty
                return
            }
            await loadTasks()
        } catch {
            taskState = .failed(AppErrorState(message: error.localizedDescription))
        }
    }

    func selectSemester(_ semester: EvaluationSemester) async {
        guard selectedSemesterID != semester.id else { return }
        selectedSemesterID = semester.id
        await loadTasks()
    }

    func loadTasks() async {
        guard !selectedSemesterID.isEmpty else {
            taskState = .empty
            return
        }
        taskState = .loading
        do {
            let values = try await service.tasks(semesterID: selectedSemesterID)
            let hasTeachers = values.contains { course in
                course.tasks.contains { !$0.teachers.isEmpty }
            }
            taskState = hasTeachers ? .loaded(values) : .empty
        } catch {
            taskState = .failed(AppErrorState(message: error.localizedDescription))
        }
    }

    func open(_ target: EvaluationSubmissionTarget) async {
        guard target.canSubmit else { return }
        selectedTarget = target
        questionnaireState = .loading
        optionAnswers = [:]
        textAnswers = [:]
        message = nil
        do {
            let form = try await service.questionnaire(id: target.task.questionnaireID)
            guard selectedTarget?.id == target.id else { return }
            questionnaireState = form.questionnaire.questions.isEmpty
                ? .empty
                : .loaded(form.questionnaire)
            if presetQuestions.isEmpty {
                presetQuestions = form.questionnaire.questions
            }
        } catch {
            guard selectedTarget?.id == target.id else { return }
            questionnaireState = .failed(AppErrorState(message: error.localizedDescription))
        }
    }

    func closeQuestionnaire() {
        selectedTarget = nil
        questionnaireState = .idle
        optionAnswers = [:]
        textAnswers = [:]
        isSubmitting = false
    }

    func choose(optionID: Int, for questionID: String) {
        optionAnswers[questionID] = optionID
    }

    func setText(_ value: String, for questionID: String, maximum: Int?) {
        textAnswers[questionID] = maximum.map {
            String(value.prefix(max($0, 0)))
        } ?? value
    }

    func validationMessage() -> String? {
        guard case let .loaded(questionnaire) = questionnaireState else {
            return "评教问卷尚未加载完成"
        }
        return EvaluationSubmissionLogic.requiredValidationMessage(
            questions: questionnaire.questions,
            optionAnswers: optionAnswers,
            textAnswers: textAnswers
        )
    }

    func applyPreset() {
        guard case let .loaded(questionnaire) = questionnaireState else { return }
        let answers = EvaluationSubmissionLogic.answers(
            applying: preset,
            to: questionnaire.questions
        )
        optionAnswers = answers.options
        textAnswers = answers.text
        message = "已套用预设"
    }

    func submitSelected(anonymous: Bool, applyingPreset: Bool = false) async {
        guard
            let target = selectedTarget,
            case let .loaded(questionnaire) = questionnaireState
        else {
            return
        }
        if applyingPreset {
            applyPreset()
        }
        if let validation = validationMessage() {
            message = validation
            return
        }

        isSubmitting = true
        defer { isSubmitting = false }
        let request = EvaluationSubmissionLogic.buildRequest(
            target: target,
            questionnaire: questionnaire,
            optionAnswers: optionAnswers,
            textAnswers: textAnswers,
            anonymous: anonymous
        )
        do {
            try await checkedSubmit(request)
            closeQuestionnaire()
            await loadTasks()
            message = "提交成功"
        } catch {
            message = error.localizedDescription
        }
    }

    func quickSubmit(_ target: EvaluationSubmissionTarget) async {
        guard target.canSubmit, !isSubmitting, !bulkState.isSubmitting else { return }
        isSubmitting = true
        defer { isSubmitting = false }
        do {
            try await submitWithPreset(target)
            await loadTasks()
            message = "已按预设完成：\(target.teacher.name) · \(target.course.courseName)"
        } catch {
            message = error.localizedDescription
        }
    }

    func submitAllWithPreset() async {
        let submissions = pendingTargets
        guard !submissions.isEmpty else {
            bulkState = .failed("暂无可按预设完成的评教")
            return
        }
        bulkState = .submitting(processed: 0, total: submissions.count)
        var successCount = 0
        var firstError: String?
        for (index, target) in submissions.enumerated() {
            do {
                try await submitWithPreset(target)
                successCount += 1
            } catch {
                if firstError == nil {
                    firstError = error.localizedDescription
                }
            }
            bulkState = .submitting(processed: index + 1, total: submissions.count)
        }
        if let firstError {
            bulkState = .partiallyFailed(
                completed: successCount,
                total: submissions.count,
                firstError: firstError
            )
        } else {
            bulkState = .succeeded(count: successCount)
        }
        await loadTasks()
    }

    func preparePresetQuestions() async {
        if !presetQuestions.isEmpty || isPresetLoading { return }
        if case let .loaded(questionnaire) = questionnaireState {
            presetQuestions = questionnaire.questions
            return
        }
        guard let questionnaireID = targets
            .map(\.task.questionnaireID)
            .first(where: { !$0.isEmpty })
        else {
            return
        }
        isPresetLoading = true
        defer { isPresetLoading = false }
        do {
            let form = try await service.questionnaire(id: questionnaireID)
            presetQuestions = form.questionnaire.questions
        } catch {
            message = error.localizedDescription
        }
    }

    func savePreset(
        optionIndexes: [String: Int],
        textAnswers: [String: String],
        isAnonymous: Bool
    ) {
        let normalized = EvaluationSubmissionLogic.normalizedPreset(
            questions: presetQuestions,
            optionIndexes: optionIndexes,
            textAnswers: textAnswers,
            isAnonymous: isAnonymous
        )
        preset = normalized
        presetStore.save(normalized)
        message = "预设已保存"
    }

    func clearMessage() {
        message = nil
    }

    func clearBulkResult() {
        guard !bulkState.isSubmitting else { return }
        bulkState = .idle
    }

    private func submitWithPreset(_ target: EvaluationSubmissionTarget) async throws {
        let form = try await service.questionnaire(id: target.task.questionnaireID)
        let answers = EvaluationSubmissionLogic.answers(
            applying: preset,
            to: form.questionnaire.questions
        )
        if let validation = EvaluationSubmissionLogic.requiredValidationMessage(
            questions: form.questionnaire.questions,
            optionAnswers: answers.options,
            textAnswers: answers.text
        ) {
            throw EvaluationModelError.server(validation)
        }
        let request = EvaluationSubmissionLogic.buildRequest(
            target: target,
            questionnaire: form.questionnaire,
            optionAnswers: answers.options,
            textAnswers: answers.text,
            anonymous: preset.isAnonymous
        )
        try await checkedSubmit(request)
    }

    private func checkedSubmit(_ request: EvaluationSubmitRequest) async throws {
        let checkMessage = try await service.checkSubmit(request)
        guard checkMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw EvaluationModelError.server(checkMessage)
        }
        try await service.submit(request)
    }
}
