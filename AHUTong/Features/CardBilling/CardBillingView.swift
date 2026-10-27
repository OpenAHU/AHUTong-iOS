import Charts
import SwiftUI

struct CardBillingView: View {
    private let api: any CampusCoreAPI
    @StateObject private var model: CardBillingViewModel
    @State private var month = Date()
    @State private var allTime = false
    @State private var type = "all"
    @State private var showsFilters = false
    @State private var minimum = ""
    @State private var maximum = ""
    init(appModel: AppModel) {
        api = appModel.campusAPI
        _model = StateObject(wrappedValue: CardBillingViewModel(remote: OfficialCardBillingRemote(api: appModel.campusAPI)))
    }
    private var range: CardBillRange? { allTime ? CardBillRange(from: "2020-01-01", to: CardBillRange.month(containing: Date()).to) : .month(containing: month) }
    private var queryID: String { "\(range?.from ?? "all")-\(type)" }
    private var filtered: [CardBill] {
        model.records.filter { record in
            let amount = Decimal(record.tranamt) / 100
            return (Decimal(string: minimum).map { amount >= $0 } ?? true) && (Decimal(string: maximum).map { amount <= $0 } ?? true)
        }
    }
    var body: some View {
        List {
            Section {
                if let summary = model.summary {
                    LabeledContent("支出", value: summary.expenses.map(CardBill.money) ?? "—")
                        .nativeNumericTransition(value: summary.expenses)
                    LabeledContent("收入", value: summary.income.map(CardBill.money) ?? "—")
                        .nativeNumericTransition(value: summary.income)
                }
                if let summaryError = model.summaryError { Text(summaryError).font(.footnote).foregroundStyle(.secondary) }
                NavigationLink("消费统计") { CardBillingStatsView(api: api, range: range) }
                    .accessibilityIdentifier("billing.stats")
            } header: { Text(allTime ? "全部时间" : String(CardBillRange.month(containing: month).from.prefix(7))) }
            Section {
                Picker("交易类型", selection: $type) { Text("全部").tag("all"); Text("支出").tag("2"); Text("收入").tag("1") }
                ForEach(filtered) { bill in
                    NavigationLink { CardBillDetailView(bill: bill) } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(bill.merchant).lineLimit(2)
                                Text(bill.time).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text((bill.isExpense ? "−" : "+") + CardBill.money(bill.tranamt))
                                .monospacedDigit().foregroundStyle(bill.isExpense ? Color.primary : Color.green)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
                if model.records.isEmpty, !model.isLoading, model.error == nil { Text("该时间范围暂无账单").foregroundStyle(.secondary) }
                if filtered.isEmpty, !model.records.isEmpty { Text("已加载账单中暂无符合金额的记录").foregroundStyle(.secondary) }
                if model.isLoading { ProgressView("正在查询账单") }
                if let error = model.error { Text(error).foregroundStyle(.secondary) }
                if model.hasMore, !model.isLoading {
                    Button(model.error == nil ? "加载更多" : "重试") { Task { await model.loadMore(range: range, type: type == "all" ? nil : type) } }
                        .accessibilityIdentifier("billing.load-more")
                }
            } footer: { Text("金额筛选仅作用于已加载记录；收支汇总涵盖所选时间范围全部类型。") }
        }
        .navigationTitle("校园卡账单")
        .accessibilityIdentifier("billing.screen")
        .task(id: queryID) { await refresh() }
        .refreshable { await refresh() }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("筛选", systemImage: "line.3.horizontal.decrease") { showsFilters = true }.accessibilityIdentifier("billing.filters")
            }
        }
        .sheet(isPresented: $showsFilters) {
            NavigationStack {
                Form {
                    Toggle("全部时间", isOn: $allTime)
                    if !allTime { DatePicker("月份内任一天", selection: $month, in: ...Date(), displayedComponents: .date) }
                    Section("金额（元）") {
                        TextField("最低金额", text: $minimum).keyboardType(.decimalPad)
                        TextField("最高金额", text: $maximum).keyboardType(.decimalPad)
                    }
                }
                .navigationTitle("筛选账单")
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { showsFilters = false } } }
            }.presentationDetents([.medium, .large])
        }
    }
    private func refresh() async { await model.refresh(range: range, type: type == "all" ? nil : type, demo: AppRuntime.isDemoSession) }
}

private struct CardBillDetailView: View {
    let bill: CardBill
    var body: some View {
        Form {
            LabeledContent("金额", value: CardBill.money(bill.tranamt))
            LabeledContent("方向", value: bill.isExpense ? "支出" : "收入")
            LabeledContent("商户", value: bill.merchant)
            LabeledContent("交易时间", value: bill.time)
            if let value = bill.turnoverType { LabeledContent("交易类型", value: value) }
            if let value = bill.consumeTypeName { LabeledContent("明细类型", value: value) }
            if let value = bill.cardBalance { LabeledContent("交易后余额", value: CardBill.money(value)) }
            if let value = bill.feeAmt, value != 0 { LabeledContent("手续费", value: CardBill.money(value)) }
            if let value = bill.remark, !value.isEmpty { LabeledContent("备注", value: value) }
            LabeledContent("订单号", value: bill.orderId).textSelection(.enabled)
        }.navigationTitle("账单详情")
    }
}

private struct CardBillingStatsView: View {
    let range: CardBillRange?
    @StateObject private var model: CardBillingViewModel
    init(api: any CampusCoreAPI, range: CardBillRange?) {
        self.range = range
        _model = StateObject(wrappedValue: CardBillingViewModel(remote: OfficialCardBillingRemote(api: api)))
    }
    var body: some View {
        List {
            if let report = model.analytics {
                Section(range.map { "\($0.from) 至 \($0.to)" } ?? "服务器当月") {
                    LabeledContent("总支出", value: CardBill.money(report.expense))
                        .nativeNumericTransition(value: report.expense)
                    LabeledContent("总收入", value: CardBill.money(report.income))
                        .nativeNumericTransition(value: report.income)
                    LabeledContent("消费笔数", value: String(report.expenseCount))
                        .nativeNumericTransition(value: report.expenseCount)
                }
                if report.expenseCount == 0 { Text("该时间范围暂无消费记录") }
                else {
                    Section("每日支出") {
                        Chart(report.days) { day in
                            BarMark(x: .value("日期", String(day.id.suffix(5))), y: .value("元", Double(day.cents) / 100))
                        }.frame(height: 180).accessibilityLabel("每日消费金额，单位元")
                        ForEach(report.days) { day in LabeledContent(day.id, value: CardBill.money(day.cents)) }
                    }
                    Section("商户统计") {
                        ForEach(report.merchants) { merchant in
                            LabeledContent { Text(CardBill.money(merchant.cents)) } label: {
                                Text(merchant.id); Text("\(merchant.count) 笔").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            } else if model.isLoading { ProgressView("正在汇总全部账单") }
            if let error = model.error {
                Text(error).foregroundStyle(.secondary)
                Button("重试") { Task { await load() } }
            }
        }
        .navigationTitle("消费统计")
        .accessibilityIdentifier("billing.stats-screen")
        .task { await load() }
        .refreshable { await load() }
    }
    private func load() async { await model.loadAnalytics(range: range, demo: AppRuntime.isDemoSession) }
}
