import SwiftUI

private enum EvaluationConfirmation: Identifiable {
    case selected(anonymous: Bool, appliesPreset: Bool)
    case quick(EvaluationSubmissionTarget)
    case bulk(Int)

    var id: String {
        switch self {
        case let .selected(anonymous, appliesPreset):
            "selected-\(anonymous)-\(appliesPreset)"
        case let .quick(target):
            "quick-\(target.id)"
        case let .bulk(count):
            "bulk-\(count)"
        }
    }

    var title: String {
        switch self {
        case .selected:
            "确认提交评教"
        case .quick:
            "确认按预设完成"
        case .bulk:
            "确认批量评教"
        }
    }

    var detail: String {
        switch self {
        case let .selected(anonymous, appliesPreset):
            let mode = appliesPreset ? "当前预设" : "当前填写内容"
            return "将按\(mode)\(anonymous ? "匿名" : "")提交，提交后通常不能撤回。"
        case let .quick(target):
            return "将按当前预设提交「\(target.course.courseName) · \(target.teacher.name)」，提交后通常不能撤回。"
        case let .bulk(count):
            return "将按当前预设提交 \(count) 项评教，提交后通常不能撤回。"
        }
    }
}

struct EvaluationView: View {
    @Environment(\.colorScheme) private var colorScheme
    @StateObject private var model: EvaluationViewModel
    @State private var showsPreset = false
    @State private var confirmation: EvaluationConfirmation?
    @State private var localMessage: String?

    init(appModel: AppModel) {
        let service: any EvaluationServicing
        if AppRuntime.isDemoSession {
            service = DemoEvaluationService()
        } else {
            let client = CampusAuthenticatedClient(campusAPI: appModel.campusAPI)
            service = EvaluationRemoteService(client: client)
        }
        let userID = if case let .authenticated(user) = appModel.sessionState {
            user.studentID
        } else {
            "guest"
        }
        _model = StateObject(
            wrappedValue: EvaluationViewModel(
                service: service,
                presetStore: EvaluationPresetStore(userID: userID)
            )
        )
    }

    init(service: any EvaluationServicing, presetStore: EvaluationPresetStore? = nil) {
        _model = StateObject(
            wrappedValue: EvaluationViewModel(
                service: service,
                presetStore: presetStore
            )
        )
    }

    var body: some View {
        AndroidScreen {
            if model.selectedTarget == nil {
                listScreen
            } else {
                questionnaireScreen
            }
        }
        .task {
            if case .idle = model.taskState {
                await model.load()
            }
        }
        .sheet(isPresented: $showsPreset) {
            EvaluationPresetSheet(model: model)
        }
        .alert(item: $confirmation) { value in
            Alert(
                title: Text(value.title),
                message: Text(value.detail),
                primaryButton: .destructive(Text("确认提交")) {
                    perform(value)
                },
                secondaryButton: .cancel(Text("取消"))
            )
        }
        .alert(
            "教评",
            isPresented: Binding(
                get: { localMessage != nil || model.message != nil },
                set: { visible in
                    if !visible {
                        localMessage = nil
                        model.clearMessage()
                    }
                }
            )
        ) {
            Button("好") {
                localMessage = nil
                model.clearMessage()
            }
        } message: {
            Text(localMessage ?? model.message ?? "")
        }
        .accessibilityIdentifier("evaluation.screen")
    }

    private var listScreen: some View {
        ScrollView {
            VStack(spacing: 12) {
                listHeader
                bulkButton
                bulkStatus
                listContent
            }
            .padding(.bottom, 96)
        }
        .scrollIndicators(.hidden)
        .refreshable { await model.loadTasks() }
    }

