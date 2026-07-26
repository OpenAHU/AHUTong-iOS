import SwiftUI

@MainActor
final class GradeViewModel: ObservableObject {
    @Published private(set) var state: LoadableState<CampusGradeReport> = .idle
    @Published private(set) var profiles: [CampusGradeStudentProfile] = []
    @Published private(set) var selectedProfileID = ""
    @Published private(set) var rank: CampusGradeRankInfo?
    @Published private(set) var profileErrors: [String: String] = [:]
    private let api: any CampusCoreAPI
    private let cache: JSONStore<GradeCache>
    private var reports: [String: CampusGradeReport] = [:]
    private var ranks: [String: CampusGradeRankInfo] = [:]

    init(
        api: any CampusCoreAPI,
        userID: String,
        store: any DataStore = AppPersistence.migratingFileCache()
    ) {
        self.api = api
        cache = JSONStore(
            store: UserScopedStore(store: store, userID: userID),
            key: "grades.v2"
        )
    }

    func load(demo: Bool = false) async {
        state = .loading
        profileErrors = [:]
        if demo {
            switch DemoDataState.current {
            case .normal:
                let custom = DebugRuntimeSettings.decode("grade", as: CampusGradeReport.self)
                    ?? (try? CampusGradeParser().parse(Data(DebugRuntimeSettings.endpointJSON("grade").utf8)))
                let report = custom ?? Self.demoReport
                profiles = Self.demoProfiles
                selectedProfileID = Self.demoProfiles[0].id
                reports = [selectedProfileID: report]
                rank = Self.demoRank
                state = report.grades.isEmpty ? .empty : .loaded(report)
            case .loading: return
            case .empty: state = .empty
            case .error: state = .failed(AppErrorState(message: "Mock 场景：接口返回 500"))
            }
            return
        }
        let cached = try? await cache.load()
        if let cached { apply(cached) }
        do {
            var loadedProfiles = try await api.gradeProfiles()
            if loadedProfiles.isEmpty {
                loadedProfiles = [CampusGradeStudentProfile(id: "", trainingType: "主修", department: "", major: "")]
            }
            var loadedReports: [String: CampusGradeReport] = [:]
            var loadedRanks: [String: CampusGradeRankInfo] = [:]
            var loadedErrors: [String: String] = [:]
            var firstError: Error?
            for profile in loadedProfiles {
                do {
                    let report = profile.id.isEmpty
                        ? try await api.grades()
                        : try await api.grades(studentID: profile.id)
                    loadedReports[profile.id] = report
                    if !profile.id.isEmpty,
                       let value = try? await api.gradeRank(studentID: profile.id) {
                        loadedRanks[profile.id] = value
                    }
                } catch {
                    firstError = firstError ?? error
                    loadedErrors[profile.id] = error.localizedDescription
                }
            }
            guard !loadedReports.isEmpty else {
                throw firstError ?? CampusCoreError.invalidResponse
            }
            let fresh = GradeCache(profiles: loadedProfiles, reports: loadedReports, ranks: loadedRanks)
            try await cache.save(fresh)
            profileErrors = loadedErrors
            apply(fresh)
        } catch {
            if cached == nil { state = .failed(AppErrorState(message: error.localizedDescription)) }
        }
    }

    func selectProfile(_ profile: CampusGradeStudentProfile) {
        selectedProfileID = profile.id
        rank = ranks[profile.id]
        guard let report = reports[profile.id] else {
            if let message = profileErrors[profile.id] {
                state = .failed(AppErrorState(message: "「\(profile.displayName)」加载失败：\(message)"))
            } else {
                state = .empty
            }
            return
        }
        state = report.grades.isEmpty ? .empty : .loaded(report)
    }

    private func apply(_ value: GradeCache) {
        profiles = value.profiles
        reports = value.reports
        ranks = value.ranks
        let profileID = value.profiles.first(where: {
            $0.id == selectedProfileID && value.reports[$0.id] != nil
        })?.id
            ?? value.profiles.first(where: { value.reports[$0.id] != nil })?.id
            ?? value.reports.keys.sorted().first
            ?? ""
        selectedProfileID = profileID
        rank = value.ranks[profileID]
        if let report = value.reports[profileID] {
            state = report.grades.isEmpty ? .empty : .loaded(report)
        }
    }

    private struct GradeCache: Codable, Sendable {
        let profiles: [CampusGradeStudentProfile]
        let reports: [String: CampusGradeReport]
        let ranks: [String: CampusGradeRankInfo]
    }

