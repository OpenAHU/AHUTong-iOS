import SwiftUI
import WidgetKit

struct ScheduleWeekNavigation {
    static let validWeeks = 1...20

    static func clamped(_ week: Int) -> Int {
        min(max(week, validWeeks.lowerBound), validWeeks.upperBound)
    }

    static func courseIdentifier(courseID: String, week: Int, selectedWeek: Int) -> String {
        week == selectedWeek
            ? "schedule.course.\(courseID)"
            : "schedule.course.\(courseID).week.\(week)"
    }
}

struct ScheduleOverviewGroup: Equatable, Identifiable {
    let weekday: Int
    let startPeriod: Int
    let duration: Int
    let courses: [Course]

    var id: String { "\(weekday)-\(startPeriod)-\(duration)" }
}

enum ScheduleOverviewLayout {
    private struct Slot: Hashable {
        let weekday: Int
        let startPeriod: Int
        let duration: Int
    }

    static func groups(for courses: [Course]) -> [ScheduleOverviewGroup] {
        Dictionary(grouping: courses) {
            Slot(weekday: $0.weekday, startPeriod: $0.startPeriod, duration: $0.duration)
        }
        .map { slot, courses in
            ScheduleOverviewGroup(
                weekday: slot.weekday,
                startPeriod: slot.startPeriod,
                duration: slot.duration,
                courses: courses.sorted {
                    if $0.startWeek != $1.startWeek { return $0.startWeek < $1.startWeek }
                    if $0.endWeek != $1.endWeek { return $0.endWeek < $1.endWeek }
                    return $0.name.localizedStandardCompare($1.name) == .orderedAscending
                }
            )
        }
        .sorted {
            if $0.weekday != $1.weekday { return $0.weekday < $1.weekday }
            if $0.startPeriod != $1.startPeriod { return $0.startPeriod < $1.startPeriod }
            return $0.duration < $1.duration
        }
    }
}

@MainActor
final class ScheduleViewModel: ObservableObject {
    @Published private(set) var state: LoadableState<[Course]> = .idle
    @Published private(set) var currentWeek = 1
    @Published private(set) var source: ScheduleSnapshotSource?

    private let currentRepository: ScheduleRepository
    private let nextRepository: ScheduleRepository
    private let api: any CampusCoreAPI
    private let semester: Semester

    init(api: any CampusCoreAPI, userID: String) {
        self.api = api
        let store = AppPersistence.migratingDefaults()
        let scopedStore = UserScopedStore(store: store, userID: userID)
        currentRepository = ScheduleRepository(
            remote: RustScheduleRemoteDataSource(api: api),
            cache: scopedStore
        )
        nextRepository = ScheduleRepository(
            remote: RustScheduleRemoteDataSource(api: api, scope: .next),
            cache: scopedStore
        )
        semester = Semester.current()
    }

    func load(demo: Bool = false, previewNext: Bool = false) async {
        if demo {
            currentWeek = 1
            switch DemoDataState.current {
            case .normal:
                let fallback = previewNext ? Self.demoNextSemesterCourses : Self.demoCourses
                let courses = DebugRuntimeSettings.decode("schedule", as: [Course].self) ?? fallback
                state = courses.isEmpty ? .empty : .loaded(courses)
                if !previewNext {
                    await updateSystemIntegrations(courses: courses, referenceDate: DemoDataState.referenceDate)
                }
            case .loading: state = .loading
            case .empty:
                state = .empty
                if !previewNext {
                    await updateSystemIntegrations(courses: [], referenceDate: DemoDataState.referenceDate)
                }
            case .error:
                state = .failed(AppErrorState(message: "Mock 场景：接口返回 500"))
                if !previewNext { await publishWidget(.unavailable(.expired, updatedAt: DemoDataState.referenceDate)) }
            }
            source = .cache
            return
        }
        state = .loading
        do {
            let result = try await repository(previewNext: previewNext).load(
                semester: previewNext ? semester.next : semester
            )
            try Task.checkCancellation()
            currentWeek = previewNext ? 1 : ((try? await api.currentWeek()) ?? 1)
            source = result.source
            state = .loaded(result.courses)
            if !previewNext { await updateSystemIntegrations(courses: result.courses) }
        } catch is CancellationError {
            return
        } catch {
            state = .failed(AppErrorState(message: error.localizedDescription))
            if !previewNext { await publishWidget(.unavailable(.expired)) }
        }
    }

