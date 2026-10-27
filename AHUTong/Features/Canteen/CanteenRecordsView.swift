import SwiftUI

struct CanteenRecordsView: View {
    @ObservedObject var appModel: AppModel
    @StateObject private var model: CanteenRecordsModel
    private let community: any CanteenCommunityRemote
    @State private var canteens: Set<String> = []
    @State private var showsCanteens = false
    @State private var contribution: ContributionPreview?
    init(appModel: AppModel) {
        self.appModel = appModel
        let community = OfficialCanteenCommunityRemote()
        self.community = community
        _model = StateObject(wrappedValue: CanteenRecordsModel(bills: OfficialCardBillingRemote(api: appModel.campusAPI), community: community))
    }
    private var meals: [CanteenMeal] { model.footprint?.filtered(canteens: canteens) ?? [] }
    private var groups: [(terminal: String, meals: [CanteenMeal])] {
        Dictionary(grouping: meals.filter { $0.terminal != nil }, by: { $0.terminal! })
            .map { (terminal: $0.key, meals: $0.value) }
            .sorted { $0.meals.count == $1.meals.count ? $0.terminal < $1.terminal : $0.meals.count > $1.meals.count }
    }
    var body: some View {
        List {
            if appModel.isExperienceMode && !AppRuntime.isDemoSession {
                ContentUnavailableView("登录后查看我的记录", systemImage: "person.crop.circle", description: Text("请先在设置中登录校园账号"))
            } else {
                Section {
                    CanteenFilterButton(selection: canteens) { showsCanteens = true }
                        .disabled(model.footprint == nil).accessibilityIdentifier("canteen.records-canteens")
                    if model.footprint != nil {
                        LabeledContent("正餐次数", value: "\(meals.count) 餐")
                            .nativeNumericTransition(value: meals.count)
                        let total = meals.reduce(Int64(0)) { $0 + $1.cents }
                        LabeledContent("累计消费", value: CardBill.money(total))
                            .nativeNumericTransition(value: total)
                        let average = meals.isEmpty ? "—" : CardBill.money(total / Int64(meals.count))
                        LabeledContent("平均每餐", value: average)
                            .nativeNumericTransition(value: average)
                        LabeledContent("光顾窗口", value: "\(Set(meals.compactMap(\.terminal)).count) 个")
                    }
                } header: { Text("近180天 · 我的用餐") } footer: {
                    Text("仅在本机分析校园卡账单。统计午餐 10:30–14:00、晚餐 16:30–22:30；同一窗口 5 分钟内的交易合并为一餐。")
                }
                if model.isLoading { ProgressView("正在整理用餐记录") }
                if let error = model.error {
                    Section { Text(error).foregroundStyle(.secondary); Button("重试") { Task { await load() } }.accessibilityIdentifier("canteen.records-retry") }
                }
                if let error = model.mappingError { Text(error).font(.footnote).foregroundStyle(.secondary) }
                if !groups.isEmpty {
                    Section("我常去的窗口") {
                        ForEach(Array(groups.prefix(10).enumerated()), id: \.element.terminal) { index, group in
                            HStack {
                                Text("\(index + 1)").font(.headline).monospacedDigit().foregroundStyle(.secondary).frame(minWidth: 24)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(model.names[group.terminal] ?? "未命名窗口")
                                    Text(group.meals.first?.location ?? "").font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text("\(group.meals.count) 餐").foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                if model.footprint != nil {
                    Section("用餐记录") {
                        ForEach(meals) { meal in
                            NavigationLink {
                                CanteenMealDetail(meal: meal, name: meal.terminal.flatMap { model.names[$0] },
                                                  sampleCount: model.footprint?.transactions.filter { $0.terminal == meal.terminal }.count ?? 0, community: community)
                            } label: {
                                HStack(alignment: .top) {
                                    VStack(alignment: .leading, spacing: 5) {
                                        Text(meal.terminal.flatMap { model.names[$0] } ?? meal.location).font(.headline)
                                        Text("\(meal.date.formatted(.dateTime.month().day())) · \(meal.slot) · \(meal.location)")
                                            .font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Text(CardBill.money(meal.cents)).monospacedDigit()
                                }.padding(.vertical, 3)
                            }
                        }
                        if meals.isEmpty { ContentUnavailableView("暂无用餐记录", systemImage: "fork.knife", description: Text("所选食堂暂无符合正餐时段的校园卡消费")) }
                    }
                }
            }
        }
        .navigationTitle("我的记录").navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("贡献记录", systemImage: "arrow.up.doc") {
                    if let footprint = model.footprint { contribution = .init(transactions: footprint.contribution(now: Date())) }
                }
                .labelStyle(.iconOnly)
                .disabled(model.footprint == nil || model.isLoading)
                .accessibilityIdentifier("canteen.contribution-preview")
            }
        }
        .task { await load() }
        .refreshable { await load() }
        .sheet(isPresented: $showsCanteens) {
            CanteenSelectionSheet(options: Array(Set(model.footprint?.meals.map(\.canteen) ?? [])).sorted(), selection: $canteens)
        }
        .sheet(item: $contribution) { preview in CanteenContributionView(transactions: preview.transactions, community: community) }
    }
    private func load() async {
        guard !appModel.isExperienceMode || AppRuntime.isDemoSession else { return }
        await model.load(demo: AppRuntime.isDemoSession)
    }
    private struct ContributionPreview: Identifiable { let id = UUID(); let transactions: [CanteenTransaction] }
}

private struct CanteenContributionView: View {
    @Environment(\.dismiss) private var dismiss
    let transactions: [CanteenTransaction]
    let community: any CanteenCommunityRemote
    @State private var agrees = false
    @State private var isSubmitting = false
    @State private var finished = false
    @State private var error: String?
    @State private var submissionID: UUID?
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("待贡献", value: "\(transactions.count) 笔正餐消费")
                    NavigationLink("查看全部待发送数据") {
                        List(transactions, id: \.self) { row in
                            VStack(alignment: .leading, spacing: 5) {
                                Text("\(row.canteen) · \(row.floor ?? "楼层未知") · \(CardBill.money(row.amountCents))")
                                Text("\(row.ts) · 终端 \(row.terminal)").font(.caption).foregroundStyle(.secondary)
                            }
                        }.navigationTitle("待发送数据")
                    }
                } footer: {
                    Text("向 inchangejiang.cn 发送终端号、时间、金额、食堂和楼层，不含账号、订单号、卡号或校园登录凭据。")
                }
                Section {
                    Toggle("同意本次贡献", isOn: $agrees).disabled(isSubmitting || finished)
                        .accessibilityIdentifier("canteen.contribution-consent")
                    Text("用于公开聚合榜单。服务可见 IP，时间和地点可能反映活动规律；提交后无法按个人身份撤回。")
                        .font(.footnote).foregroundStyle(.secondary)
                    if AppRuntime.isDemoSession { Label("演示数据不会提交", systemImage: "info.circle") }
                    else if !community.canContribute { Label("此安装包暂未配置贡献服务", systemImage: "info.circle") }
                    if transactions.isEmpty { Text("近30天暂无可贡献的正餐记录").foregroundStyle(.secondary) }
                    if let error { Text(error).foregroundStyle(.red) }
                    if finished { Label("已上传", systemImage: "checkmark.circle.fill").foregroundStyle(.green) }
                    if isSubmitting { ProgressView("正在上传") }
                }
            }
            .navigationTitle("贡献预览").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(finished ? "完成" : "取消") { dismiss() }.disabled(isSubmitting) }
                ToolbarItem(placement: .confirmationAction) {
                    Button("上传", systemImage: "arrow.up.doc") { isSubmitting = true; submissionID = UUID() }
                        .labelStyle(.iconOnly)
                        .disabled(!agrees || transactions.isEmpty || isSubmitting || finished || AppRuntime.isDemoSession || !community.canContribute)
                        .accessibilityIdentifier("canteen.contribution-submit")
                }
            }
            .interactiveDismissDisabled(isSubmitting)
            .task(id: submissionID) {
                guard submissionID != nil else { return }
                isSubmitting = true; error = nil
                defer { isSubmitting = false }
                do { try await community.upload(transactions); finished = true }
                catch is CancellationError {} catch { self.error = error.localizedDescription }
            }
        }
    }
}