    static let demoProfiles = [
        CampusGradeStudentProfile(id: "demo-main", trainingType: "主修", department: "计算机科学与技术学院", major: "计算机科学与技术"),
        CampusGradeStudentProfile(id: "demo-minor", trainingType: "微专业", department: "创新学院", major: "人工智能")
    ]

    static let demoRank = CampusGradeRankInfo(
        gpa: 3.78,
        majorRank: 8,
        majorHeadCount: 120,
        gpaSemesterSubs: [CampusGradeSemesterRank(gpa: 3.8, semesterId: 202420252, majorRank: 5)],
        updatedDateTimeStr: "2026-07-15 12:00"
    )

    static let demoReport = CampusGradeReport(
        grades: [
            CampusGrade(courseName: "数据结构", courseCode: "COMP2301", credit: 4, score: "96", gradePoint: 4, courseProperty: "专业必修", semesterID: 202320242, semesterName: "2023-2024-2"),
            CampusGrade(courseName: "概率论与数理统计", courseCode: "MATH2202", credit: 3, score: "91", gradePoint: 3.7, courseProperty: "学科基础", semesterID: 202320242, semesterName: "2023-2024-2"),
            CampusGrade(courseName: "大学英语 IV", courseCode: "ENGL2002", credit: 2, score: "86", gradePoint: 3.3, courseProperty: "公共必修", semesterID: 202320242, semesterName: "2023-2024-2"),
            CampusGrade(courseName: "数据库系统", courseCode: "COMP3301", credit: 3, score: "93", gradePoint: 3.8, courseProperty: "专业必修", semesterID: 202420251, semesterName: "2024-2025-1"),
            CampusGrade(courseName: "计算机网络", courseCode: "COMP3302", credit: 3, score: "88", gradePoint: 3.5, courseProperty: "专业必修", semesterID: 202420251, semesterName: "2024-2025-1"),
            CampusGrade(courseName: "软件工程", courseCode: "COMP3303", credit: 2.5, score: "优秀", gradePoint: 4, courseProperty: "专业必修", semesterID: 202420251, semesterName: "2024-2025-1"),
            CampusGrade(courseName: "大学体育", courseCode: "PE3001", credit: 1, score: "良好", gradePoint: 3, courseProperty: "公共必修", semesterID: 202420251, semesterName: "2024-2025-1"),
            CampusGrade(courseName: "移动应用开发", courseCode: "COMP3401", credit: 3, score: "97", gradePoint: 4, courseProperty: "专业选修", semesterID: 202420252, semesterName: "2024-2025-2"),
            CampusGrade(courseName: "操作系统", courseCode: "COMP3402", credit: 3.5, score: "90", gradePoint: 3.6, courseProperty: "专业必修", semesterID: 202420252, semesterName: "2024-2025-2"),
            CampusGrade(courseName: "软件工程实践", courseCode: "COMP3403", credit: 2, score: "95", gradePoint: 3.9, courseProperty: "实践教学", semesterID: 202420252, semesterName: "2024-2025-2")
        ],
        gradePointAverage: nil,
        rank: nil,
        studentProfiles: ["计算机科学与技术"]
    )
}

struct GradeView: View {
    @Environment(\.colorScheme) private var colorScheme
    @StateObject private var model: GradeViewModel
    @State private var query = ""
    @State private var selectedSemester = AppRuntime.isDemoSession
        ? (
            GradeViewModel.demoReport.grades.max(by: {
                ($0.semesterID ?? 0) < ($1.semesterID ?? 0)
            })?.semesterName ?? GradeView.currentSemesterName
        )
        : GradeView.currentSemesterName
    @State private var isSearching = false
    @State private var showsSemesterMenu = false
    private let appModel: AppModel

    init(appModel: AppModel) {
        self.appModel = appModel
        let userID = if case let .authenticated(user) = appModel.sessionState { user.studentID } else { "demo" }
        _model = StateObject(wrappedValue: GradeViewModel(api: appModel.campusAPI, userID: userID))
    }

