import SwiftUI

struct HomeWidgetSpec: Identifiable, Codable, Equatable, Sendable {
    let id: String
    let title: String
    let systemImage: String
    let tintHex: UInt

    static let all = [
        HomeWidgetSpec(id: "bathroom", title: "浴室缴费", systemImage: "shower.fill", tintHex: 0x26A69A),
        HomeWidgetSpec(id: "electricity", title: "电控缴费", systemImage: "bolt.fill", tintHex: 0xFFB300),
        HomeWidgetSpec(id: "grade", title: "成绩单", systemImage: "chart.bar.doc.horizontal.fill", tintHex: 0xFFC107),
        HomeWidgetSpec(id: "phone_book", title: "电话本", systemImage: "phone.fill", tintHex: 0x009688),
        HomeWidgetSpec(id: "exam", title: "考场查询", systemImage: "pencil.and.list.clipboard", tintHex: 0x4CAF50),
        HomeWidgetSpec(id: "school_calendar", title: "校历", systemImage: "calendar", tintHex: 0x9C27B0),
        HomeWidgetSpec(id: "free_classroom", title: "空闲教室", systemImage: "building.2.fill", tintHex: 0x03A9F4),
        HomeWidgetSpec(id: "lost_found", title: "失物招领", systemImage: "shippingbox.fill", tintHex: 0x1976D2),
        HomeWidgetSpec(id: "weather", title: "天气", systemImage: "cloud.sun.fill", tintHex: 0xFFB300),
        HomeWidgetSpec(id: "repository", title: "学习资料", systemImage: "folder.fill", tintHex: 0x8D6E63)
    ]
}

struct HomeWidgetLayout: Codable, Equatable, Sendable {
    static let slotCount = 8
    private(set) var slots: [String?]

    init(slots: [String?] = ["bathroom", "electricity", nil, nil, nil, nil, nil, nil]) {
        let known = Set(HomeWidgetSpec.all.map(\.id))
        var seen: Set<String> = []
        self.slots = (0..<Self.slotCount).map { index in
            guard let value = slots[safe: index] ?? nil,
                  known.contains(value), seen.insert(value).inserted else { return nil }
            return value
        }
    }

    mutating func add(_ id: String) {
        guard HomeWidgetSpec.all.contains(where: { $0.id == id }), !slots.contains(id),
              let index = slots.firstIndex(where: { $0 == nil }) else { return }
        slots[index] = id
    }

    mutating func remove(at index: Int) {
        guard slots.indices.contains(index) else { return }
        slots[index] = nil
    }

    mutating func move(from source: Int, to destination: Int) {
        guard slots.indices.contains(source), slots.indices.contains(destination) else { return }
        slots.swapAt(source, destination)
    }

    mutating func place(_ id: String, at destination: Int) {
        guard slots.indices.contains(destination),
              HomeWidgetSpec.all.contains(where: { $0.id == id }) else { return }
        if let source = slots.firstIndex(where: { $0 == id }) {
            move(from: source, to: destination)
        } else if slots[destination] == nil {
            slots[destination] = id
        }
    }
}

struct HomeCourseSummary: Equatable {
    let title: String
    let headline: String
    let detail: String
    let focusedCourseID: String?

    static func make(courses: [Course], now: Date, calendar: Calendar = .current) -> Self {
        let components = calendar.dateComponents([.hour, .minute], from: now)
        let currentMinutes = (components.hour ?? 0) * 60 + (components.minute ?? 0)
        let current = courses.first { range(for: $0).contains(currentMinutes) }
        let next = courses.first { currentMinutes < range(for: $0).lowerBound }
        let focused = current ?? next

        guard let focused else {
            return Self(title: "今日课程", headline: "已全部上完", detail: "准备您自己的安排吧", focusedCourseID: nil)
        }

        if current != nil {
            let duration = range(for: focused).upperBound - currentMinutes
            return Self(
                title: "正在上课",
                headline: focused.name,
                detail: "距下课还有 \(durationText(duration))",
                focusedCourseID: focused.courseID
            )
        }

        let duration = range(for: focused).lowerBound - currentMinutes
        return Self(
            title: "下节课是",
            headline: focused.name,
            detail: "还有 \(durationText(duration))，在 \(focused.location)",
            focusedCourseID: focused.courseID
        )
    }