    private var listHeader: some View {
        AndroidHeader(title: "教评", large: true) {
            HStack(spacing: 2) {
                Menu {
                    ForEach(model.semesters) { semester in
                        Button {
                            Task { await model.selectSemester(semester) }
                        } label: {
                            if semester.id == model.selectedSemesterID {
                                Label(semester.name, systemImage: "checkmark")
                            } else {
                                Text(semester.name)
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(selectedSemesterName)
                            .lineLimit(1)
                        Image(systemName: "chevron.down")
                            .font(.caption2.bold())
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AndroidParityPalette.systemTheme)
                    .padding(.horizontal, 10)
                    .frame(height: 44)
                    .contentShape(Rectangle())
                }
                .disabled(model.semesters.isEmpty)
                .accessibilityLabel("选择评教学期")

                AndroidIconButton(
                    systemName: "gearshape.fill",
                    accessibilityLabel: "评教预设"
                ) {
                    showsPreset = true
                    Task { await model.preparePresetQuestions() }
                }
            }
        }
    }

    private var bulkButton: some View {
        Button {
            confirmation = .bulk(model.pendingTargets.count)
        } label: {
            HStack(spacing: 8) {
                if model.bulkState.isSubmitting {
                    ProgressView()
                        .controlSize(.small)
                }
                Text(bulkButtonTitle)
                    .font(.headline)
            }
            .frame(maxWidth: .infinity)
            .frame(minHeight: 46)
        }
        .buttonStyle(.bordered)
        .tint(AndroidParityPalette.systemTheme)
        .disabled(
            model.pendingTargets.isEmpty
                || model.taskState.isLoading
                || model.isSubmitting
                || model.bulkState.isSubmitting
        )
        .padding(.horizontal, 16)
        .accessibilityIdentifier("evaluation.bulk-submit")
    }

    @ViewBuilder
    private var bulkStatus: some View {
        if let message = model.bulkState.message {
            HStack(alignment: .top, spacing: 8) {
                Image(
                    systemName: bulkSucceeded
                        ? "checkmark.circle.fill"
                        : "exclamationmark.triangle.fill"
                )
                Text(message)
                    .font(.subheadline)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button {
                    model.clearBulkResult()
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.plain)
                .accessibilityLabel("关闭批量评教结果")
            }
            .foregroundStyle(bulkSucceeded ? AndroidParityPalette.success : AndroidParityPalette.error)
            .padding(.horizontal, 18)
        }
    }

    @ViewBuilder
    private var listContent: some View {
        switch model.taskState {
        case .idle, .loading:
            ProgressView("正在加载待评课程…")
                .frame(maxWidth: .infinity, minHeight: 260)
        case .empty:
            emptyState(
                title: "暂无待评教课程",
                detail: "当前学期没有需要完成的教学评价。"
            )
        case let .failed(error):
            errorState(error.message) {
                Task { await model.load() }
            }
        case .loaded:
            LazyVStack(spacing: 12) {
                ForEach(model.targets) { target in
                    targetCard(target)
                }
            }
            .padding(.horizontal, 16)
        }
    }

    private func targetCard(_ target: EvaluationSubmissionTarget) -> some View {
        AndroidCard(radius: 16) {
            VStack(alignment: .leading, spacing: 10) {
                Button {
                    Task { await model.open(target) }
                } label: {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .firstTextBaseline, spacing: 12) {
                            Text(target.course.courseName)
                                .font(.headline)
                                .foregroundStyle(.primary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Text(statusTitle(target))
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(statusColor(target))
                        }
                        Label(target.teacher.name, systemImage: "person")
                            .font(.subheadline)
                            .foregroundStyle(AndroidParityPalette.secondaryText(colorScheme))
                        Text("\(target.course.lessonName) · \(target.task.questionnaireName)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(!target.canSubmit)

                HStack {
                    Spacer()
                    Button("按预设完成") {
                        confirmation = .quick(target)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .tint(AndroidParityPalette.systemTheme)
                    .disabled(
                        !target.canSubmit
                            || model.isSubmitting
                            || model.bulkState.isSubmitting
                    )
                }
            }
            .padding(16)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("evaluation.target.\(target.id)")
    }

    private var questionnaireScreen: some View {
        VStack(spacing: 0) {
            questionnaireHeader
            Divider()
            questionnaireContent
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            submissionBar
        }
    }

    private var questionnaireHeader: some View {
        HStack(spacing: 8) {
            AndroidIconButton(systemName: "arrow.left", accessibilityLabel: "返回教评列表") {
                model.closeQuestionnaire()
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(model.selectedTarget?.course.courseName ?? "教评")
                    .font(.headline)
                    .lineLimit(1)
                Text(questionnaireSubtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            AndroidIconButton(
                systemName: "gearshape.fill",
                accessibilityLabel: "评教预设"
            ) {
                showsPreset = true
                Task { await model.preparePresetQuestions() }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(AndroidParityPalette.background(colorScheme))
    }

    @ViewBuilder
    private var questionnaireContent: some View {
        switch model.questionnaireState {
        case .idle, .loading:
            ProgressView("正在加载评教问卷…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .empty:
            emptyState(
                title: "问卷暂无题目",
                detail: "该评教问卷没有可填写内容。"
            )
        case let .failed(error):
            errorState(error.message) {
                guard let target = model.selectedTarget else { return }
                Task { await model.open(target) }
            }
        case let .loaded(questionnaire):
            ScrollView {
                VStack(spacing: 16) {
                    HStack(spacing: 12) {
                        Button("套用预设") {
                            model.applyPreset()
                        }
                        .buttonStyle(.bordered)
                        .frame(maxWidth: .infinity)

                        Button("预设提交") {
                            confirmation = .selected(
                                anonymous: model.preset.isAnonymous,
                                appliesPreset: true
                            )
                        }
                        .buttonStyle(.borderedProminent)
                        .frame(maxWidth: .infinity)
                    }
                    .tint(AndroidParityPalette.systemTheme)

                    ForEach(questionnaire.questions) { question in
                        questionCard(question)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 96)
            }
            .scrollIndicators(.hidden)
        }
    }

    private func questionCard(_ question: EvaluationQuestion) -> some View {
        AndroidCard(radius: 16) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("\(question.index).")
                        .font(.headline)
                    Text(question.attribute.title)
                        .font(.headline)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if question.attribute.isRequired {
                        Text("*")
                            .foregroundStyle(AndroidParityPalette.error)
                            .accessibilityLabel("必填")
                    }
                }

                switch question.attribute.typeID {
                case 1:
                    VStack(spacing: 8) {
                        ForEach(question.options) { option in
                            Button {
                                model.choose(optionID: option.id, for: question.id)
                            } label: {
                                HStack(spacing: 12) {
                                    Image(
                                        systemName: model.optionAnswers[question.id] == option.id
                                            ? "largecircle.fill.circle"
                                            : "circle"
                                    )
                                    .foregroundStyle(AndroidParityPalette.systemTheme)
                                    Text(option.value)
                                        .foregroundStyle(.primary)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .padding(.horizontal, 12)
                                .frame(minHeight: 44)
                                .background(
                                    model.optionAnswers[question.id] == option.id
                                        ? AndroidParityPalette.primaryContainer(colorScheme)
                                        : AndroidParityPalette.background(colorScheme),
                                    in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                                )
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                case 4:
                    TextEditor(
                        text: Binding(
                            get: { model.textAnswers[question.id] ?? "" },
                            set: {
                                model.setText(
                                    $0,
                                    for: question.id,
                                    maximum: question.setting.maximumWords
                                )
                            }
                        )
                    )
                    .frame(minHeight: 112)
                    .padding(8)
                    .scrollContentBackground(.hidden)
                    .background(
                        AndroidParityPalette.background(colorScheme),
                        in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                    )
                    .overlay(alignment: .bottomTrailing) {
                        if let maximum = question.setting.maximumWords {
                            Text("\((model.textAnswers[question.id] ?? "").count)/\(maximum)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .padding(8)
                        }
                    }
                default:
                    Text("当前版本暂不支持此题型")
                        .font(.subheadline)
                        .foregroundStyle(AndroidParityPalette.error)
                }
            }
            .padding(16)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("evaluation.question.\(question.id)")
    }

    private var submissionBar: some View {
        HStack(spacing: 10) {
            Button("取消") {
                model.closeQuestionnaire()
            }
            .buttonStyle(.bordered)

            Button("提交") {
                requestSelectedConfirmation(anonymous: false)
            }
            .buttonStyle(.borderedProminent)

            Button("匿名") {
                requestSelectedConfirmation(anonymous: true)
            }
            .buttonStyle(.borderedProminent)
        }
        .tint(AndroidParityPalette.systemTheme)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.regularMaterial)
        .disabled(model.isSubmitting || model.questionnaireState.isLoading)
        .overlay {
            if model.isSubmitting {
                ProgressView()
                    .padding(8)
                    .background(.regularMaterial, in: Capsule())
            }
        }
        .accessibilityIdentifier("evaluation.submission-bar")
    }

    private func requestSelectedConfirmation(anonymous: Bool) {
        if let validation = model.validationMessage() {
            localMessage = validation
        } else {
            confirmation = .selected(anonymous: anonymous, appliesPreset: false)
        }
    }

    private func perform(_ value: EvaluationConfirmation) {
        switch value {
        case let .selected(anonymous, appliesPreset):
            Task {
                await model.submitSelected(
                    anonymous: anonymous,
                    applyingPreset: appliesPreset
                )
            }
        case let .quick(target):
            Task { await model.quickSubmit(target) }
        case .bulk:
            Task { await model.submitAllWithPreset() }
        }
    }

    private var selectedSemesterName: String {
        model.semesters.first { $0.id == model.selectedSemesterID }?.name ?? "选择学期"
    }

    private var questionnaireSubtitle: String {
        guard let target = model.selectedTarget else { return "" }
        return "\(target.teacher.name) · \(target.course.lessonName)"
    }

    private var bulkButtonTitle: String {
        if case let .submitting(processed, total) = model.bulkState {
            return "正在提交 \(processed)/\(total)"
        }
        return "按预设完成全部"
    }

    private var bulkSucceeded: Bool {
        if case .succeeded = model.bulkState { return true }
        return false
    }

    private func statusTitle(_ target: EvaluationSubmissionTarget) -> String {
        if !target.teacher.needsReview { return "已评" }
        if !target.task.isOpen { return "未开始" }
        return "待评"
    }

    private func statusColor(_ target: EvaluationSubmissionTarget) -> Color {
        if !target.teacher.needsReview { return .secondary }
        if !target.task.isOpen { return AndroidParityPalette.success }
        return AndroidParityPalette.systemTheme
    }

    private func emptyState(title: String, detail: String) -> some View {
        ContentUnavailableView(
            title,
            systemImage: "checkmark.seal",
            description: Text(detail)
        )
        .frame(maxWidth: .infinity, minHeight: 280)
    }

    private func errorState(_ message: String, retry: @escaping () -> Void) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.largeTitle)
                .foregroundStyle(AndroidParityPalette.error)
            Text(message)
                .multilineTextAlignment(.center)
                .foregroundStyle(AndroidParityPalette.error)
            Button("重试", action: retry)
                .buttonStyle(.borderedProminent)
                .tint(AndroidParityPalette.systemTheme)
        }
        .padding(24)
        .frame(maxWidth: .infinity, minHeight: 280)
    }
}

private struct EvaluationPresetSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject var model: EvaluationViewModel
    @State private var optionIndexes: [String: Int]
    @State private var textAnswers: [String: String]
    @State private var isAnonymous: Bool

    init(model: EvaluationViewModel) {
        self.model = model
        _optionIndexes = State(initialValue: model.preset.optionIndexes)
        _textAnswers = State(initialValue: model.preset.textAnswers)
        _isAnonymous = State(initialValue: model.preset.isAnonymous)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AndroidParityPalette.background(colorScheme).ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 14) {
                        Toggle("匿名提交", isOn: $isAnonymous)
                            .font(.headline)
                            .padding(16)
                            .background(
                                AndroidParityPalette.surface(colorScheme),
                                in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                            )

                        if model.isPresetLoading {
                            ProgressView("正在加载预设题目…")
                                .frame(maxWidth: .infinity, minHeight: 220)
                        } else if model.presetQuestions.isEmpty {
                            ContentUnavailableView(
                                "暂无可编辑题目",
                                systemImage: "list.bullet.clipboard",
                                description: Text("加载待评课程后即可设置评教预设。")
                            )
                            .frame(minHeight: 260)
                        } else {
                            ForEach(model.presetQuestions) { question in
                                presetEditor(question)
                            }
                        }
                    }
                    .padding(16)
                }
            }
            .navigationTitle("评教预设")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        model.savePreset(
                            optionIndexes: optionIndexes,
                            textAnswers: textAnswers,
                            isAnonymous: isAnonymous
                        )
                        dismiss()
                    }
                    .disabled(model.presetQuestions.isEmpty)
                }
            }
            .task { await model.preparePresetQuestions() }
            .onChange(of: model.presetQuestions) { _, questions in
                guard !questions.isEmpty else { return }
                let resolved = EvaluationSubmissionLogic.normalizedPreset(
                    questions: questions,
                    optionIndexes: optionIndexes,
                    textAnswers: textAnswers,
                    isAnonymous: isAnonymous
                )
                optionIndexes = resolved.optionIndexes
                for question in questions where question.attribute.typeID == 4 {
                    if textAnswers[question.id] == nil {
                        textAnswers[question.id] = EvaluationPreset.defaultComment
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .accessibilityIdentifier("evaluation.preset-sheet")
    }

    private func presetEditor(_ question: EvaluationQuestion) -> some View {
        AndroidCard(radius: 16) {
            VStack(alignment: .leading, spacing: 12) {
                Text(question.attribute.title)
                    .font(.headline)
                    .frame(maxWidth: .infinity, alignment: .leading)

                switch question.attribute.typeID {
                case 1:
                    Picker(
                        "预设选项",
                        selection: Binding(
                            get: { optionIndexes[question.id] ?? 0 },
                            set: { optionIndexes[question.id] = $0 }
                        )
                    ) {
                        ForEach(Array(question.options.enumerated()), id: \.offset) { index, option in
                            Text(option.value).tag(index)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(maxWidth: .infinity, alignment: .leading)
                case 4:
                    TextEditor(
                        text: Binding(
                            get: {
                                textAnswers[question.id] ?? EvaluationPreset.defaultComment
                            },
                            set: { value in
                                if let maximum = question.setting.maximumWords {
                                    textAnswers[question.id] = String(value.prefix(max(maximum, 0)))
                                } else {
                                    textAnswers[question.id] = value
                                }
                            }
                        )
                    )
                    .frame(minHeight: 90)
                    .padding(8)
                    .scrollContentBackground(.hidden)
                    .background(
                        AndroidParityPalette.background(colorScheme),
                        in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                    )
                default:
                    Text("此题型不可设为预设")
                        .foregroundStyle(.secondary)
                }
            }
            .padding(16)
        }
    }
}