    func refresh(previewNext: Bool = false) async {
        state = .loading
        do {
            let result = try await repository(previewNext: previewNext).load(
                semester: previewNext ? semester.next : semester,
                policy: .refresh
            )
            try Task.checkCancellation()
            source = result.source
            state = .loaded(result.courses)
            currentWeek = previewNext ? 1 : ((try? await api.currentWeek()) ?? currentWeek)
            if !previewNext { await updateSystemIntegrations(courses: result.courses) }
        } catch is CancellationError {
            return
        } catch {
            state = .failed(AppErrorState(message: error.localizedDescription))
            if !previewNext { await publishWidget(.unavailable(.expired)) }
        }
    }

    private func updateSystemIntegrations(courses: [Course], referenceDate: Date = Date()) async {
        await publishWidget(.make(courses: courses, currentWeek: currentWeek, updatedAt: referenceDate))
        if UserDefaults.standard.bool(forKey: "notifications.course-reminders") {
            _ = try? await CourseReminderCoordinator().setEnabled(
                true,
                courses: courses,
                currentWeek: currentWeek,
                now: referenceDate
            )
        }
    }

    private func publishWidget(_ snapshot: ScheduleWidgetSnapshot) async {
        try? await ScheduleWidgetSnapshotStore.shared.save(snapshot)
        WidgetCenter.shared.reloadTimelines(ofKind: "AHUTongScheduleWidget")
    }

    private func repository(previewNext: Bool) -> ScheduleRepository {
        previewNext ? nextRepository : currentRepository
    }

    static let demoCourses = [
        Course(weekday: 1, startWeek: 1, endWeek: 16, location: "博学南楼 A301", name: "移动应用开发", teacher: "张老师", duration: 2, startPeriod: 1, courseID: "demo-1", weekIndexes: Array(1...16)),
        Course(weekday: 1, startWeek: 1, endWeek: 16, location: "文典阁 205", name: "数据库系统", teacher: "李老师", duration: 3, startPeriod: 6, courseID: "demo-2", weekIndexes: Array(1...16)),
        Course(weekday: 2, startWeek: 1, endWeek: 12, location: "笃行北楼 B402", name: "计算机网络", teacher: "王老师", duration: 2, startPeriod: 3, courseID: "demo-3", weekIndexes: Array(1...12)),
        Course(weekday: 3, startWeek: 1, endWeek: 16, location: "博学南楼 A210", name: "操作系统", teacher: "陈老师", duration: 2, startPeriod: 1, courseID: "demo-4", weekIndexes: Array(1...16)),
        Course(weekday: 4, startWeek: 3, endWeek: 15, location: "实验中心 503", name: "软件工程实践", teacher: "刘老师", duration: 3, startPeriod: 8, courseID: "demo-5", weekIndexes: Array(3...15)),
        Course(weekday: 5, startWeek: 1, endWeek: 16, location: "磬苑操场", name: "大学体育", teacher: "赵老师", duration: 2, startPeriod: 3, courseID: "demo-6", weekIndexes: Array(1...16)),
        Course(weekday: 7, startWeek: 4, endWeek: 16, location: "线上", name: "形势与政策", teacher: "辅导员", duration: 2, startPeriod: 11, courseID: "demo-7", weekIndexes: [4, 8, 12, 16])
    ]

    static let demoNextSemesterCourses = [
        Course(weekday: 1, startWeek: 1, endWeek: 16, location: "博学南楼 A205", name: "编译原理", teacher: "周老师", duration: 2, startPeriod: 1, courseID: "demo-next-1", weekIndexes: Array(1...16)),
        Course(weekday: 3, startWeek: 1, endWeek: 12, location: "笃行北楼 B305", name: "计算机图形学", teacher: "吴老师", duration: 2, startPeriod: 3, courseID: "demo-next-2", weekIndexes: Array(1...12)),
        Course(weekday: 5, startWeek: 2, endWeek: 16, location: "实验中心 407", name: "软件测试", teacher: "郑老师", duration: 3, startPeriod: 6, courseID: "demo-next-3", weekIndexes: Array(2...16))
    ]
}

