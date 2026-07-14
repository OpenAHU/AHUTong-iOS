import SwiftUI

@MainActor
final class FreeClassroomViewModel: ObservableObject {
    @Published var selectedCampusID = 1
    @Published var buildings: [ClassroomBuilding] = []
    @Published var selectedBuildingIDs: Set<Int> = []
    @Published var selectedUnits: Set<Int> = []
    @Published var startDate = DemoDataState.referenceDate
    @Published var endDate = DemoDataState.referenceDate
    @Published private(set) var buildingsLoading = false
    @Published private(set) var rooms: LoadableState<[FreeClassroomRoom]> = .idle

    private let remote: any FreeClassroomRemote
    private let demo: Bool

    init(api: any CampusCoreAPI, demo: Bool) {
        self.demo = demo
        remote = demo ? DemoFreeClassroomRemote() : CampusFreeClassroomRemote(campusAPI: api)
        if !demo {
            startDate = Date()
            endDate = Date()
        }
    }

    func loadBuildings() async {
        buildingsLoading = true
        selectedBuildingIDs = []
        rooms = .idle
        do {
            if demo && DemoDataState.current == .error { throw CampusWebError.server("Mock 场景：获取教学楼失败") }
            buildings = try await remote.buildings(campusID: selectedCampusID)
        } catch {
            buildings = []
            rooms = .failed(AppErrorState(message: error.localizedDescription))
        }
        buildingsLoading = false
    }

    func selectCampus(_ id: Int) async {
        guard selectedCampusID != id else { return }
        selectedCampusID = id
        await loadBuildings()
    }

    func toggleBuilding(_ id: Int) {
        if selectedBuildingIDs.contains(id) { selectedBuildingIDs.remove(id) } else { selectedBuildingIDs.insert(id) }
    }

    func toggleUnit(_ unit: Int) {
        if selectedUnits.contains(unit) { selectedUnits.remove(unit) } else { selectedUnits.insert(unit) }
    }

    func toggleUnits(_ range: ClosedRange<Int>) {
        let values = Set(range)
        selectedUnits = values.isSubset(of: selectedUnits) ? selectedUnits.subtracting(values) : selectedUnits.union(values)
    }

    func search() async {
        rooms = .loading
        if demo {
            switch DemoDataState.current {
            case .loading: return
            case .empty:
                rooms = .empty
                return
            case .error:
                rooms = .failed(AppErrorState(message: "Mock 场景：接口返回 500"))
                return
            case .normal: break
            }
        }
        do {
            let result = try await remote.rooms(
                query: FreeClassroomQuery(
                    campusID: selectedCampusID,
                    buildingIDs: selectedBuildingIDs.sorted(),
                    units: selectedUnits.sorted(),
                    startDate: startDate,
                    endDate: endDate
                )
            )
            rooms = result.isEmpty ? .empty : .loaded(result)
        } catch {
            rooms = .failed(AppErrorState(message: error.localizedDescription))
        }
    }
}

struct FreeClassroomView: View {
    @Environment(\.colorScheme) private var colorScheme
    @StateObject private var model: FreeClassroomViewModel
    @State private var collapsed = false

    init(appModel: AppModel) {
        _model = StateObject(
            wrappedValue: FreeClassroomViewModel(
                api: appModel.campusAPI,
                demo: ProcessInfo.processInfo.arguments.contains("--demo-session")
            )
        )
    }

    var body: some View {
        AndroidScreen {
            ScrollView {
                VStack(spacing: 24) {
                    AndroidHeader(title: "空闲教室", large: true)
                    if !collapsed { filters.transition(.opacity.combined(with: .move(edge: .top))) }
                    searchControls
                    results
                }
                .padding(.bottom, 64)
            }
            .scrollIndicators(.hidden)
        }
        .task { await model.loadBuildings() }
        .accessibilityIdentifier("free-classroom.screen")
    }

