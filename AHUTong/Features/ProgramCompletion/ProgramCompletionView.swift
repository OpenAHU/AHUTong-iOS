import SwiftUI

@MainActor
final class ProgramCompletionViewModel: ObservableObject {
    struct Saved: Codable, Sendable { let value: ProgramCompletion; let updatedAt: Date }
    @Published private(set) var saved: Saved?
    @Published private(set) var isLoading = false
    @Published private(set) var error: String?
    @Published private(set) var profiles: [CampusGradeStudentProfile] = []
    @Published var selectedID = ""
    private let api: any CampusCoreAPI
    private let remote: any ProgramCompletionRemote
    private let cache: UserScopedStore
    private var generation = 0

    init(api: any CampusCoreAPI, userID: String, remote: (any ProgramCompletionRemote)? = nil,
         store: any DataStore = AppPersistence.migratingFileCache()) {
        self.api = api
        self.remote = remote ?? OfficialProgramCompletionRemote(api: api)
        cache = UserScopedStore(store: store, userID: userID)
    }

    func load(demo: Bool, refresh: Bool = false) async {
        generation += 1
        let revision = generation
        isLoading = true; error = nil
        defer { if revision == generation { isLoading = false } }
        if demo {
            if DemoDataState.current == .error { error = "暂时无法连接教务服务"; return }
            if DemoDataState.current == .loading { return }
            saved = Saved(value: Self.demo, updatedAt: DemoDataState.referenceDate)
            return
        }
        if profiles.isEmpty {
            profiles = (try? await JSONStore<[CampusGradeStudentProfile]>(store: cache, key: "program-profiles.v1").load()) ?? []
            if selectedID.isEmpty { selectedID = profiles.first?.id ?? "" }
        }
        if profiles.isEmpty {
            do { profiles = try await api.gradeProfiles(); if selectedID.isEmpty { selectedID = profiles.first?.id ?? "" } }
            catch is CancellationError { return }
            catch { self.error = error.localizedDescription; return }
            try? await JSONStore<[CampusGradeStudentProfile]>(store: cache, key: "program-profiles.v1").save(profiles)
        }
        let selected = selectedID
        let store = JSONStore<Saved>(store: cache, key: "program-completion.v1.\(selected)")
        let cached = try? await store.load()
        guard revision == generation else { return }
        saved = cached
        if !refresh, cached != nil { return }
        do {
            let value = try await remote.load(profileID: selected.isEmpty ? nil : selected)
            try Task.checkCancellation()
            guard revision == generation, selectedID == selected else { return }
            let fresh = Saved(value: value, updatedAt: Date())
            try await store.save(fresh)
            saved = fresh
        } catch is CancellationError {} catch {
            guard revision == generation else { return }
            self.error = cached == nil ? error.localizedDescription : "刷新失败，显示上次同步的数据"
        }
    }

    static let demo = ProgramCompletion(programName: "示例专业人才培养方案（主修）", progress: "34.8%", required: 161, passed: 56, taking: 26.5, unfinished: 105, auditPublished: false, modules: [
        CompletionModule(name: "思想政治理论", required: 18, passed: 8, courses: [
            CompletionCourse(name: "思想道德与法治", code: "GG61014", credits: 3, status: "PASSED", grade: "91", terms: "TERM_1", remark: nil),
            CompletionCourse(name: "马克思主义基本原理", code: "GG61012", credits: 3, status: "TAKING", grade: nil, terms: "TERM_2", remark: nil),
            CompletionCourse(name: "形势与政策", code: "GG61001", credits: 2, status: "UNREPAIRED", grade: nil, terms: nil, remark: nil)
        ], children: [])
    ], outerCourses: [])
}