struct ScheduleView: View {
    @Environment(\.colorScheme) private var colorScheme
    @StateObject private var model: ScheduleViewModel
    @State private var selectedWeek = 1
    @State private var selectedCourse: Course?
    @State private var showSettings = false
    @AppStorage("schedule.show-all") private var showAllCourses = false
    @AppStorage("schedule.preview-next") private var previewNextSemester = false

    private let times = [
        "08:00", "08:50", "09:50", "10:40", "11:30", "14:00", "14:50",
        "15:50", "16:40", "17:30", "19:00", "19:50", "20:40"
    ]
    private let weekdays = ["周一", "周二", "周三", "周四", "周五", "周六", "周日"]

    init(appModel: AppModel) {
        let userID: String
        if case let .authenticated(user) = appModel.sessionState { userID = user.studentID } else { userID = "guest" }
        _model = StateObject(wrappedValue: ScheduleViewModel(api: appModel.campusAPI, userID: userID))
    }

    var body: some View {
        AndroidScreen {
            ScrollView(.vertical) {
                VStack(spacing: 8) {
                    controls
                    content
                }
                .padding(.bottom, 16)
            }
            .scrollIndicators(.hidden)
        }
        .task(id: previewNextSemester) {
            await model.load(demo: AppRuntime.isDemoSession, previewNext: previewNextSemester)
            guard !Task.isCancelled else { return }
            selectedWeek = ScheduleWeekNavigation.clamped(model.currentWeek)
        }
        .sheet(item: $selectedCourse) { course in CourseDetailView(course: course) }
        .sheet(isPresented: $showSettings) {
            ScheduleSettingsView(
                showAllCourses: $showAllCourses,
                previewNextSemester: $previewNextSemester
            )
        }
    }