    private var filters: some View {
        VStack(spacing: 24) {
            filterCard("选择校区") {
                chipRow {
                    ForEach(ClassroomCampus.all) { campus in
                        chip(campus.name, selected: model.selectedCampusID == campus.id) {
                            Task { await model.selectCampus(campus.id) }
                        }
                    }
                }
            }
            filterCard("选择教学楼") {
                if model.buildingsLoading {
                    ProgressView().frame(maxWidth: .infinity, alignment: .leading)
                } else if model.buildings.isEmpty {
                    Text("当前校区暂无教学楼").foregroundStyle(.secondary)
                } else {
                    chipRow {
                        ForEach(model.buildings) { building in
                            chip(building.nameZh, selected: model.selectedBuildingIDs.contains(building.id)) {
                                model.toggleBuilding(building.id)
                            }
                        }
                    }
                }
            }
            filterCard("选择节次") {
                HStack(spacing: 8) {
                    shortcut("上午", range: 1...5)
                    shortcut("下午", range: 6...10)
                    shortcut("晚上", range: 11...13)
                    Spacer()
                }
                chipRow {
                    ForEach(1...13, id: \.self) { unit in
                        chip("\(unit)节", selected: model.selectedUnits.contains(unit)) { model.toggleUnit(unit) }
                    }
                }
                Text("未选择节次时，默认按 1-13 节查询")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            filterCard("选择日期") {
                HStack(spacing: 8) {
                    datePicker("开始", selection: $model.startDate)
                    datePicker("结束", selection: $model.endDate)
                }
            }
        }
    }

    private var searchControls: some View {
        HStack(spacing: 8) {
            Button {
                Task { await model.search() }
                withAnimation { collapsed = true }
            } label: {
                Text(model.rooms.isLoading ? "查询中..." : "开始查询空闲教室")
                    .font(.headline.bold())
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
                    .background(AndroidParityPalette.brand, in: Capsule())
            }
            .buttonStyle(.plain)
            .disabled(model.rooms.isLoading || model.buildings.isEmpty)
            .accessibilityIdentifier("free-classroom.search")

            AndroidIconButton(
                systemName: collapsed ? "chevron.down" : "chevron.up",
                accessibilityLabel: collapsed ? "展开筛选条件" : "收起筛选条件"
            ) { withAnimation { collapsed.toggle() } }
            .padding(4)
            .background(AndroidParityPalette.surface(colorScheme), in: Capsule())
        }
        .padding(.horizontal, 16)
    }

    private var results: some View {
        AndroidCard(radius: 32) {
            VStack(spacing: 10) {
                HStack {
                    Text("查询结果").font(.headline)
                    Spacer()
                    Text("共 \(model.rooms.value?.count ?? 0) 间").foregroundStyle(.secondary)
                }
                switch model.rooms {
                case .idle:
                    Text("暂无数据，请先设置条件后查询").frame(maxWidth: .infinity, alignment: .leading)
                case .loading:
                    ProgressView().accessibilityIdentifier("free-classroom.loading")
                case .empty:
                    AndroidEmptyState(text: "暂无符合条件的空闲教室").accessibilityIdentifier("free-classroom.empty")
                case let .failed(error):
                    VStack(spacing: 8) {
                        Text("查询失败").font(.headline)
                        Text(error.message).font(.caption).foregroundStyle(.secondary)
                    }
                    .accessibilityIdentifier("free-classroom.error")
                case let .loaded(rooms):
                    ForEach(rooms) { room in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(room.nameZh).font(.headline)
                            Text("\(room.building.nameZh)  \(room.floor)层  \(room.remark ?? "")")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(14)
                        .background(AndroidParityPalette.background(colorScheme), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    }
                }
            }
            .padding(20)
        }
        .padding(.horizontal, 16)
    }

    private func filterCard<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        AndroidCard(radius: 32) {
            VStack(alignment: .leading, spacing: 12) {
                Text(title).font(.headline)
                content()
            }
            .padding(20)
        }
        .padding(.horizontal, 16)
    }

    private func chipRow<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) { content() }
        }
        .scrollIndicators(.hidden)
    }

    private func chip(_ text: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(text)
                .font(.subheadline)
                .foregroundStyle(selected ? Color.white : Color.primary)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(selected ? AndroidParityPalette.brand : AndroidParityPalette.background(colorScheme), in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private func shortcut(_ text: String, range: ClosedRange<Int>) -> some View {
        chip(text, selected: Set(range).isSubset(of: model.selectedUnits)) { model.toggleUnits(range) }
    }

    private func datePicker(_ title: String, selection: Binding<Date>) -> some View {
        DatePicker(title, selection: selection, displayedComponents: .date)
            .labelsHidden()
            .datePickerStyle(.compact)
    }
}
