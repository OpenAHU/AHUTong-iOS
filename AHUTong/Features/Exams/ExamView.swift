import SwiftUI

enum CampusExamDisplayStatus: Equatable {
    case ongoing
    case notStarted
    case finished
    case invalid

    var title: String {
        switch self {
        case .ongoing: "进行中"
        case .notStarted: "未开始"
        case .finished: "已结束"
        case .invalid: "时间解析错误"
        }
    }

    static func resolve(time: String, isFinished: Bool, now: Date = Date()) -> Self {
        let values = time.components(separatedBy: "~")
        guard values.count == 2 else { return isFinished ? .finished : .invalid }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        let datePart = values[0].prefix(10)
        guard
            let start = formatter.date(from: values[0].trimmingCharacters(in: .whitespaces)),
            let end = formatter.date(from: "\(datePart) \(values[1].trimmingCharacters(in: .whitespaces))")
        else { return isFinished ? .finished : .invalid }
        if now < start { return .notStarted }
        if now > end { return .finished }
        return .ongoing
    }
}

@MainActor
final class ExamViewModel: ObservableObject {
    @Published private(set) var state: LoadableState<[CampusExam]> = .idle
    private let api: any CampusCoreAPI
    private let cache: JSONStore<[CampusExam]>

    init(api: any CampusCoreAPI, userID: String) {
        self.api = api
        cache = JSONStore(
            store: UserScopedStore(store: AppPersistence.migratingFileCache(), userID: userID),
            key: "exams.v1"
        )
    }

    func load(demo: Bool = false) async {
        state = .loading
        if demo {
            switch DemoDataState.current {
            case .normal:
                let exams = DebugRuntimeSettings.decode("exam", as: [CampusExam].self) ?? Self.demoExams
                state = exams.isEmpty ? .empty : .loaded(exams)
            case .loading: return
            case .empty: state = .empty
            case .error: state = .failed(AppErrorState(message: "Mock 场景：接口返回 500"))
            }
            return
        }
        let cached = try? await cache.load()
        if let cached { state = cached.isEmpty ? .empty : .loaded(cached) }
        do {
            let exams = try await api.exams()
            try await cache.save(exams)
            state = exams.isEmpty ? .empty : .loaded(exams)
        } catch {
            if cached == nil { state = .failed(AppErrorState(message: error.localizedDescription)) }
        }
    }

    static var demoExams: [CampusExam] {
        let day = DateFormatter()
        day.locale = Locale(identifier: "en_US_POSIX")
        day.calendar = Calendar(identifier: .gregorian)
        day.timeZone = .current
        day.dateFormat = "yyyy-MM-dd"
        let calendar = Calendar(identifier: .gregorian)
        let today = DemoDataState.referenceDate
        func date(_ offset: Int) -> String {
            day.string(from: calendar.date(byAdding: .day, value: offset, to: today) ?? today)
        }
        let clock = DateFormatter()
        clock.locale = Locale(identifier: "en_US_POSIX")
        clock.timeZone = .current
        clock.dateFormat = "HH:mm"
        return [
            CampusExam(course: "操作系统", time: "\(date(0)) \(clock.string(from: today.addingTimeInterval(-20 * 60)))~\(clock.string(from: today.addingTimeInterval(80 * 60)))", seatNumber: "18", location: "博学南楼 A210", isFinished: false),
            CampusExam(course: "计算机网络", time: "\(date(2)) 09:00~11:00", seatNumber: "32", location: "笃行北楼 B402", isFinished: false),
            CampusExam(course: "数据库系统", time: "\(date(5)) 14:30~16:30", seatNumber: "07", location: "文典阁 205", isFinished: false),
            CampusExam(course: "软件工程", time: "\(date(-3)) 08:00~10:00", seatNumber: "21", location: "博学南楼 A101", isFinished: true)
        ]
    }
}

struct ExamView: View {
    @Environment(\.colorScheme) private var colorScheme
    @StateObject private var model: ExamViewModel
    @State private var query = ""
    @State private var isSearching = false

    init(appModel: AppModel) {
        let userID = if case let .authenticated(user) = appModel.sessionState { user.studentID } else { "demo" }
        _model = StateObject(wrappedValue: ExamViewModel(api: appModel.campusAPI, userID: userID))
    }

