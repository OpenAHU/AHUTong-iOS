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
        HomeWidgetSpec(id: "evaluation", title: "教评", systemImage: "list.bullet.rectangle.fill", tintHex: 0x0D9488),
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

enum HomeCourseTimelineState: Equatable, Sendable {
    case completed
    case ongoing
    case upcoming
}

enum HomeCourseTimeline {
    static func states(
        for courses: [Course],
        now: Date,
        calendar: Calendar = .current
    ) -> [HomeCourseTimelineState] {
        let components = calendar.dateComponents([.hour, .minute], from: now)
        let currentMinutes = (components.hour ?? 0) * 60 + (components.minute ?? 0)
        return courses.map { course in
            let range = HomeCourseSummary.range(for: course)
            if range.contains(currentMinutes) { return .ongoing }
            if currentMinutes > range.upperBound { return .completed }
            return .upcoming
        }
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
    @AppStorage("weather.show-on-home") private var showWeatherOnHome = false
    @AppStorage("weather.home.mode") private var weatherHomeMode = WeatherHomeMode.detailed.rawValue
    @AppStorage("weather.home.show-location") private var weatherHomeShowsLocation = true
    @AppStorage("weather.home.show-temperature") private var weatherHomeShowsTemperature = true
    @AppStorage("weather.home.show-condition") private var weatherHomeShowsCondition = true
    @AppStorage("weather.home.show-air-quality") private var weatherHomeShowsAirQuality = true
    @AppStorage private var prefersCMBCardRecharge: Bool
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
        _prefersCMBCardRecharge = AppStorage(
            wrappedValue: false,
            AccountPreferenceKey.make("payment.cmb-card-recharge-preferred", userID: userID)
        )
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
                    if effectiveShowWeatherOnHome,
                       effectiveWeatherHomeMode == .detailed,
                       case let .loaded(snapshot) = weatherModel.state {
                        NavigationLink { WeatherView().androidDetailScreen() } label: {
                            HomeWeatherCard(weather: snapshot.response, configuration: weatherHomeConfiguration)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("home.weather")
                    }
                    homeWidgetLayout
                }
                .padding(.bottom, isEditing ? 420 : 16)
            }
            .scrollIndicators(.hidden)
            .onLongPressGesture { if homeEditEnabled { isEditing = true } }
            .overlay(alignment: .bottom) {
                if isEditing { widgetLibrary }
            }
        }
        .navigationDestination(isPresented: $showsCardRecharge) {
            if prefersCMBCardRecharge {
                CMBRechargeView(appModel: appModel).androidDetailScreen()
            } else {
                CardRechargeView(appModel: appModel).androidDetailScreen()
            }
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
        VStack(alignment: .leading, spacing: 32) {
            HStack(spacing: 12) {
                Text(Self.dateFormatter.string(from: model.referenceDate))
                    .font(.body)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if effectiveShowWeatherOnHome,
                   effectiveWeatherHomeMode == .compact,
                   case let .loaded(snapshot) = weatherModel.state {
                    NavigationLink {
                        WeatherView().androidDetailScreen()
                    } label: {
                        CompactHomeWeatherCard(weather: snapshot.response)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("home.weather.compact")
                }
            }
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
            .contentShape(Rectangle())
            .onTapGesture(perform: onOpenSchedule)
            .accessibilityHint("打开完整课表")
        }
    }

    @ViewBuilder
    private var todayCourseList: some View {
        Button(action: onOpenSchedule) {
            AndroidCard(radius: 32, background: AndroidParityPalette.surface(colorScheme)) {
                let states = HomeCourseTimeline.states(
                    for: model.todayCourses,
                    now: model.referenceDate
                )
                VStack(alignment: .leading, spacing: 0) {
                    if model.todayCourses.isEmpty {
                        Text("今天暂无课程").font(.headline)
                        Text(model.errorMessage ?? "点击课表查看完整安排")
                            .font(.body).foregroundStyle(.secondary)
                    } else {
                        ForEach(model.todayCourses.indices, id: \.self) { index in
                            let course = model.todayCourses[index]
                            let state = states[index]
                            HStack(spacing: 16) {
                                HomeCourseTimelineIndicator(
                                    state: state,
                                    isFirst: index == model.todayCourses.startIndex,
                                    isLast: index == model.todayCourses.index(before: model.todayCourses.endIndex)
                                )
                                Text("\(course.startPeriod) - \(course.endPeriod)")
                                    .frame(width: 52, alignment: .leading)
                                Text(course.name)
                                    .fontWeight(state == .ongoing ? .bold : .medium)
                                    .lineLimit(1)
                                Spacer()
                                Text(shortLocation(course.location))
                                    .foregroundStyle(state == .ongoing ? .primary : .secondary)
                                    .lineLimit(1)
                            }
                            .frame(minHeight: 40)
                            .padding(.horizontal, 8)
                            .background(
                                state == .ongoing
                                    ? AndroidParityPalette.primaryContainer(colorScheme)
                                    : .clear,
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
        .padding(.horizontal, 16)
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

    private var weatherHomeConfiguration: WeatherHomeConfiguration {
        WeatherHomeConfiguration(
            showOnHome: effectiveShowWeatherOnHome,
            mode: effectiveWeatherHomeMode,
            showLocation: weatherHomeShowsLocation,
            showTemperature: weatherHomeShowsTemperature,
            showCondition: weatherHomeShowsCondition,
            showAirQuality: weatherHomeShowsAirQuality
        )
    }

    private var demoForcesCompactWeather: Bool {
        AppRuntime.isDemoSession
            && ProcessInfo.processInfo.arguments.contains("--demo-weather-compact")
    }

    private var effectiveShowWeatherOnHome: Bool {
        showWeatherOnHome || demoForcesCompactWeather
    }

    private var effectiveWeatherHomeMode: WeatherHomeMode {
        demoForcesCompactWeather
            ? .compact
            : WeatherHomeMode.resolve(weatherHomeMode)
    }

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
            case "evaluation": NavigationLink { EvaluationView(appModel: appModel).androidDetailScreen() } label: { label() }.buttonStyle(.plain)
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

private struct HomeCourseTimelineIndicator: View {
    let state: HomeCourseTimelineState
    let isFirst: Bool
    let isLast: Bool

    private let active = Color(red: 100 / 255, green: 122 / 255, blue: 190 / 255)

    var body: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(state == .upcoming ? Color.secondary.opacity(0.4) : active)
                .frame(width: state == .upcoming ? 1 : 2)
                .opacity(isFirst ? 0 : 1)
            Group {
                if state == .upcoming {
                    Circle()
                        .stroke(Color.secondary.opacity(0.65), lineWidth: 2)
                } else {
                    Circle().fill(active)
                }
            }
            .frame(width: state == .ongoing ? 10 : 8, height: state == .ongoing ? 10 : 8)
            Rectangle()
                .fill(state == .completed ? active : Color.secondary.opacity(0.4))
                .frame(width: state == .completed ? 2 : 1)
                .opacity(isLast ? 0 : 1)
        }
        .frame(width: 12, height: 40)
        .accessibilityHidden(true)
    }
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
    let configuration: WeatherHomeConfiguration

    var body: some View {
        AndroidCard(radius: 20, background: AndroidParityPalette.primaryContainer(colorScheme)) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    if configuration.showLocation {
                        Text(weather.locationName).font(.caption).foregroundStyle(.secondary)
                    }
                    HStack(alignment: .bottom, spacing: 8) {
                        if configuration.showTemperature {
                            Text(weather.temperature.map { "\(Int($0.rounded()))°" } ?? "--")
                                .font(.system(size: 32, weight: .light))
                        }
                        if configuration.showCondition {
                            Text(weather.weather ?? "").font(.body)
                        }
                    }
                    Text(HomeWeatherPresentation.detail(
                        weather: weather,
                        showsAirQuality: configuration.showAirQuality
                    ))
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

private struct CompactHomeWeatherCard: View {
    let weather: WeatherResponse

    var body: some View {
        HStack(spacing: 6) {
            Text(HomeWeatherPresentation.glyph(weather))
                .font(.system(size: 19))
            VStack(alignment: .leading, spacing: 0) {
                Text(weather.temperature.map { "\(Int($0.rounded()))°" } ?? "--°")
                    .font(.system(size: 17, weight: .bold))
                Text(weather.weather ?? "天气")
                    .font(.caption2)
                    .lineLimit(1)
            }
            VStack(alignment: .trailing, spacing: 0) {
                ForEach(HomeWeatherPresentation.metricLines(weather), id: \.self) {
                    Text($0).font(.system(size: 10, weight: .medium)).lineLimit(1)
                }
            }
        }
        .padding(.horizontal, 10)
        .frame(minWidth: 154, maxWidth: 178, minHeight: 44, maxHeight: 44)
        .background(Color.primary.opacity(0.055), in: RoundedRectangle(cornerRadius: 18))
    }
}

enum HomeWeatherPresentation {
    static func detail(weather: WeatherResponse, showsAirQuality: Bool) -> String {
        let wind = "\(weather.windDirection ?? "") \(weather.windPower ?? "")"
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard showsAirQuality else { return wind }
        return "\(wind)\(wind.isEmpty ? "" : " · ")空气\(weather.aqi.map(String.init) ?? "--")"
    }

    static func metricLines(_ weather: WeatherResponse) -> [String] {
        let nextSix = Array((weather.hourlyForecast ?? []).prefix(6))
        let probability = nextSix.compactMap(\.probabilityOfPrecipitation).max()
        let rainWords = ["雨", "雪", "雹"]
        let hasRain = [weather.weather, weather.forecast?.first?.weatherDay, weather.forecast?.first?.weatherNight]
            .compactMap { $0 }
            .contains { value in rainWords.contains { value.contains($0) } }
            || nextSix.contains { hour in
                guard let value = hour.weather else { return false }
                return rainWords.contains { value.contains($0) }
            }
        let rain = probability.map { "雨 \($0)%" } ?? (hasRain ? "雨 --" : nil)
        let ultraviolet = weather.ultraviolet.map { "UV \(Int($0.rounded()))" }
            ?? weather.hourlyForecast?.first?.ultravioletIndex.map { "UV \($0)" }
            ?? weather.forecast?.first?.ultravioletIndex.map { "UV \($0)" }
        let fallback = weather.humidity.map { "湿 \($0)%" } ?? weather.windPower.map { "风 \($0)" }
        return [rain, ultraviolet, fallback].compactMap { $0 }.prefix(2).map { $0 }
    }

    static func glyph(_ weather: WeatherResponse) -> String {
        let code = Int(weather.weatherCode ?? weather.weatherIcon ?? "")
        let text = weather.weather ?? ""
        if (code.map { [100, 150].contains($0) } ?? false) || text.contains("晴") { return "☀" }
        if (code.map { (101...103).contains($0) || (151...153).contains($0) } ?? false)
            || ["多云", "少云", "云"].contains(where: text.contains) { return "⛅" }
        if (code.map { [104, 154].contains($0) } ?? false) || text.contains("阴") { return "☁" }
        if (code.map { (300...399).contains($0) } ?? false)
            || ["雨", "雹"].contains(where: text.contains) { return "☔" }
        if (code.map { (400...499).contains($0) } ?? false) || text.contains("雪") { return "❄" }
        if (code.map { (500...515).contains($0) } ?? false)
            || ["雾", "霾", "沙", "尘"].contains(where: text.contains) { return "≋" }
        if (code.map { (200...213).contains($0) } ?? false) || text.contains("风") { return "↝" }
        return "☁"
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