    private var controls: some View {
        HStack(spacing: 8) {
            ScrollViewReader { proxy in
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        ForEach(ScheduleWeekNavigation.validWeeks, id: \.self) { week in
                            Button {
                                withAnimation(.easeInOut(duration: 0.25)) {
                                    selectedWeek = week
                                }
                            } label: {
                                Text("\(week)")
                                    .font(.headline.bold())
                                    .foregroundStyle(selectedWeek == week ? Color.white : Color.primary)
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 8)
                                    .background(selectedWeek == week ? AndroidParityPalette.brand : .clear, in: Capsule())
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("schedule.week.\(week)")
                            .accessibilityAddTraits(selectedWeek == week ? .isSelected : [])
                            .id(week)
                        }
                    }
                    .padding(.horizontal, 16)
                }
                .scrollIndicators(.hidden)
                .onChange(of: selectedWeek) { _, week in
                    withAnimation(.easeInOut(duration: 0.25)) {
                        proxy.scrollTo(max(1, week - 2), anchor: .leading)
                    }
                }
            }
            HStack(spacing: 0) {
                scheduleAction("location", "回到当前周") {
                    if previewNextSemester {
                        previewNextSemester = false
                    } else {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            selectedWeek = ScheduleWeekNavigation.clamped(model.currentWeek)
                        }
                    }
                }
                scheduleAction("gearshape", "课表设置", identifier: "schedule.settings") { showSettings = true }
                scheduleAction("arrow.clockwise", "刷新课表", identifier: "schedule.refresh") { Task { await model.refresh(previewNext: previewNextSemester) } }
            }
            .padding(2)
            .background(AndroidParityPalette.surface(colorScheme), in: Capsule())
            .padding(.trailing, 8)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch model.state {
        case .idle, .loading:
            schedulePager(courses: [])
                .overlay { ProgressView("加载课表…").accessibilityIdentifier("schedule.loading") }
        case let .failed(error):
            schedulePager(courses: [])
                .overlay {
                    VStack(spacing: 12) {
                        Text("加载课表失败").font(.headline)
                        Text(error.message).font(.caption).multilineTextAlignment(.center)
                        Button("重试") { Task { await model.refresh(previewNext: previewNextSemester) } }
                    }
                    .padding(24)
                    .accessibilityIdentifier("schedule.error")
                }
        case .empty:
            schedulePager(courses: []).accessibilityIdentifier("schedule.empty")
        case let .loaded(courses):
            schedulePager(courses: courses)
                .overlay {
                    if courses.isEmpty {
                        EmptyView().accessibilityIdentifier("schedule.empty")
                    }
                }
        }
    }

    private func scheduleAction(
        _ icon: String,
        _ label: String,
        identifier: String? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) { Image(systemName: icon).font(.system(size: 20)).frame(width: 38, height: 38) }
            .buttonStyle(.plain)
            .accessibilityLabel(label)
            .accessibilityIdentifier(identifier ?? "schedule.action.\(label)")
    }

    private func schedulePager(courses: [Course]) -> some View {
        TabView(selection: $selectedWeek) {
            ForEach(ScheduleWeekNavigation.validWeeks, id: \.self) { week in
                scheduleGrid(courses: courses, week: week)
                    .tag(week)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .frame(height: scheduleGridHeight)
        .accessibilityIdentifier("schedule.week-pager")
        .accessibilityValue("第\(selectedWeek)周")
    }

    private func scheduleGrid(courses: [Course], week: Int) -> some View {
        GeometryReader { geometry in
            let spacing: CGFloat = 4
            let timeWidth: CGFloat = 40
            let dayWidth = (geometry.size.width - timeWidth - spacing * 9) / 7
            let displayed = visibleCourses(courses, week: week)
            ZStack(alignment: .topLeading) {
                grid(dayWidth: dayWidth, spacing: spacing, timeWidth: timeWidth, week: week)
                if showAllCourses {
                    ForEach(ScheduleOverviewLayout.groups(for: courses)) { group in
                        overviewCourseGroupCard(
                            group,
                            dayWidth: dayWidth,
                            spacing: spacing,
                            timeWidth: timeWidth,
                            week: week
                        )
                    }
                } else {
                    ForEach(displayed) { course in
                        courseCard(
                            course,
                            dayWidth: dayWidth,
                            spacing: spacing,
                            timeWidth: timeWidth,
                            week: week
                        )
                    }
                }
            }
            .padding(.top, 8)
            .padding(4)
        }
        .frame(height: scheduleGridHeight)
        .background(AndroidParityPalette.raisedSurface(colorScheme), in: RoundedRectangle(cornerRadius: 32))
    }

    private func grid(dayWidth: CGFloat, spacing: CGFloat, timeWidth: CGFloat, week: Int) -> some View {
        VStack(spacing: spacing) {
            HStack(spacing: spacing) {
                Color.clear.frame(width: timeWidth, height: 64)
                ForEach(Array(weekdays.enumerated()), id: \.offset) { index, weekday in
                    VStack(spacing: 2) {
                        Text(weekday).font(.caption.bold())
                        Text(dateLabel(dayIndex: index, week: week)).font(.caption2).foregroundStyle(.secondary)
                    }
                    .frame(width: dayWidth, height: 64)
                    .background(index == currentWeekdayIndex && week == model.currentWeek ? AndroidParityPalette.primaryContainer(colorScheme) : .clear, in: RoundedRectangle(cornerRadius: 8))
                }
            }
            ForEach(Array(times.enumerated()), id: \.offset) { index, time in
                HStack(spacing: spacing) {
                    VStack(spacing: 1) {
                        Text("\(index + 1)").font(.caption.bold())
                        Text(time).androidScaledFont(size: 9, relativeTo: .caption2).foregroundStyle(.secondary)
                    }
                    .frame(width: timeWidth, height: 48)
                    ForEach(0..<7, id: \.self) { _ in Color.clear.frame(width: dayWidth, height: 48) }
                }
            }
        }
    }

    private func courseCard(
        _ course: Course,
        dayWidth: CGFloat,
        spacing: CGFloat,
        timeWidth: CGFloat,
        week: Int
    ) -> some View {
        let active = course.occurs(inWeek: week)
        let height = CGFloat(course.duration) * 48 + CGFloat(max(course.duration - 1, 0)) * spacing
        return Button { selectedCourse = course } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(course.name).androidScaledFont(size: 11, relativeTo: .caption2, weight: .bold).lineLimit(3)
                Spacer(minLength: 0)
                Text(active ? shortLocation(course.location) : "非本周")
                    .androidScaledFont(size: 10, relativeTo: .caption2, weight: .bold)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity)
                    .padding(2)
                    .background(.white.opacity(0.82), in: RoundedRectangle(cornerRadius: 6))
                    .foregroundStyle(.black)
            }
            .foregroundStyle(.white)
            .padding(4)
            .frame(width: dayWidth, height: height)
            .background(active ? courseColor(course.name) : Color.gray, in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .offset(
            x: timeWidth + spacing + CGFloat(course.weekday - 1) * (dayWidth + spacing),
            y: 64 + spacing + CGFloat(course.startPeriod - 1) * (48 + spacing)
        )
        .accessibilityLabel("\(course.name)，\(course.location)，第\(course.startPeriod)节")
        .accessibilityIdentifier(
            ScheduleWeekNavigation.courseIdentifier(
                courseID: course.courseID,
                week: week,
                selectedWeek: selectedWeek
            )
        )
    }

    private func overviewCourseGroupCard(
        _ group: ScheduleOverviewGroup,
        dayWidth: CGFloat,
        spacing: CGFloat,
        timeWidth: CGFloat,
        week: Int
    ) -> some View {
        let height = CGFloat(group.duration) * 48 + CGFloat(max(group.duration - 1, 0)) * spacing
        return VStack(spacing: 1) {
            ForEach(group.courses) { course in
                let active = course.occurs(inWeek: week)
                Button { selectedCourse = course } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(course.name)
                            .androidScaledFont(size: 11, relativeTo: .caption2, weight: .bold)
                            .lineLimit(group.courses.count <= 2 ? 3 : 2)
                        Spacer(minLength: 0)
                        Text(ScheduleTextFormatter.weekRange(for: course))
                            .androidScaledFont(size: 10, relativeTo: .caption2, weight: .bold)
                            .frame(maxWidth: .infinity)
                        Text(shortLocation(course.location))
                            .androidScaledFont(size: 10, relativeTo: .caption2, weight: .bold)
                            .lineLimit(2)
                            .frame(maxWidth: .infinity)
                            .padding(2)
                            .background(.white.opacity(0.82), in: RoundedRectangle(cornerRadius: 6))
                            .foregroundStyle(.black)
                    }
                    .foregroundStyle(.white)
                    .padding(4)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(courseColor(course.name).opacity(active ? 1 : 0.45))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(course.name)，\(ScheduleTextFormatter.weekRange(for: course))，\(course.location)")
                .accessibilityIdentifier(
                    ScheduleWeekNavigation.courseIdentifier(
                        courseID: course.courseID,
                        week: week,
                        selectedWeek: selectedWeek
                    )
                )
            }
        }
        .frame(width: dayWidth, height: height)
        .background(AndroidParityPalette.surface(colorScheme))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .offset(
            x: timeWidth + spacing + CGFloat(group.weekday - 1) * (dayWidth + spacing),
            y: 64 + spacing + CGFloat(group.startPeriod - 1) * (48 + spacing)
        )
    }

    private func visibleCourses(_ courses: [Course], week: Int) -> [Course] {
        courses.filter { $0.occurs(inWeek: week) }
    }

    private func courseColor(_ name: String) -> Color {
        let names: [String]
        if case let .loaded(courses) = model.state {
            var uniqueNames: [String] = []
            for course in courses where !uniqueNames.contains(course.name) {
                uniqueNames.append(course.name)
            }
            names = uniqueNames
        } else {
            names = [name]
        }
        let index = names.firstIndex(of: name) ?? 0
        let colors = [
            Color(red: 182 / 255, green: 84 / 255, blue: 118 / 255),
            Color(red: 181 / 255, green: 108 / 255, blue: 52 / 255),
            Color(red: 145 / 255, green: 128 / 255, blue: 0 / 255),
            Color(red: 62 / 255, green: 139 / 255, blue: 85 / 255),
            Color(red: 76 / 255, green: 124 / 255, blue: 177 / 255),
            Color(red: 80 / 255, green: 130 / 255, blue: 184 / 255),
            Color(red: 112 / 255, green: 82 / 255, blue: 174 / 255)
        ]
        return colors[index % colors.count]
    }

    private var currentWeekdayIndex: Int {
        demo || previewNextSemester ? -1 : (Calendar.current.component(.weekday, from: Date()) + 5) % 7
    }

    private func dateLabel(dayIndex: Int, week: Int) -> String {
        let calendar = Calendar(identifier: .gregorian)
        let date: Date
        if demo {
            let semesterStart = calendar.date(from: DateComponents(year: 2026, month: 7, day: 13)) ?? Date()
            date = calendar.date(byAdding: .day, value: (week - 1) * 7 + dayIndex, to: semesterStart) ?? semesterStart
        } else {
            let weekday = calendar.component(.weekday, from: Date())
            let mondayOffset = -((weekday + 5) % 7) + (week - model.currentWeek) * 7
            date = calendar.date(byAdding: .day, value: mondayOffset + dayIndex, to: Date()) ?? Date()
        }
        let components = calendar.dateComponents([.month, .day], from: date)
        return String(format: "%02d-%02d", components.month ?? 0, components.day ?? 0)
    }

    private var demo: Bool { AppRuntime.isDemoSession }

    private var scheduleGridHeight: CGFloat { 64 + 13 * 52 + 24 }

    private func shortLocation(_ location: String) -> String {
        ScheduleTextFormatter.shortLocation(location)
    }
}

