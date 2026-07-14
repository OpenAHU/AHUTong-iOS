import SwiftUI

@MainActor
final class GradeViewModel: ObservableObject {
    @Published private(set) var state: LoadableState<CampusGradeReport> = .idle
    private let api: any CampusCoreAPI

    init(api: any CampusCoreAPI) { self.api = api }

    func load(demo: Bool = false) async {
        state = .loading
        if demo {
            state = .loaded(Self.demoReport)
            return
        }
        do {
            let report = try await api.grades()
            state = report.grades.isEmpty ? .empty : .loaded(report)
        } catch {
            state = .failed(AppErrorState(message: error.localizedDescription))
        }
    }

    static let demoReport = CampusGradeReport(
        grades: [
            CampusGrade(courseName: "高等数学", courseCode: "MATH1001", credit: 5, score: "92", gradePoint: 4.2, courseProperty: "学科基础", semesterID: 202601, semesterName: "2025-2026-1"),
            CampusGrade(courseName: "大学英语", courseCode: "ENG1001", credit: 3, score: "优秀", gradePoint: 4.5, courseProperty: "公共基础", semesterID: 202601, semesterName: "2025-2026-1"),
            CampusGrade(courseName: "数据结构", courseCode: "CS2002", credit: 4, score: "88", gradePoint: 3.8, courseProperty: "专业核心", semesterID: 202602, semesterName: "2025-2026-2")
        ],
        gradePointAverage: 4.08,
        rank: "12 / 126",
        studentProfiles: ["计算机科学与技术"]
    )
}

struct GradeView: View {
    @Environment(\.colorScheme) private var colorScheme
    @StateObject private var model: GradeViewModel
    @State private var query = ""
    @State private var selectedSemester = "全部学期"

    init(appModel: AppModel) {
        _model = StateObject(wrappedValue: GradeViewModel(api: appModel.campusAPI))
    }

    var body: some View {
        AndroidScreen {
            ScrollView {
                VStack(spacing: 16) {
                    AndroidHeader(title: "成绩单", large: true)
                    AndroidSearchField(text: $query, prompt: "搜索课程")
                    if case let .loaded(report) = model.state {
                        summary(report)
                        semesterSelector(report)
                        LazyVStack(spacing: 8) {
                            ForEach(filtered(report.grades)) { grade in gradeCard(grade) }
                        }
                        .padding(.horizontal, 16)
                    } else {
                        stateView
                    }
                }
                .padding(.bottom, 32)
            }
            .scrollIndicators(.hidden)
        }
        .task { await model.load(demo: ProcessInfo.processInfo.arguments.contains("--demo-session")) }
        .refreshable { await model.load() }
        .accessibilityIdentifier("grades.screen")
    }

    private func summary(_ report: CampusGradeReport) -> some View {
        AndroidCard(radius: 32, background: AndroidParityPalette.primaryContainer(colorScheme)) {
            VStack(alignment: .leading, spacing: 16) {
                Text(report.studentProfiles.first ?? "当前学籍").font(.title3.bold())
                HStack {
                    metric("平均绩点", report.gradePointAverage.map { String(format: "%.2f", $0) } ?? "--")
                    metric("专业排名", report.rank ?? "--")
                    metric("课程数", "\(report.grades.count)")
                }
            }
            .padding(20)
        }
        .padding(.horizontal, 16)
        .accessibilityIdentifier("grades.summary")
    }

    private func metric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.title3.bold())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func semesterSelector(_ report: CampusGradeReport) -> some View {
        let semesters = ["全部学期"] + Array(
            Array(Set(report.grades.map(\.semesterName).filter { !$0.isEmpty })).sorted().reversed()
        )
        return ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(semesters, id: \.self) { semester in
                    Button(semester) { selectedSemester = semester }
                        .buttonStyle(AndroidChipButtonStyle(selected: selectedSemester == semester))
                }
            }
            .padding(.horizontal, 16)
        }
        .scrollIndicators(.hidden)
        .accessibilityIdentifier("grades.semester-filter")
    }

    private func gradeCard(_ grade: CampusGrade) -> some View {
        AndroidCard(radius: 24, background: AndroidParityPalette.surface(colorScheme)) {
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(grade.courseName).font(.headline).lineLimit(2)
                    Text([grade.courseCode, grade.courseProperty, grade.credit.map { "\($0.formatted()) 学分" }].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "))
                        .font(.caption).foregroundStyle(.secondary)
                    if !grade.semesterName.isEmpty { Text(grade.semesterName).font(.caption2).foregroundStyle(.secondary) }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    Text(grade.score).font(.title2.bold()).foregroundStyle(AndroidParityPalette.brand)
                    Text(grade.gradePoint.map { "绩点 \($0.formatted())" } ?? "")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(18)
        }
    }

    private func filtered(_ grades: [CampusGrade]) -> [CampusGrade] {
        grades.filter { grade in
            let semesterMatches = selectedSemester == "全部学期" || grade.semesterName == selectedSemester
            let normalized = query.trimmingCharacters(in: .whitespacesAndNewlines)
            return semesterMatches && (normalized.isEmpty || grade.courseName.localizedCaseInsensitiveContains(normalized) || grade.courseCode.localizedCaseInsensitiveContains(normalized))
        }
    }

    @ViewBuilder
    private var stateView: some View {
        switch model.state {
        case .idle, .loading: ProgressView("正在加载成绩…").frame(maxWidth: .infinity, minHeight: 320)
        case .empty: ContentUnavailableView("暂无成绩", systemImage: "chart.bar.doc.horizontal")
        case let .failed(error):
            ContentUnavailableView { Label("加载成绩失败", systemImage: "exclamationmark.triangle") } description: { Text(error.message) } actions: { Button("重试") { Task { await model.load() } } }
        case .loaded: EmptyView()
        }
    }
}

private struct AndroidChipButtonStyle: ButtonStyle {
    let selected: Bool
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(selected ? .white : .primary)
            .padding(.horizontal, 16).padding(.vertical, 9)
            .background(selected ? AndroidParityPalette.brand : Color.primary.opacity(0.06), in: Capsule())
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}