private struct CanteenMealDetail: View {
    let meal: CanteenMeal
    let name: String?
    let sampleCount: Int
    let community: any CanteenCommunityRemote
    @State private var suggestion = ""
    @State private var showsConfirmation = false
    @State private var submissionID: UUID?
    @State private var isSubmitting = false
    @State private var finished = false
    @State private var error: String?
    private var proposedName: String { suggestion.trimmingCharacters(in: .whitespacesAndNewlines) }
    var body: some View {
        Form {
            Section {
                LabeledContent("窗口", value: name ?? "未命名窗口")
                LabeledContent("位置", value: meal.location)
                LabeledContent("时间", value: meal.date.formatted(date: .numeric, time: .shortened))
                LabeledContent("餐段", value: meal.slot)
                LabeledContent("本餐消费", value: CardBill.money(meal.cents))
                if let terminal = meal.terminal { LabeledContent("终端编号", value: terminal) }
            }
            if meal.terminal != nil, name == nil {
                Section {
                    TextField("窗口叫什么？（最多20字）", text: $suggestion).disabled(isSubmitting || finished)
                    if !community.canContribute { Text("此安装包暂未配置贡献服务").font(.footnote).foregroundStyle(.secondary) }
                    if let error { Text(error).foregroundStyle(.red) }
                    if isSubmitting { ProgressView("正在提交") }
                    if finished { Label("已提交，等待审核", systemImage: "checkmark.circle") }
                    Button("预览提交") { showsConfirmation = true }
                        .disabled(proposedName.isEmpty || proposedName.count > 20 || isSubmitting || finished || !community.canContribute || AppRuntime.isDemoSession)
                } header: { Text("补充窗口名称") } footer: { Text("只提交窗口终端号、食堂位置、建议名称和样本笔数，不发送账号或本餐时间、金额。审核通过后会出现在榜单中。") }
            }
        }
        .navigationTitle("用餐详情").navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("提交“\(proposedName)”？", isPresented: $showsConfirmation, titleVisibility: .visible) {
            Button("确认提交") { isSubmitting = true; submissionID = UUID() }
            Button("取消", role: .cancel) {}
        } message: { Text("发送到 inchangejiang.cn：终端 \(meal.terminal ?? "")，\(meal.location)，\(sampleCount) 笔样本。服务仍可看到连接 IP。") }
        .task(id: submissionID) {
            guard submissionID != nil, let terminal = meal.terminal else { return }
            isSubmitting = true; error = nil
            defer { isSubmitting = false }
            do {
                try await community.report(.init(terminal: terminal, merchant: meal.location, suggestedName: proposedName, sampleCount: sampleCount))
                finished = true
            } catch is CancellationError {} catch { self.error = error.localizedDescription }
        }
    }
}
