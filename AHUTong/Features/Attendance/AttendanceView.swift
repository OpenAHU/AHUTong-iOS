import SwiftUI

@MainActor
final class AttendanceViewModel: ObservableObject {
    @Published private(set) var records: [AttendanceRecord] = []
    @Published private(set) var total = 0
    @Published private(set) var isLoading = false
    @Published private(set) var error: String?
    @Published private(set) var hasMore = false
    private let remote: any AttendanceRemote
    private var nextPage = 1
    private var generation = 0
    init(remote: any AttendanceRemote) { self.remote = remote }

    func load(status: Int, refresh: Bool, demo: Bool) async {
        if refresh { generation += 1; nextPage = 1; records = []; total = 0; hasMore = false }
        else if isLoading || !hasMore { return }
        let revision = generation, page = nextPage
        isLoading = true; error = nil
        defer { if revision == generation, !(demo && DemoDataState.current == .loading) { isLoading = false } }
        do {
            let result: AttendancePage
            if demo {
                switch DemoDataState.current {
                case .loading: return
                case .error: throw CampusWebError.server("暂时无法连接考勤服务")
                case .empty: result = AttendancePage(totalCount: 0, records: [])
                case .normal:
                    let values = Self.demo.filter { status == 0 || $0.status == status }
                    result = AttendancePage(totalCount: values.count, records: values)
                }
            } else { result = try await remote.page(status: status, page: page) }
            try Task.checkCancellation()
            guard revision == generation else { return }
            records += result.records; total = result.totalCount
            hasMore = !result.records.isEmpty && records.count < result.totalCount
            nextPage = page + 1
        } catch is CancellationError {} catch {
            guard revision == generation else { return }
            self.error = error.localizedDescription
        }
    }

    static let demo: [AttendanceRecord] = [
        .init(courseName: "高等数学", courseCode: "DEMO001", teacher: "示例教师", room: "博学楼 A101", building: "博学楼",
              section: "第1-2节", classDate: "2026-10-26", startTime: "08:20", endTime: "09:55", punchTime: "2026-10-26 08:12:00", status: 1, canAppeal: false),
        .init(courseName: "大学英语", courseCode: "DEMO002", teacher: "示例教师", room: "博学楼 B202", building: "博学楼",
              section: "第3-4节", classDate: "2026-10-23", startTime: "10:15", endTime: "11:50", punchTime: "", status: 3, canAppeal: true)
    ]
}

struct AttendanceView: View {
    @StateObject private var model: AttendanceViewModel
    @State private var status = 0
    init(appModel: AppModel) {
        _model = StateObject(wrappedValue: AttendanceViewModel(remote: OfficialAttendanceRemote(api: appModel.campusAPI)))
    }
    var body: some View {
        List {
            Picker("考勤状态", selection: $status) {
                Text("全部").tag(0); Text("正常").tag(1); Text("迟到").tag(2); Text("缺勤").tag(3); Text("请假").tag(5)
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("attendance.status")
            .listRowBackground(Color.clear)
            Section {
                ForEach(Array(model.records.enumerated()), id: \.offset) { _, record in
                    NavigationLink {
                        AttendanceDetailView(record: record)
                    } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(alignment: .firstTextBaseline) {
                                Text(record.courseName.isEmpty ? "未知课程" : record.courseName).font(.headline).foregroundStyle(Color.primary)
                                Spacer()
                                Text(record.statusText).font(.subheadline).foregroundStyle(statusColor(record.status))
                            }
                            Text([record.classDate, record.section].filter { !$0.isEmpty }.joined(separator: " · "))
                            Text([record.room, record.teacher].filter { !$0.isEmpty }.joined(separator: " · "))
                        }.font(.subheadline).foregroundStyle(.secondary)
                    }
                }
                if model.isLoading { ProgressView("正在查询考勤") }
                if model.records.isEmpty, !model.isLoading, model.error == nil {
                    ContentUnavailableView("暂无考勤记录", systemImage: "checkmark.circle", description: Text("所选状态下没有记录"))
                }
                if let error = model.error {
                    Text(error).foregroundStyle(.secondary)
                    Button("重试") { Task { await load(refresh: model.records.isEmpty) } }.accessibilityIdentifier("attendance.retry")
                } else if model.hasMore, !model.isLoading {
                    Button("加载更多") { Task { await load(refresh: false) } }.accessibilityIdentifier("attendance.more")
                }
            } footer: {
                if !model.records.isEmpty { Text("已加载 \(model.records.count) / \(model.total) 条，以教务系统记录为准。") }
            }
        }
        .navigationTitle("教务考勤")
        .accessibilityIdentifier("attendance.screen")
        .task(id: status) { await load(refresh: true) }
        .refreshable { await load(refresh: true) }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("刷新", systemImage: "arrow.clockwise") { Task { await load(refresh: true) } }.disabled(model.isLoading)
            }
        }
    }
    private func load(refresh: Bool) async { await model.load(status: status, refresh: refresh, demo: AppRuntime.isDemoSession) }
    private func statusColor(_ value: Int) -> Color {
        switch value { case 1: .green; case 2: .orange; case 3: .red; default: .secondary }
    }
}

private struct AttendanceDetailView: View {
    let record: AttendanceRecord
    var body: some View {
        Form {
            Section {
                LabeledContent("课程", value: record.courseName)
                LabeledContent("状态", value: record.statusText)
                LabeledContent("日期", value: record.classDate)
                if !record.section.isEmpty { LabeledContent("节次", value: record.section) }
                if !record.startTime.isEmpty { LabeledContent("时间", value: [record.startTime, record.endTime].filter { !$0.isEmpty }.joined(separator: "–")) }
                if !record.room.isEmpty { LabeledContent("地点", value: record.room) }
                if !record.teacher.isEmpty { LabeledContent("教师", value: record.teacher) }
                LabeledContent("打卡时间", value: record.punchTime.isEmpty ? "未记录" : record.punchTime)
                if !record.courseCode.isEmpty { LabeledContent("课程代码", value: record.courseCode) }
            } footer: {
                if record.canAppeal { Text("记录如有异议，请在校方教务考勤中申诉。") }
            }
        }
        .navigationTitle("考勤详情")
        .accessibilityIdentifier("attendance.detail")
    }
}