    private var isDemo: Bool {
        AppRuntime.isDemoSession
    }

    private var statusReferenceDate: Date {
        isDemo ? DemoDataState.referenceDate : Date()
    }

    var body: some View {
        AndroidScreen {
            ScrollView {
                VStack(spacing: 24) {
                    header
                    content
                }
                .padding(.bottom, 32)
            }
            .scrollIndicators(.hidden)
        }
        .task { await model.load(demo: isDemo) }
        .refreshable { await model.load(demo: isDemo) }
        .accessibilityIdentifier("exams.screen")
    }

    @ViewBuilder
    private var header: some View {
        if isSearching {
            HStack(spacing: 8) {
                AndroidIconButton(systemName: "arrow.left", accessibilityLabel: "返回") {
                    isSearching = false
                    query = ""
                }
                AndroidSearchField(text: $query, prompt: "搜索课程名称…")
            }
            .padding(.horizontal, 16)
            .padding(.top, 24)
        } else {
            AndroidHeader(title: "考场查询", large: true) {
                AndroidIconButton(systemName: "magnifyingglass", accessibilityLabel: "搜索") { isSearching = true }
                AndroidIconButton(systemName: "arrow.clockwise", accessibilityLabel: "刷新") {
                    Task { await model.load(demo: isDemo) }
                }
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch model.state {
        case .idle, .loading:
            ProgressView().frame(maxWidth: .infinity, minHeight: 320)
        case .empty:
            emptyText("目前没有任何考试")
        case let .failed(error):
            VStack(spacing: 20) {
                Text(error.message).foregroundStyle(.red).multilineTextAlignment(.center)
                Button("重试") { Task { await model.load(demo: isDemo) } }.buttonStyle(.borderedProminent)
            }
            .padding(24)
        case let .loaded(exams):
            let matched = exams.filter { !isSearching || query.isEmpty || $0.course.localizedCaseInsensitiveContains(query) }
            if matched.isEmpty {
                emptyText(isSearching && !query.isEmpty ? "未找到包含「\(query)」的考试" : "目前没有任何考试")
            } else {
                LazyVStack(spacing: 2) {
                    ForEach(matched.sorted(by: examSort)) { exam in examCard(exam) }
                }
                .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
                .padding(.horizontal, 16)
            }
        }
    }

    private func emptyText(_ text: String) -> some View {
        Text(text).font(.title3).frame(maxWidth: .infinity, alignment: .leading).padding(24)
    }

    private func examSort(_ lhs: CampusExam, _ rhs: CampusExam) -> Bool {
        let order: [CampusExamDisplayStatus] = [.ongoing, .notStarted, .finished, .invalid]
        let left = order.firstIndex(of: .resolve(time: lhs.time, isFinished: lhs.isFinished, now: statusReferenceDate)) ?? 3
        let right = order.firstIndex(of: .resolve(time: rhs.time, isFinished: rhs.isFinished, now: statusReferenceDate)) ?? 3
        return left == right ? lhs.time < rhs.time : left < right
    }

    private func examCard(_ exam: CampusExam) -> some View {
        let status = CampusExamDisplayStatus.resolve(time: exam.time, isFinished: exam.isFinished, now: statusReferenceDate)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(exam.course).font(.headline.bold()).lineLimit(1)
                Text(status.title)
                    .font(.caption)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(statusColor(status), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                Spacer(minLength: 0)
            }
            .padding(8)
            Text("考试时间：\(exam.time)").font(.body).foregroundStyle(AndroidParityPalette.secondaryText(colorScheme))
            Text("地点：\(exam.location)，座位号：\(exam.seatNumber)").font(.subheadline).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 24).padding(.vertical, 16)
        .background(AndroidParityPalette.surface(colorScheme))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("exams.card.\(exam.id)")
    }

    private func statusColor(_ status: CampusExamDisplayStatus) -> Color {
        switch status {
        case .ongoing: Color(red: 1, green: 193 / 255, blue: 7 / 255)
        case .notStarted: AndroidParityPalette.success
        case .finished: .gray
        case .invalid: .red
        }
    }
}
