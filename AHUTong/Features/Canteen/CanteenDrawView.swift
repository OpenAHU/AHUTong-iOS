import SwiftUI

struct CanteenFilterButton: View {
    let selection: Set<String>
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            LabeledContent {
                HStack(spacing: 6) {
                    Text(selection.isEmpty ? "全部食堂" : selection.sorted().joined(separator: "、"))
                        .multilineTextAlignment(.trailing)
                    Image(systemName: "chevron.up.chevron.down").font(.caption2.bold())
                }
                .foregroundStyle(.tint)
            } label: {
                Text("食堂").foregroundStyle(Color.primary)
            }
        }
    }
}

struct CanteenSelectionSheet: View {
    @Environment(\.dismiss) private var dismiss
    let options: [String]
    @Binding var selection: Set<String>
    @State private var draft: Set<String>
    init(options: [String], selection: Binding<Set<String>>) {
        self.options = options; _selection = selection
        _draft = State(initialValue: selection.wrappedValue.isEmpty ? Set(options) : selection.wrappedValue)
    }
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button("全选") { draft = Set(options) }.accessibilityIdentifier("canteen.select-all")
                    Button("清空选择") { draft = [] }.accessibilityIdentifier("canteen.clear-selection")
                }
                Section("选择一个或多个食堂") {
                    ForEach(options, id: \.self) { name in
                        Toggle(name, isOn: Binding(get: { draft.contains(name) }, set: { value in
                            if value { draft.insert(name) } else { draft.remove(name) }
                        })).accessibilityIdentifier("canteen.select.\(name)")
                    }
                }
            }
            .navigationTitle("选择食堂").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { selection = draft == Set(options) ? [] : draft; dismiss() }
                        .disabled(draft.isEmpty).accessibilityIdentifier("canteen.selection-done")
                }
            }
        }
    }
}