    static func range(for course: Course) -> ClosedRange<Int> {
        let start = timetable[course.startPeriod]?.lowerBound ?? 0
        let end = timetable[course.endPeriod]?.upperBound ?? start
        return start...end
    }

    private static let timetable: [Int: ClosedRange<Int>] = [
        1: 480...525, 2: 530...575, 3: 590...635, 4: 640...685,
        5: 690...735, 6: 840...885, 7: 890...935, 8: 950...995,
        9: 1_000...1_045, 10: 1_050...1_095, 11: 1_140...1_185,
        12: 1_190...1_235, 13: 1_240...1_285
    ]

    private static func durationText(_ minutes: Int) -> String {
        if minutes.isMultiple(of: 60) { return "\(minutes / 60)小时整" }
        if minutes > 60 { return "\(minutes / 60)小时\(minutes % 60)分钟" }
        return "\(minutes)分钟"
    }
}

@MainActor
final class HomeViewModel: ObservableObject {
    @Published private(set) var courses: [Course] = []
    @Published private(set) var currentWeek = 1
    @Published private(set) var errorMessage: String?
    @Published private(set) var referenceDate = Date()

    private let repository: ScheduleRepository
    private let api: any CampusCoreAPI

    init(api: any CampusCoreAPI, userID: String) {
        self.api = api
        repository = ScheduleRepository(
            remote: RustScheduleRemoteDataSource(api: api),
            cache: UserScopedStore(store: AppPersistence.migratingDefaults(), userID: userID)
        )
    }