    var body: some View {
        AndroidScreen {
            ScrollView {
                VStack(spacing: 24) {
                    header
                    if !isSearching { profileSelector }
                    if case let .loaded(report) = model.state {
                        if !isSearching {
                            semesterSelector(report)
                            summary(report)
                        }
                        gradeContent(report)
                    } else {
                        stateView
                    }
                }
                .padding(.bottom, 32)
            }
            .scrollIndicators(.hidden)
        }
        .task { await model.load(demo: AppRuntime.isDemoSession) }
        .refreshable { await model.load(demo: AppRuntime.isDemoSession) }
        .accessibilityIdentifier("grades.screen")
    }

    @ViewBuilder
    private var profileSelector: some View {
        if model.profiles.count > 1 {
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(model.profiles) { profile in
                        Button(profile.displayName) { model.selectProfile(profile) }
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(model.selectedProfileID == profile.id ? Color.white : AndroidParityPalette.systemTheme)
                            .padding(.horizontal, 14)
                            .frame(height: 38)
                            .background(
                                model.selectedProfileID == profile.id ? AndroidParityPalette.systemTheme : AndroidParityPalette.surface(colorScheme),
                                in: Capsule()
                            )
                    }
                }
                .padding(.horizontal, 16)
            }
            .scrollIndicators(.hidden)
            .accessibilityIdentifier("grades.profile-selector")
        }
    }

    @ViewBuilder
    private var header: some View {
        if isSearching {
            HStack(spacing: 8) {
                AndroidSearchField(text: $query, prompt: "搜索课程")
                AndroidIconButton(systemName: "xmark", accessibilityLabel: "关闭搜索") {
                    isSearching = false
                    query = ""
                }
            }
            .padding(.horizontal, 16).padding(.top, 24)
        } else {
            AndroidHeader(title: "成绩单", large: true) {
                HStack(spacing: 0) {
                    AndroidIconButton(systemName: "arrow.clockwise", accessibilityLabel: "刷新成绩") { Task { await model.load(demo: AppRuntime.isDemoSession) } }
                    AndroidIconButton(systemName: "magnifyingglass", accessibilityLabel: "搜索成绩") { isSearching = true }
                }
                .background(AndroidParityPalette.surface(colorScheme), in: Capsule())
            }
        }
    }

    private func semesterSelector(_ report: CampusGradeReport) -> some View {
        let semesters = [Self.currentSemesterName] + report.grades.map(\.semesterName).filter { !$0.isEmpty && $0 != Self.currentSemesterName }
        let unique = semesters.reduce(into: [String]()) { values, value in if !values.contains(value) { values.append(value) } }
        return Button { showsSemesterMenu.toggle() } label: {
            HStack {
                Text(displaySemester(selectedSemester)).font(.title3)
                Spacer()
                Image(systemName: "chevron.down").font(.caption.bold())
            }
            .padding(.horizontal, 16).frame(height: 56)
            .overlay(Capsule().stroke(.secondary.opacity(0.55), lineWidth: 1.5))
            .overlay(alignment: .topLeading) {
                Text("选择学期").font(.caption).foregroundStyle(.secondary)
                    .padding(.horizontal, 5).background(AndroidParityPalette.background(colorScheme))
                    .offset(x: 12, y: -8)
            }
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 16)
        .confirmationDialog("选择学期", isPresented: $showsSemesterMenu) {
            ForEach(unique, id: \.self) { semester in
                Button(displaySemester(semester)) { selectedSemester = semester }
            }
        }
        .accessibilityIdentifier("grades.semester-filter")
    }

    private func summary(_ report: CampusGradeReport) -> some View {
        let selected = report.grades.filter { $0.semesterName == selectedSemester }
        let semesterGPA = weightedGPA(selected)
        let rank = model.rank
        let cohort = rank?.majorHeadCount.map(String.init) ?? "暂无"
        let semesterID = selected.first?.semesterID
        return VStack(spacing: 14) {
            metric("本学期平均绩点", semesterGPA.map { String(format: "%.2f", $0) } ?? "暂无")
            metric("全程平均绩点", (rank?.gpa ?? report.gradePointAverage).map { String(format: "%.2f", $0) } ?? "暂无")
            metric("全程专业排名", "\(rank?.majorRank.map(String.init) ?? "暂无")/\(cohort)")
            metric("该学期专业排名", "\(rank?.semesterRank(for: semesterID).map(String.init) ?? "暂无")/\(cohort)")
            metric("最后更新时间", rank?.updatedDateTimeStr.flatMap { $0.isEmpty ? nil : $0 } ?? "暂无")
        }
        .padding(.horizontal, 24)
    }

    private func metric(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title).font(.headline)
            Spacer()
            Text(value).font(.headline)
        }
    }

    @ViewBuilder
    private func gradeContent(_ report: CampusGradeReport) -> some View {
        let grades = isSearching ? searchResults(report.grades) : report.grades.filter { $0.semesterName == selectedSemester }
        if grades.isEmpty {
            Text(isSearching && !query.isEmpty ? "未找到包含「\(query)」的成绩" : "该学期目前没有任何成绩")
                .font(.title3).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading).padding(24)
        } else {
            LazyVStack(spacing: 2) {
                ForEach(grades) { grade in gradeCard(grade) }
            }
            .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
            .padding(.horizontal, 16)
        }
    }

    private func gradeCard(_ grade: CampusGrade) -> some View {
        let needsEvaluation = GradeEvaluationGate.isRequired(grade.score)
            || GradeEvaluationGate.isRequired(grade.detail)
        let displayDetail = GradeEvaluationGate.displayText(grade.detail)
        return VStack(alignment: .leading, spacing: 8) {
            Text(grade.courseName).font(.headline.bold())
            if needsEvaluation {
                HStack(spacing: 4) {
                    Text("成绩:")
                    NavigationLink {
                        EvaluationView(appModel: appModel).androidDetailScreen()
                    } label: {
                        Text(GradeEvaluationGate.message)
                            .fontWeight(.semibold)
                            .foregroundStyle(AndroidParityPalette.systemTheme)
                    }
                    .buttonStyle(.plain)
                    Text("  绩点: \(grade.gradePoint?.formatted() ?? "")    学分: \(grade.credit?.formatted() ?? "")")
                }
                .font(.body)
                .accessibilityIdentifier("grades.evaluation-gate")
            } else {
                Text(
                    "成绩: \(GradeEvaluationGate.displayText(grade.score))"
                        + "    绩点: \(grade.gradePoint?.formatted() ?? "")"
                        + "    学分: \(grade.credit?.formatted() ?? "")"
                )
                .font(.body)
                .foregroundStyle(AndroidParityPalette.secondaryText(colorScheme))
            }
            Text("\(grade.courseProperty) (\(grade.courseCode))").font(.subheadline).foregroundStyle(.secondary)
            if !needsEvaluation, !displayDetail.isEmpty {
                Text(displayDetail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 24).padding(.vertical, 16)
        .background(AndroidParityPalette.surface(colorScheme))
    }

    private func weightedGPA(_ grades: [CampusGrade]) -> Double? {
        let valid = grades.compactMap { grade -> (Double, Double)? in
            guard let credit = grade.credit, let point = grade.gradePoint else { return nil }
            return (credit, point)
        }
        let credits = valid.reduce(0) { $0 + $1.0 }
        guard credits > 0 else { return nil }
        return valid.reduce(0) { $0 + $1.0 * $1.1 } / credits
    }

    private func searchResults(_ grades: [CampusGrade]) -> [CampusGrade] {
        let normalized = query.filter { !$0.isWhitespace }
        guard !normalized.isEmpty else { return [] }
        return grades.filter {
            $0.courseName.localizedCaseInsensitiveContains(normalized)
                || $0.courseCode.localizedCaseInsensitiveContains(normalized)
                || $0.courseProperty.localizedCaseInsensitiveContains(normalized)
        }
    }

    private func displaySemester(_ value: String) -> String {
        let parts = value.split(separator: "-")
        guard parts.count >= 3 else { return value }
        return "\(parts[0])-\(parts[1]) 第\(parts[2])学期"
    }

    @ViewBuilder
    private var stateView: some View {
        switch model.state {
        case .idle, .loading:
            ProgressView().frame(maxWidth: .infinity, minHeight: 320)
        case .empty:
            Text("该学期目前没有任何成绩").font(.title3).foregroundStyle(.secondary).padding(24)
        case let .failed(error):
            VStack(spacing: 20) {
                Text(error.message).foregroundStyle(.red).multilineTextAlignment(.center)
                Button("重试") { Task { await model.load() } }.buttonStyle(.borderedProminent)
            }.padding(24)
        case .loaded:
            EmptyView()
        }
    }

    private static var currentSemesterName: String {
        let calendar = Calendar(identifier: .gregorian)
        let now = Date()
        let year = calendar.component(.year, from: now)
        let month = calendar.component(.month, from: now)
        return month >= 8 ? "\(year)-\(year + 1)-1" : "\(year - 1)-\(year)-2"
    }
}