struct CanteenDrawView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var model = CanteenRankingViewModel()
    @State private var query: CanteenQuery
    @State private var showsCanteens = false
    @State private var selectedWindow: CanteenInsights.Window?
    @State private var drawID: UUID?
    private var isDrawing: Bool { drawID != nil }
    @State private var rolling: CanteenInsights.Window?
    @State private var result: CanteenInsights.Window?
    @State private var step = 0
    init(query: CanteenQuery) {
        var query = query
        query.limit = 200
        _query = State(initialValue: query)
    }
    private var candidates: [CanteenInsights.Window] {
        guard model.saved?.query == query else { return [] }
        return (model.saved?.value.ranking ?? []).filter { $0.isNamed && query.includes($0.canteen ?? "") }
    }
    var body: some View {
        ScrollViewReader { proxy in
            List {
                Section {
                    Picker("校区", selection: $query.campus) {
                        ForEach(CanteenCampus.allCases) { Text($0.title).tag($0) }
                    }.accessibilityIdentifier("canteen.draw-campus")
                    CanteenFilterButton(selection: query.selectedCanteens) { showsCanteens = true }
                        .accessibilityIdentifier("canteen.draw-canteens")
                    Picker("参考周期", selection: $query.period) {
                        ForEach(CanteenPeriod.allCases) { Text($0.title).tag($0) }
                    }
                }.disabled(isDrawing)
                Section {
                    VStack(spacing: 14) {
                        Image(systemName: "fork.knife.circle.fill").font(.system(size: 44)).foregroundStyle(.orange)
                        ZStack {
                            VStack(spacing: 8) {
                                Text(rolling?.title ?? "今天吃什么？").font(.title2.bold()).multilineTextAlignment(.center)
                                Text(rolling?.location ?? "选好食堂，让安大通帮你挑一家")
                                    .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                            }
                            .id(step)
                            .transition(reduceMotion ? .opacity : .asymmetric(insertion: .move(edge: .bottom).combined(with: .opacity), removal: .move(edge: .top).combined(with: .opacity)))
                        }
                        .frame(maxWidth: .infinity, minHeight: 105).clipped()
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(isDrawing ? "正在抽取" : rolling.map { "\($0.title)，\($0.location)" } ?? "今天吃什么？")
                        Button {
                            result = nil; drawID = UUID()
                        } label: {
                            Text(result == nil ? "帮我选一家" : "再抽一次")
                                .frame(maxWidth: .infinity, alignment: .center)
                        }
                        .buttonStyle(.borderedProminent).controlSize(.large)
                        .disabled(isDrawing || model.isLoading || candidates.isEmpty)
                        .accessibilityIdentifier("canteen.draw-start")
                        Text(isDrawing ? "正在挑选…" : "\(candidates.count) 个窗口可选 · 每家机会相同")
                            .font(.footnote).foregroundStyle(.secondary)
                    }.frame(maxWidth: .infinity).padding(.vertical, 12)
                } footer: { Text("从所选范围的已命名窗口中抽取。热度来自正餐消费样本，均价仅供参考。") }
                if model.isLoading { ProgressView("正在获取可选窗口") }
                if let error = model.error {
                    Section { Text(error); Button("重试") { Task { await load(refresh: true) } } }
                } else if !model.isLoading, candidates.isEmpty {
                    ContentUnavailableView("暂无可抽取的窗口", systemImage: "fork.knife", description: Text("试试其他食堂或更长的参考周期"))
                }
                if let result {
                    Section {
                        Text(result.title).font(.headline)
                        LabeledContent("位置", value: result.location)
                        LabeledContent("热度排名", value: result.rank.map { "第 \($0) 名" } ?? "暂无排名")
                        LabeledContent("平均消费", value: result.avgCentsPerTxn.map { ($0 / 100).formatted(.currency(code: "CNY")) } ?? "暂无均价样本")
                        Button("查看窗口详情") { selectedWindow = result }
                            .id("canteen.draw.details")
                            .accessibilityIdentifier("canteen.draw.details")
                    } header: { Text("这次就吃它") } footer: { Text("排名范围：\(query.title) · \(query.period.title)。平均消费按每笔交易计算。") }
                    .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
                }
            }
            .navigationTitle("吃什么").navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showsCanteens) { CanteenSelectionSheet(options: query.campus.names, selection: $query.selectedCanteens) }
            .sheet(item: $selectedWindow) { CanteenWindowDetail(window: $0) }
            .onChange(of: query.campus) { _, _ in query.selectedCanteens = [] }
            .task(id: query) { result = nil; rolling = nil; await load() }
            .task(id: drawID) { if let drawID { await draw(id: drawID) } }
            .onDisappear { drawID = nil; result = nil; rolling = nil }
            .onChange(of: scenePhase) { _, phase in if phase != .active { drawID = nil } }
            .sensoryFeedback(.selection, trigger: step)
            .sensoryFeedback(.success, trigger: result?.id)
            .onChange(of: result?.id) { _, id in
                if id != nil {
                    withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.3)) {
                        proxy.scrollTo("canteen.draw.details", anchor: .bottom)
                    }
                }
            }
        }
    }
    private func load(refresh: Bool = false) async { await model.load(query, refresh: refresh, demo: AppRuntime.isDemoSession) }
    @MainActor private func draw(id: UUID) async {
        defer { if drawID == id { drawID = nil } }
        let pool = candidates
        guard let winner = pool.randomElement() else { return }
        do {
            // 24 progressively slower steps total approximately three seconds.
            if reduceMotion {
                try await Task.sleep(for: .seconds(3))
            } else {
                for index in 0..<24 {
                    try Task.checkCancellation()
                    withAnimation(.easeOut(duration: 0.12)) {
                        rolling = pool.randomElement(); step += 1
                    }
                    try await Task.sleep(for: .seconds(0.065 + Double(index) * 0.0052))
                }
            }
            try Task.checkCancellation()
            guard drawID == id else { return }
            withAnimation(.easeOut(duration: reduceMotion ? 0.15 : 0.3)) {
                rolling = winner; step += 1; result = winner
            }
        } catch { rolling = nil }
    }
}