private struct ScheduleSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Binding var showAllCourses: Bool
    @Binding var previewNextSemester: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("课表设置")
                    .font(.title2.bold())
                Spacer()
                Button("完成") { dismiss() }
                    .font(.headline)
                    .accessibilityIdentifier("schedule.settings.done")
            }

            settingToggle(
                title: "总览课表",
                description: "显示全部周次的课程，重叠课程会平分同一块时间区域",
                identifier: "schedule.settings.overview",
                isOn: $showAllCourses
            )
            settingToggle(
                title: "预览下学期课表",
                description: "切换到教务系统中的下学期课表",
                identifier: "schedule.settings.next-semester",
                isOn: $previewNextSemester
            )
            Spacer(minLength: 0)
        }
        .padding(24)
        .background(AndroidParityPalette.raisedSurface(colorScheme))
        .presentationDetents([.height(310)])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(32)
    }

    private func settingToggle(
        title: String,
        description: String,
        identifier: String,
        isOn: Binding<Bool>
    ) -> some View {
        Button { isOn.wrappedValue.toggle() } label: {
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.body.bold())
                    Text(description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Toggle("", isOn: isOn)
                    .labelsHidden()
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(ScheduleSettingPressStyle())
        .padding(.vertical, 10)
        .accessibilityIdentifier(identifier)
        .accessibilityValue(isOn.wrappedValue ? "开启" : "关闭")
    }
}