    func load(demo: Bool) async {
        if demo {
            courses = DemoDataState.current == .normal ? ScheduleViewModel.demoCourses : []
            currentWeek = 1
            referenceDate = DemoDataState.referenceDate
            return
        }
        let semester = Semester.current()
        do {
            async let snapshot = repository.load(semester: semester)
            async let week = api.currentWeek()
            let result = try await snapshot
            courses = result.courses
            currentWeek = (try? await week) ?? 1
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    var todayCourses: [Course] {
        let weekday = (Calendar.current.component(.weekday, from: referenceDate) + 5) % 7 + 1
        return courses.filter { $0.weekday == weekday && $0.occurs(inWeek: currentWeek) }
            .sorted { $0.startPeriod < $1.startPeriod }
    }

    var summary: HomeCourseSummary {
        HomeCourseSummary.make(courses: todayCourses, now: referenceDate)
    }
}

struct HomeView: View {
    @Environment(\.colorScheme) private var colorScheme
    @StateObject private var weatherModel = WeatherViewModel()
    @StateObject private var model: HomeViewModel
    @State private var layout: HomeWidgetLayout
    @State private var isEditing = false
    @AppStorage("home.request-edit") private var requestEdit = false
    @AppStorage("weather.show-on-home") private var showWeatherOnHome = true
    @State private var showsCardRecharge = false
    private let appModel: AppModel
    private let layoutStore: JSONStore<HomeWidgetLayout>
    private let onOpenSchedule: () -> Void
    private let homeEditEnabled: Bool

    init(
        appModel: AppModel,
        homeEditEnabled: Bool = true,
        onOpenSchedule: @escaping () -> Void = {}
    ) {
        self.appModel = appModel
        self.homeEditEnabled = homeEditEnabled
        self.onOpenSchedule = onOpenSchedule
        let userID: String
        if case let .authenticated(user) = appModel.sessionState { userID = user.studentID } else { userID = "guest" }
        _model = StateObject(wrappedValue: HomeViewModel(api: appModel.campusAPI, userID: userID))
        layoutStore = JSONStore(
            store: UserScopedStore(store: AppPersistence.migratingDefaults(), userID: userID),
            key: "home.widget-layout.v2"
        )
        _layout = State(initialValue: HomeWidgetLayout())
    }

    var body: some View {
        AndroidScreen {
            ScrollView {
                LazyVStack(spacing: 24) {
                    atAGlance
                    if !model.todayCourses.isEmpty { todayCourseList }
                    if showWeatherOnHome, case let .loaded(snapshot) = weatherModel.state {
                        NavigationLink { WeatherView().androidDetailScreen() } label: {
                            HomeWeatherCard(weather: snapshot.response)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("home.weather")
                    }
                    homeWidgetLayout
                }
                .padding(.bottom, isEditing ? 420 : 96)
            }
            .scrollIndicators(.hidden)
            .onLongPressGesture { if homeEditEnabled { isEditing = true } }
            .overlay(alignment: .bottom) {
                if isEditing { widgetLibrary }
            }
        }
        .navigationDestination(isPresented: $showsCardRecharge) {
            CardRechargeView(appModel: appModel).androidDetailScreen()
        }
        .task {
            await loadLayout()
            async let schedule: Void = model.load(demo: AppRuntime.isDemoSession)
            async let weather: Void = weatherModel.start()
            _ = await (schedule, weather)
        }
        .onChange(of: layout) { _, newValue in
            Task { try? await layoutStore.save(newValue) }
        }
        .onAppear {
            if requestEdit && homeEditEnabled {
                isEditing = true
                requestEdit = false
            }
        }
    }

    private var atAGlance: some View {
        Button(action: onOpenSchedule) {
            VStack(alignment: .leading, spacing: 32) {
            Text(Self.dateFormatter.string(from: model.referenceDate))
                .font(.body)
                .padding(.leading, 32)
                .padding(.trailing, 16)
                .padding(.top, 8)
            VStack(alignment: .leading, spacing: 8) {
                Text(model.summary.title).font(.body.bold()).accessibilityIdentifier("screen.home")
                Text(model.summary.headline)
                    .font(.system(size: 40, weight: .bold)).lineLimit(2)
                    .padding(.leading, model.summary.focusedCourseID == nil ? 0 : 8)
                    .overlay(alignment: .leading) {
                        if model.summary.focusedCourseID != nil {
                            Rectangle().fill(Color(red: 100 / 255, green: 122 / 255, blue: 190 / 255)).frame(width: 4)
                        }
                    }
                Text(model.summary.detail).font(.body).lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 32)
            }
        }
        .buttonStyle(.plain)
        .accessibilityHint("打开完整课表")
    }

    @ViewBuilder
    private var todayCourseList: some View {
        Button(action: onOpenSchedule) {
            AndroidCard(radius: 32, background: AndroidParityPalette.surface(colorScheme)) {
            VStack(alignment: .leading, spacing: 16) {
                if model.todayCourses.isEmpty {
                    Text("今天暂无课程").font(.headline)
                    Text(model.errorMessage ?? "点击课表查看完整安排")
                        .font(.body).foregroundStyle(.secondary)
                } else {
                    ForEach(model.todayCourses) { course in
                        let isFocused = model.summary.focusedCourseID == course.courseID
                        HStack(spacing: 16) {
                            Circle()
                                .fill(Color(red: 100 / 255, green: 122 / 255, blue: 190 / 255))
                                .frame(width: isFocused ? 8 : 4, height: isFocused ? 8 : 4)
                            Text("\(course.startPeriod) - \(course.endPeriod)").frame(width: 52, alignment: .leading)
                            Text(course.name).fontWeight(isFocused ? .bold : .medium).lineLimit(1)
                            Spacer()
                            Text(shortLocation(course.location)).foregroundStyle(.secondary).lineLimit(1)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 12)
                        .background(
                            isFocused ? AndroidParityPalette.primaryContainer(colorScheme) : .clear,
                            in: Capsule()
                        )
                    }
                }
            }
            .padding(16)
            }
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 16)
        .accessibilityIdentifier("home.today-courses")
    }

    private var homeWidgetLayout: some View {
        VStack(spacing: 16) {
            HStack(alignment: .top, spacing: 16) {
                CampusCardPanel(api: appModel.campusAPI, userID: userID, demo: demo) {
                    showsCardRecharge = true
                }
                    .frame(maxWidth: .infinity)

                if isEditing || layout.slots[0] != nil || layout.slots[1] != nil {
                    VStack(spacing: 8) {
                        homeSlot(index: 0, height: 66)
                        homeSlot(index: 1, height: 66)
                    }
                    .frame(width: 132)
                }
            }

            ForEach([2, 4, 6], id: \.self) { index in
                if isEditing || layout.slots[index] != nil || layout.slots[index + 1] != nil {
                    HStack(spacing: 16) {
                        homeSlot(index: index, height: 76)
                        homeSlot(index: index + 1, height: 76)
                    }
                }
            }
        }
        .padding(.horizontal, 32)
    }

    @ViewBuilder
    private func homeSlot(index: Int, height: CGFloat) -> some View {
        if let id = layout.slots[index], let spec = HomeWidgetSpec.all.first(where: { $0.id == id }) {
            Group {
                if spec.id == "bathroom" {
                    NavigationLink {
                        BathroomPaymentView(appModel: appModel).androidDetailScreen()
                    } label: {
                        HomeTextWidgetCard(title: spec.title, isEditing: isEditing)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("home.payment.bathroom")
                } else if spec.id == "electricity" {
                    NavigationLink {
                        ElectricityPaymentView(appModel: appModel).androidDetailScreen()
                    } label: {
                        HomeTextWidgetCard(title: spec.title, isEditing: isEditing)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("home.payment.electricity")
                } else {
                    widgetDestination(spec: spec) {
                        HomeTextWidgetCard(title: spec.title, isEditing: isEditing)
                    }
                }
            }
            .frame(maxWidth: .infinity, minHeight: height, maxHeight: height)
            .draggable(spec.id)
            .dropDestination(for: String.self) { items, _ in
                guard let id = items.first else { return false }
                layout.place(id, at: index)
                return true
            }
            .contextMenu {
                if isEditing { Button("移除", role: .destructive) { layout.remove(at: index) } }
            }
        } else if isEditing {
            Button { isEditing = true } label: {
                RoundedRectangle(cornerRadius: 24)
                    .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [8, 6]))
                    .foregroundStyle(.secondary)
                    .overlay { Text("拖到这里").font(.caption) }
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity, minHeight: height, maxHeight: height)
            .dropDestination(for: String.self) { items, _ in
                guard let id = items.first else { return false }
                layout.place(id, at: index)
                return true
            }
            .accessibilityLabel("空白小工具槽位 \(index + 1)")
        }
    }

    private var userID: String {
        if case let .authenticated(user) = appModel.sessionState { return user.studentID }
        return "guest"
    }

    private var demo: Bool { AppRuntime.isDemoSession }

    private var widgetLibrary: some View {
        VStack(alignment: .leading, spacing: 12) {
            Capsule().fill(.secondary).frame(width: 42, height: 4).frame(maxWidth: .infinity)
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("添加小工具").font(.title3.bold())
                    Text("此操作仅隐藏图标，您随时可以从小工具中重新添加。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("完成") { isEditing = false }
            }
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(HomeWidgetSpec.all.filter { !layout.slots.contains($0.id) }) { spec in
                        Button { layout.add(spec.id) } label: { HomeWidgetCard(spec: spec, compact: true) }
                            .buttonStyle(.plain)
                            .draggable(spec.id)
                    }
                }
            }
            .scrollIndicators(.hidden)
        }
        .padding(16)
        .background(AndroidParityPalette.raisedSurface(colorScheme), in: RoundedRectangle(cornerRadius: 32))
        .padding(.horizontal, 12)
        .padding(.bottom, 88)
        .accessibilityIdentifier("home.widget-library")
    }

    @ViewBuilder
    private func widgetDestination<Label: View>(spec: HomeWidgetSpec, @ViewBuilder label: () -> Label) -> some View {
        Group {
            switch spec.id {
            case "grade": NavigationLink { GradeView(appModel: appModel).androidDetailScreen() } label: { label() }.buttonStyle(.plain)
            case "exam": NavigationLink { ExamView(appModel: appModel).androidDetailScreen() } label: { label() }.buttonStyle(.plain)
            case "phone_book": NavigationLink { PhoneBookView().androidDetailScreen() } label: { label() }.buttonStyle(.plain)
            case "school_calendar": NavigationLink { SchoolCalendarView().androidDetailScreen() } label: { label() }.buttonStyle(.plain)
            case "weather": NavigationLink { WeatherView().androidDetailScreen() } label: { label() }.buttonStyle(.plain)
            case "repository": NavigationLink { StudyRepositoryView().androidDetailScreen() } label: { label() }.buttonStyle(.plain)
            case "free_classroom": NavigationLink { FreeClassroomView(appModel: appModel).androidDetailScreen() } label: { label() }.buttonStyle(.plain)
            case "lost_found": NavigationLink { LostFoundView(appModel: appModel).androidDetailScreen() } label: { label() }.buttonStyle(.plain)
            default: label()
            }
        }
        .accessibilityIdentifier("home.widget.\(spec.id)")
    }

    private func loadLayout() async {
        if let stored = try? await layoutStore.load() {
            layout = stored
            return
        }
        let defaults = UserDefaults.standard
        if defaults.integer(forKey: "home.widget-layout-version") == 2,
           let data = defaults.data(forKey: "home.widget-layout"),
           let legacy = try? JSONDecoder().decode(HomeWidgetLayout.self, from: data) {
            layout = legacy
            try? await layoutStore.save(legacy)
            defaults.removeObject(forKey: "home.widget-layout")
            defaults.removeObject(forKey: "home.widget-layout-version")
        }
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "zh_CN"); formatter.dateFormat = "MM-dd / EE"; return formatter
    }()
}

