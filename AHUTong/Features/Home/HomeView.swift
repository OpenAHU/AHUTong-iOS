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
}

@MainActor
final class HomeViewModel: ObservableObject {
    @Published private(set) var courses: [Course] = []
    @Published private(set) var currentWeek = 1
    @Published private(set) var errorMessage: String?

    private let repository: ScheduleRepository
    private let api: any CampusCoreAPI

    init(api: any CampusCoreAPI, userID: String) {
        self.api = api
        repository = ScheduleRepository(
            remote: RustScheduleRemoteDataSource(api: api),
            cache: UserScopedStore(store: UserDefaultsDataStore(), userID: userID)
        )
    }

    func load(demo: Bool) async {
        if demo {
            courses = []
            currentWeek = 1
            return
        }
        let year = Calendar.current.component(.year, from: Date())
        let semester = Semester(schoolYear: "\(year)-\(year + 1)", term: "1")!
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
        let weekday = (Calendar.current.component(.weekday, from: Date()) + 5) % 7 + 1
        return courses.filter { $0.weekday == weekday && $0.occurs(inWeek: currentWeek) }
            .sorted { $0.startPeriod < $1.startPeriod }
    }
}

struct HomeView: View {
    @Environment(\.colorScheme) private var colorScheme
    @StateObject private var weatherModel = WeatherViewModel()
    @StateObject private var model: HomeViewModel
    @State private var layout: HomeWidgetLayout
    @State private var isEditing = false
    @State private var unavailableWidgetTitle = ""
    @State private var showsUnavailableWidget = false
    private let appModel: AppModel

    init(appModel: AppModel) {
        self.appModel = appModel
        let userID: String
        if case let .authenticated(user) = appModel.sessionState { userID = user.studentID } else { userID = "guest" }
        _model = StateObject(wrappedValue: HomeViewModel(api: appModel.campusAPI, userID: userID))
        let stored = UserDefaults.standard.integer(forKey: "home.widget-layout-version") == 2
            ? UserDefaults.standard.data(forKey: "home.widget-layout")
                .flatMap { try? JSONDecoder().decode(HomeWidgetLayout.self, from: $0) }
            : nil
        _layout = State(initialValue: stored ?? HomeWidgetLayout())
    }

    var body: some View {
        AndroidScreen {
            ScrollView {
                LazyVStack(spacing: 24) {
                    atAGlance
                    if !model.todayCourses.isEmpty { todayCourseList }
                    if case let .loaded(snapshot) = weatherModel.state {
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
            .onLongPressGesture { isEditing = true }
            .overlay(alignment: .bottom) {
                if isEditing { widgetLibrary }
            }
        }
        .task {
            async let schedule: Void = model.load(demo: ProcessInfo.processInfo.arguments.contains("--demo-session"))
            async let weather: Void = weatherModel.start()
            _ = await (schedule, weather)
        }
        .onChange(of: layout) { _, newValue in
            if let data = try? JSONEncoder().encode(newValue) {
                UserDefaults.standard.set(data, forKey: "home.widget-layout")
                UserDefaults.standard.set(2, forKey: "home.widget-layout-version")
            }
        }
        .alert(unavailableWidgetTitle, isPresented: $showsUnavailableWidget) {
            Button("知道了", role: .cancel) { }
        } message: {
            Text("该写操作仍在安全整改和真机验收阶段，本轮不提供不可验证的占位支付。")
        }
    }

    private var atAGlance: some View {
        VStack(alignment: .leading, spacing: 32) {
            Text(Self.dateFormatter.string(from: Date()))
                .font(.body)
                .padding(.leading, 32)
                .padding(.trailing, 16)
                .padding(.top, 8)
            VStack(alignment: .leading, spacing: 8) {
                Text("今日课程").font(.body.bold()).accessibilityIdentifier("screen.home")
                Text(headline).font(.system(size: 40, weight: .bold)).lineLimit(2)
                Text(subheadline).font(.body).lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 32)
        }
    }

    private var headline: String {
        guard let next = model.todayCourses.first else { return "已全部上完" }
        return next.name
    }

    private var subheadline: String {
        guard let next = model.todayCourses.first else { return "准备您自己的安排吧" }
        return "第 \(next.startPeriod)-\(next.endPeriod) 节 · \(shortLocation(next.location))"
    }

    @ViewBuilder
    private var todayCourseList: some View {
        AndroidCard(radius: 32, background: AndroidParityPalette.surface(colorScheme)) {
            VStack(alignment: .leading, spacing: 16) {
                if model.todayCourses.isEmpty {
                    Text("今天暂无课程").font(.headline)
                    Text(model.errorMessage ?? "点击课表查看完整安排")
                        .font(.body).foregroundStyle(.secondary)
                } else {
                    ForEach(model.todayCourses) { course in
                        HStack(spacing: 16) {
                            Text("\(course.startPeriod) - \(course.endPeriod)").frame(width: 52, alignment: .leading)
                            Text(course.name).fontWeight(.medium).lineLimit(1)
                            Spacer()
                            Text(shortLocation(course.location)).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }
                }
            }
            .padding(16)
        }
        .padding(.horizontal, 16)
        .accessibilityIdentifier("home.today-courses")
    }

    private var homeWidgetLayout: some View {
        VStack(spacing: 16) {
            HStack(spacing: 16) {
                CampusCardPanel(api: appModel.campusAPI, userID: userID, demo: demo)
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
        .accessibilityIdentifier("home.widget-grid")
    }

    @ViewBuilder
    private func homeSlot(index: Int, height: CGFloat) -> some View {
        if let id = layout.slots[index], let spec = HomeWidgetSpec.all.first(where: { $0.id == id }) {
            Group {
                if spec.id == "bathroom" || spec.id == "electricity" {
                    Button {
                        unavailableWidgetTitle = spec.title
                        showsUnavailableWidget = true
                    } label: {
                        HomeTextWidgetCard(title: spec.title, isEditing: isEditing)
                    }
                    .buttonStyle(.plain)
                } else {
                    widgetDestination(spec: spec) {
                        HomeTextWidgetCard(title: spec.title, isEditing: isEditing)
                    }
                }
            }
            .frame(maxWidth: .infinity, minHeight: height, maxHeight: height)
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
            .accessibilityLabel("空白小工具槽位 \(index + 1)")
        }
    }

    private var userID: String {
        if case let .authenticated(user) = appModel.sessionState { return user.studentID }
        return "guest"
    }

    private var demo: Bool { ProcessInfo.processInfo.arguments.contains("--demo-session") }

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
        switch spec.id {
        case "grade": NavigationLink { GradeView(appModel: appModel).androidDetailScreen() } label: { label() }.buttonStyle(.plain)
        case "exam": NavigationLink { ExamView(appModel: appModel).androidDetailScreen() } label: { label() }.buttonStyle(.plain)
        case "phone_book": NavigationLink { PhoneBookView().androidDetailScreen() } label: { label() }.buttonStyle(.plain)
        case "school_calendar": NavigationLink { SchoolCalendarView().androidDetailScreen() } label: { label() }.buttonStyle(.plain)
        case "weather": NavigationLink { WeatherView().androidDetailScreen() } label: { label() }.buttonStyle(.plain)
        case "repository": NavigationLink { StudyRepositoryView().androidDetailScreen() } label: { label() }.buttonStyle(.plain)
        default: label()
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
