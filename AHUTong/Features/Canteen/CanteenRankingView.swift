import Charts
import SwiftUI

struct CanteenRankingView: View {
    let appModel: AppModel
    @State private var showsCanteens = false
    @StateObject private var model = CanteenRankingViewModel()
    @State private var query = CanteenQuery()
    var body: some View {
        List {
            Section {
                Picker("榜单周期", selection: $query.period) {
                    ForEach(CanteenPeriod.allCases) { Text($0.title).tag($0) }
                }.pickerStyle(.segmented).accessibilityIdentifier("canteen.period")
                Picker("校区", selection: $query.campus) {
                    ForEach(CanteenCampus.allCases) { Text($0.title).tag($0) }
                }.accessibilityIdentifier("canteen.campus")
                CanteenFilterButton(selection: query.selectedCanteens) { showsCanteens = true }
                    .accessibilityIdentifier("canteen.canteens")
            }
            if model.isLoading { ProgressView(model.saved == nil ? "正在查询必吃榜" : "正在更新榜单") }
            if let error = model.error {
                Text(error).foregroundStyle(.secondary)
                Button("重试") { Task { await load(refresh: true) } }.accessibilityIdentifier("canteen.retry")
            }
            if let saved = model.saved {
                let data = saved.value
                Section {
                    ForEach(Array((data.ranking ?? []).enumerated()), id: \.offset) { _, window in
                        NavigationLink { CanteenWindowDetail(window: window) } label: {
                            HStack(alignment: .top, spacing: 12) {
                                Text(window.rank.map(String.init) ?? "—").font(.title3.bold()).monospacedDigit()
                                    .foregroundStyle(window.rank.map { $0 <= 3 } == true ? Color.orange : Color.secondary).frame(minWidth: 24)
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(window.title).font(.headline)
                                    Text(window.location).font(.subheadline).foregroundStyle(.secondary)
                                }
                                Spacer(minLength: 8)
                                Text("\(window.txns) 人次").font(.subheadline).monospacedDigit().foregroundStyle(.secondary)
                            }.padding(.vertical, 4)
                        }
                    }
                    if data.ranking?.isEmpty != false {
                        ContentUnavailableView("暂无榜单", systemImage: "fork.knife", description: Text("所选范围内的样本还不足以生成排行"))
                    }
                } header: {
                    Text("\(saved.query.title) · \(saved.query.period.title)热度榜")
                } footer: {
                    VStack(alignment: .leading, spacing: 4) {
                        if let start = data.startDay, let end = data.endDay { Text("\(start) 至 \(end)") }
                        if let sample = data.sample { Text("\(sample.txns ?? 0) 笔样本 · \(sample.terminals ?? 0) 个窗口 · \(sample.days ?? 0) 天") }
                    }
                }
                if let highlights = data.superlatives, highlights.hasContent {
                    Section("人气推荐") {
                        highlight("午餐人气", highlights.lunchTopWindow)
                        highlight("晚餐人气", highlights.dinnerTopWindow)
                        highlight("常青窗口", highlights.mostConsistent)
                        highlight("上升最快", highlights.mostImproved)
                        highlight("小众窗口", highlights.leastPopular)
                        if let peak = highlights.peakDay { LabeledContent("单日峰值", value: "\(peak.day) · \(peak.name ?? "未命名窗口") · \(peak.txns) 人次") }
                        if let hour = highlights.busiestHour { LabeledContent("最忙时段", value: "\(hour.hour):00 · \(hour.txns) 人次") }
                    }
                }
                if let canteens = data.canteenRanking, !canteens.isEmpty {
                    Section("食堂热度") {
                        ForEach(Array(canteens.enumerated()), id: \.offset) { _, canteen in
                            LabeledContent(canteen.canteen, value: "\(canteen.txns) 人次")
                        }
                    }
                }
                if let hours = data.hourly, !hours.isEmpty {
                    Section("用餐时段") {
                        Chart(Array(hours.enumerated()), id: \.offset) { _, hour in
                            BarMark(x: .value("时间", hour.hour), y: .value("人次", hour.txns))
                        }.chartXAxisLabel("时").frame(height: 160).accessibilityLabel("各小时消费人次")
                    }
                }
                if let segments = data.segments, !segments.isEmpty {
                    Section("餐段分布") {
                        ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
                            LabeledContent(segmentTitle(segment.segment), value: "\(segment.txns) 人次")
                        }
                    }
                }
                if let trend = data.trend, !trend.isEmpty {
                    Section("每日热度") {
                        Chart(Array(trend.enumerated()), id: \.offset) { _, day in
                            LineMark(x: .value("日期", String(day.day.suffix(5))), y: .value("人次", day.txns))
                        }.frame(height: 160).accessibilityLabel("每日消费人次变化")
                    }
                }
            }
        }
        .navigationTitle("必吃榜")
        .accessibilityIdentifier("canteen.screen")
        .sheet(isPresented: $showsCanteens) { CanteenSelectionSheet(options: query.campus.names, selection: $query.selectedCanteens) }
        .onChange(of: query.campus) { _, _ in query.selectedCanteens = [] }
        .task(id: query) { await load() }
        .refreshable { await load(refresh: true) }
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                NavigationLink { CanteenRecordsView(appModel: appModel) } label: {
                    Label("我的记录", systemImage: "person.crop.rectangle")
                }
                .labelStyle(.iconOnly)
                .accessibilityIdentifier("canteen.my-records")
                NavigationLink { CanteenDrawView(query: query) } label: {
                    Label("吃什么", systemImage: "shuffle")
                }
                .labelStyle(.iconOnly)
                .accessibilityIdentifier("canteen.draw")
                Button("刷新", systemImage: "arrow.clockwise") { Task { await load(refresh: true) } }
                    .labelStyle(.iconOnly)
                    .disabled(model.isLoading)
                    .accessibilityIdentifier("canteen.refresh")
            }
        }
    }
    private func load(refresh: Bool = false) async { await model.load(query, refresh: refresh, demo: AppRuntime.isDemoSession) }
    @ViewBuilder private func highlight(_ title: String, _ window: CanteenInsights.Window?) -> some View {
        if let window { NavigationLink { CanteenWindowDetail(window: window) } label: { LabeledContent(title, value: window.title) } }
    }
    private func segmentTitle(_ value: String) -> String {
        switch value { case "breakfast": "早餐"; case "lunch": "午餐"; case "dinner": "晚餐"; default: value }
    }
}

struct CanteenWindowDetail: View {
    let window: CanteenInsights.Window
    var body: some View {
        Form {
            LabeledContent("窗口", value: window.title)
            if !window.location.isEmpty { LabeledContent("位置", value: window.location) }
            if let rank = window.rank { LabeledContent("热度排名", value: "第 \(rank) 名") }
            LabeledContent("消费人次", value: String(window.txns))
            if let share = window.share { LabeledContent("样本占比", value: share.formatted(.percent.precision(.fractionLength(1)))) }
            if let average = window.avgCentsPerTxn { LabeledContent("平均每笔", value: (average / 100).formatted(.currency(code: "CNY"))) }
            LabeledContent("终端编号", value: window.terminal).font(.footnote).foregroundStyle(.secondary)
        }.navigationTitle("窗口详情").accessibilityIdentifier("canteen.window")
    }
}