private struct ScheduleSettingPressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.985 : 1)
            .opacity(configuration.isPressed ? 0.78 : 1)
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.primary.opacity(configuration.isPressed ? 0.08 : 0))
                    .allowsHitTesting(false)
            }
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: configuration.isPressed)
            .sensoryFeedback(.impact(weight: .light, intensity: 0.55), trigger: configuration.isPressed) { oldValue, newValue in
                !oldValue && newValue
            }
    }
}

private struct CourseDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    let course: Course

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 24) {
                HStack {
                    Text(course.name).font(.title2.bold())
                    Spacer()
                    Button("完成") { dismiss() }
                }
                Text(scheduleDescription).font(.headline)
            }
            .padding(24)
            Divider().frame(height: 2)
            HStack(spacing: 0) {
                detail("location", course.location)
                Divider().frame(width: 2)
                detail("person.crop.circle", course.teacher)
            }
        }
        .background(AndroidParityPalette.raisedSurface(colorScheme))
        .presentationDetents([.height(300)])
        .presentationCornerRadius(32)
        .accessibilityIdentifier("schedule.course-detail")
    }

    private func detail(_ icon: String, _ text: String) -> some View {
        HStack(spacing: 8) { Image(systemName: icon); Text(text).font(.headline).lineLimit(2) }
            .frame(maxWidth: .infinity, minHeight: 72)
            .padding(.horizontal, 16)
    }

    private var scheduleDescription: String {
        let names = [1: "一", 2: "二", 3: "三", 4: "四", 5: "五", 6: "六", 7: "日"]
        let weeks = course.activeWeeks
        let weekText = weeks == Array(course.startWeek...course.endWeek)
            ? "\(course.startWeek) - \(course.endWeek)"
            : weeks.map(String.init).joined(separator: "、")
        return "第\(weekText)周的周\(names[course.weekday] ?? "")，第 \(course.startPeriod)-\(course.endPeriod) 节课"
    }
}