private struct HomeWidgetCard: View {
    let spec: HomeWidgetSpec
    var isEditing = false
    var compact = false

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: spec.systemImage).font(.system(size: compact ? 28 : 34)).foregroundStyle(Color(hex: spec.tintHex))
            Text(spec.title).font(.headline).lineLimit(1)
        }
        .frame(width: compact ? 88 : nil, height: compact ? 88 : 112)
        .frame(maxWidth: compact ? nil : .infinity)
        .background(Color.primary.opacity(0.055), in: RoundedRectangle(cornerRadius: compact ? 18 : 24))
        .rotationEffect(.degrees(isEditing ? -0.7 : 0))
    }
}

private struct HomeTextWidgetCard: View {
    @Environment(\.colorScheme) private var colorScheme
    let title: String
    let isEditing: Bool

    var body: some View {
        Text(title)
            .font(.headline.bold())
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 16)
            .background(AndroidParityPalette.surface(colorScheme), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .rotationEffect(.degrees(isEditing ? -0.7 : 0))
    }
}

private struct HomeWeatherCard: View {
    @Environment(\.colorScheme) private var colorScheme
    let weather: WeatherResponse

    var body: some View {
        AndroidCard(radius: 20, background: AndroidParityPalette.primaryContainer(colorScheme)) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(weather.locationName).font(.caption).foregroundStyle(.secondary)
                    HStack(alignment: .bottom, spacing: 8) {
                        Text(weather.temperature.map { "\(Int($0.rounded()))°" } ?? "--").font(.system(size: 32, weight: .light))
                        Text(weather.weather ?? "").font(.body)
                    }
                    Text("\(weather.windDirection ?? "") \(weather.windPower ?? "") · 空气\(weather.aqi.map(String.init) ?? "--")")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "cloud.sun.fill").font(.system(size: 34)).foregroundStyle(.orange)
            }
            .padding(16)
        }
        .padding(.horizontal, 16)
    }
}

private func shortLocation(_ value: String) -> String {
    value.replacingOccurrences(of: "博学北楼", with: "博北")
        .replacingOccurrences(of: "博学南楼", with: "博南")
        .replacingOccurrences(of: "笃行北楼", with: "笃北")
        .replacingOccurrences(of: "笃行南楼", with: "笃南")
        .replacingOccurrences(of: "互联大楼", with: "互楼")
}

private extension Array {
    subscript(safe index: Index) -> Element? { indices.contains(index) ? self[index] : nil }
}

private extension Color {
    init(hex: UInt) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
    }
}