struct ProgramCompletionView: View {
    @StateObject private var model: ProgramCompletionViewModel
    @State private var unfinishedOnly = false
    init(appModel: AppModel) {
        let userID = if case let .authenticated(user) = appModel.sessionState { user.studentID } else { "guest" }
        _model = StateObject(wrappedValue: ProgramCompletionViewModel(api: appModel.campusAPI, userID: userID))
    }
    var body: some View {
        List {
            if model.profiles.count > 1 {
                Picker("学生档案", selection: $model.selectedID) {
                    ForEach(model.profiles) { Text($0.displayName).tag($0.id) }
                }
            }
            if let saved = model.saved {
                let value = saved.value
                Section {
                    Text(value.programName).font(.headline)
                    LabeledContent(value.progressTitle, value: value.progressText)
                    LabeledContent("要求学分", value: value.required.formatted())
                    LabeledContent("已完成", value: value.passed.formatted())
                    LabeledContent("在修", value: value.taking.formatted())
                    LabeledContent("未完成", value: value.unfinished.formatted())
                } footer: {
                    VStack(alignment: .leading, spacing: 4) {
                        if !value.auditPublished { Text("审核结果尚未发布，以教务系统为准。") }
                        Text("同步于 \(saved.updatedAt.formatted(date: .abbreviated, time: .shortened))")
                        Text("当前支持本科教务培养方案")
                    }
                }
                Toggle("只看未完成", isOn: $unfinishedOnly)
                ForEach(Array(value.modules.enumerated()), id: \.offset) { _, module in
                    Section { CompletionModuleRows(module: module, unfinishedOnly: unfinishedOnly) }
                }
                if !value.outerCourses.isEmpty {
                    Section("计划外课程") { CompletionCourseRows(courses: value.outerCourses, unfinishedOnly: unfinishedOnly) }
                }
            } else if model.isLoading { ProgressView("正在查询培养方案") }
            if let error = model.error {
                Section {
                    Text(error).foregroundStyle(.secondary)
                    Button("重试") { Task { await model.load(demo: AppRuntime.isDemoSession, refresh: true) } }
                }
            }
            if model.saved == nil, !model.isLoading, model.error == nil { Text("暂无培养方案数据") }
        }
        .navigationTitle("培养方案")
        .accessibilityIdentifier("program-completion.screen")
        .refreshable { await model.load(demo: AppRuntime.isDemoSession, refresh: true) }
        .task { await model.load(demo: AppRuntime.isDemoSession) }
        .onChange(of: model.selectedID) { old, _ in
            if !old.isEmpty { Task { await model.load(demo: AppRuntime.isDemoSession) } }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("刷新", systemImage: "arrow.clockwise") { Task { await model.load(demo: AppRuntime.isDemoSession, refresh: true) } }
                    .disabled(model.isLoading)
            }
        }
    }
}

private struct CompletionModuleRows: View {
    let module: CompletionModule
    let unfinishedOnly: Bool
    var body: some View {
        DisclosureGroup {
            CompletionCourseRows(courses: module.courses, unfinishedOnly: unfinishedOnly)
            ForEach(Array(module.children.enumerated()), id: \.offset) { _, child in
                CompletionModuleRows(module: child, unfinishedOnly: unfinishedOnly)
            }
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text(module.name)
                Text("已完成 \(module.passed.formatted()) / \(module.required.formatted()) 学分")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

private struct CompletionCourseRows: View {
    let courses: [CompletionCourse]
    let unfinishedOnly: Bool
    var body: some View {
        ForEach(Array(courses.enumerated()).filter { !unfinishedOnly || !$0.element.completed }, id: \.offset) { _, course in
            VStack(alignment: .leading, spacing: 4) {
                HStack { Text(course.name); Spacer(); Text(course.statusText).font(.caption).foregroundStyle(.secondary) }
                Text("\(course.credits.formatted()) 学分" + (course.grade.map { " · 成绩 \($0)" } ?? ""))
                    .font(.caption).foregroundStyle(.secondary)
                if let remark = course.remark, !remark.isEmpty { Text(remark).font(.caption).foregroundStyle(.secondary) }
            }
            .accessibilityElement(children: .combine)
        }
    }
}
