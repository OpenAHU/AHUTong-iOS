import SwiftUI

@MainActor
final class ExamViewModel: ObservableObject {
    @Published private(set) var state: LoadableState<[CampusExam]> = .idle
    private let api: any CampusCoreAPI

    init(api: any CampusCoreAPI) { self.api = api }

    func load(demo: Bool = false) async {
        state = .loading
        if demo {
            state = .loaded([
                CampusExam(course: "高等数学（期末考试）", time: "2026-07-18 09:00-11:00", seatNumber: "26", location: "磬苑校区-博学南楼101", isFinished: false),
                CampusExam(course: "大学英语（期末考试）", time: "2026-06-20 14:00-16:00", seatNumber: "08", location: "龙河校区-主教楼203", isFinished: true)
            ])
            return
        }
        do {
            let exams = try await api.exams()
            state = exams.isEmpty ? .empty : .loaded(exams)
        } catch {
            state = .failed(AppErrorState(message: error.localizedDescription))
        }
    }
}

struct ExamView: View {
    @Environment(\.colorScheme) private var colorScheme
    @StateObject private var model: ExamViewModel
    @State private var query = ""

    init(appModel: AppModel) {
        _model = StateObject(wrappedValue: ExamViewModel(api: appModel.campusAPI))
    }

    var body: some View {
        AndroidScreen {
            ScrollView {
                VStack(spacing: 16) {
                    AndroidHeader(title: "考场查询", large: true)
                    AndroidSearchField(text: $query, prompt: "搜索课程名称…")
                    content
                }
                .padding(.bottom, 32)
            }
            .scrollIndicators(.hidden)
        }
        .task { await model.load(demo: ProcessInfo.processInfo.arguments.contains("--demo-session")) }
        .refreshable { await model.load() }
        .accessibilityIdentifier("exams.screen")
    }

    @ViewBuilder
    private var content: some View {
        switch model.state {
        case .idle, .loading: ProgressView("加载中…").frame(maxWidth: .infinity, minHeight: 320)
        case .empty: ContentUnavailableView("暂无考试安排", systemImage: "pencil.and.list.clipboard")
        case let .failed(error):
            ContentUnavailableView { Label("加载考试失败", systemImage: "exclamationmark.triangle") } description: { Text(error.message) } actions: { Button("重试") { Task { await model.load() } } }
        case let .loaded(exams):
            let matched = exams.filter { query.isEmpty || $0.course.localizedCaseInsensitiveContains(query) }
            if matched.isEmpty {
                ContentUnavailableView.search(text: query)
            } else {
                LazyVStack(spacing: 12) {
                    ForEach(matched) { exam in examCard(exam) }
                }
                .padding(.horizontal, 16)
            }
        }
    }

    private func examCard(_ exam: CampusExam) -> some View {
        AndroidCard(radius: 28, background: AndroidParityPalette.surface(colorScheme)) {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .firstTextBaseline) {
                    Text(exam.course).font(.title3.bold()).lineLimit(2)
                    Spacer()
                    Text(exam.isFinished ? "已结束" : "待考试")
                        .font(.caption.bold())
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(exam.isFinished ? Color.gray.opacity(0.16) : AndroidParityPalette.primaryContainer(colorScheme), in: Capsule())
                }
                Label(exam.time, systemImage: "clock.fill").font(.headline)
                HStack {
                    Label(exam.location, systemImage: "mappin.and.ellipse").lineLimit(2)
                    Spacer()
                    VStack(spacing: 2) { Text("座号").font(.caption); Text(exam.seatNumber).font(.title2.bold()) }
                }
            }
            .padding(20)
        }
        .accessibilityElement(children: .combine)
    }
}
