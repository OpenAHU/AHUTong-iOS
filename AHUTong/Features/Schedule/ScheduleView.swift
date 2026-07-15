import SwiftUI
import WidgetKit

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
                let courses = DebugRuntimeSettings.decode("schedule", as: [Course].self) ?? Self.demoCourses
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
            currentWeek = previewNext ? 1 : ((try? await api.currentWeek()) ?? 1)
            source = result.source
            state = .loaded(result.courses)
            if !previewNext { await updateSystemIntegrations(courses: result.courses) }
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
            source = result.source
            state = .loaded(result.courses)
            currentWeek = previewNext ? 1 : ((try? await api.currentWeek()) ?? currentWeek)
            if !previewNext { await updateSystemIntegrations(courses: result.courses) }
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
                .padding(.bottom, 96)
            }
            .scrollIndicators(.hidden)
        }
        .task {
            await model.load(demo: AppRuntime.isDemoSession, previewNext: previewNextSemester)
            selectedWeek = model.currentWeek
        }
        .onChange(of: previewNextSemester) { _, enabled in
            Task {
                await model.load(demo: AppRuntime.isDemoSession, previewNext: enabled)
                selectedWeek = model.currentWeek
            }
        }
        .sheet(item: $selectedCourse) { course in CourseDetailView(course: course) }
        .alert("课表设置", isPresented: $showSettings) {
            Toggle("总览课表", isOn: $showAllCourses)
            Toggle("预览下学期课表", isOn: $previewNextSemester)
            Button("完成", role: .cancel) {}
        } message: {
            Text("总览课表会显示全部周次课程；下学期预览会读取教务系统下一学期课表。")
        }
    }

    private var controls: some View {
        HStack(spacing: 8) {
            ScrollViewReader { proxy in
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        ForEach(1...20, id: \.self) { week in
                            Button {
                                selectedWeek = week
                                withAnimation { proxy.scrollTo(max(1, week - 2), anchor: .leading) }
                            } label: {
                                Text("\(week)")
                                    .font(.headline.bold())
                                    .foregroundStyle(selectedWeek == week ? Color.white : Color.primary)
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 8)
                                    .background(selectedWeek == week ? AndroidParityPalette.brand : .clear, in: Capsule())
                            }
                            .buttonStyle(.plain)
                            .id(week)
                        }
                    }
                    .padding(.horizontal, 16)
                }
                .scrollIndicators(.hidden)
            }
            HStack(spacing: 0) {
                scheduleAction("location", "回到当前周") { selectedWeek = model.currentWeek }
                scheduleAction("gearshape", "课表设置") { showSettings = true }
                scheduleAction("arrow.clockwise", "刷新课表") { Task { await model.refresh(previewNext: previewNextSemester) } }
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
            scheduleGrid(courses: [])
                .overlay { ProgressView("加载课表…").accessibilityIdentifier("schedule.loading") }
        case let .failed(error):
            scheduleGrid(courses: [])
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
            scheduleGrid(courses: []).accessibilityIdentifier("schedule.empty")
        case let .loaded(courses):
            scheduleGrid(courses: courses)
                .overlay {
                    if courses.isEmpty {
                        EmptyView().accessibilityIdentifier("schedule.empty")
                    }
                }
        }
    }

    private func scheduleAction(_ icon: String, _ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: icon).font(.system(size: 20)).frame(width: 38, height: 38) }
            .buttonStyle(.plain)
            .accessibilityLabel(label)
    }

    private func scheduleGrid(courses: [Course]) -> some View {
        GeometryReader { geometry in
            let spacing: CGFloat = 4
            let timeWidth: CGFloat = 40
            let dayWidth = (geometry.size.width - timeWidth - spacing * 9) / 7
            let displayed = visibleCourses(courses)
            ZStack(alignment: .topLeading) {
                grid(dayWidth: dayWidth, spacing: spacing, timeWidth: timeWidth)
                ForEach(displayed) { course in
                    let group = conflictGroup(for: course, in: displayed)
                    let index = group.firstIndex(of: course) ?? 0
                    courseCard(
                        course,
                        dayWidth: dayWidth,
                        spacing: spacing,
                        timeWidth: timeWidth,
                        conflictIndex: index,
                        conflictCount: group.count
                    )
                }
            }
            .padding(.top, 8)
            .padding(4)
        }
        .frame(height: 64 + 13 * 52 + 24)
        .background(AndroidParityPalette.raisedSurface(colorScheme), in: RoundedRectangle(cornerRadius: 32))
    }

    private func grid(dayWidth: CGFloat, spacing: CGFloat, timeWidth: CGFloat) -> some View {
        VStack(spacing: spacing) {
            HStack(spacing: spacing) {
                Color.clear.frame(width: timeWidth, height: 64)
                ForEach(Array(weekdays.enumerated()), id: \.offset) { index, weekday in
                    VStack(spacing: 2) {
                        Text(weekday).font(.caption.bold())
                        Text(dateLabel(dayIndex: index)).font(.caption2).foregroundStyle(.secondary)
                    }
                    .frame(width: dayWidth, height: 64)
                    .background(index == currentWeekdayIndex && selectedWeek == model.currentWeek ? AndroidParityPalette.primaryContainer(colorScheme) : .clear, in: RoundedRectangle(cornerRadius: 8))
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
        conflictIndex: Int,
        conflictCount: Int
    ) -> some View {
        let active = course.occurs(inWeek: selectedWeek)
        let height = CGFloat(course.duration) * 48 + CGFloat(max(course.duration - 1, 0)) * spacing
        let resolvedCount = max(conflictCount, 1)
        let resolvedWidth = (dayWidth - CGFloat(resolvedCount - 1) * 1) / CGFloat(resolvedCount)
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
            .frame(width: resolvedWidth, height: height)
            .background(active ? courseColor(course.name) : Color.gray, in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .offset(
            x: timeWidth + spacing + CGFloat(course.weekday - 1) * (dayWidth + spacing)
                + CGFloat(conflictIndex) * (resolvedWidth + 1),
            y: 64 + spacing + CGFloat(course.startPeriod - 1) * (48 + spacing)
        )
        .accessibilityLabel("\(course.name)，\(course.location)，第\(course.startPeriod)节")
        .accessibilityIdentifier("schedule.course.\(course.courseID)")
    }

    private func visibleCourses(_ courses: [Course]) -> [Course] {
        courses.filter { showAllCourses || $0.occurs(inWeek: selectedWeek) }
    }

    private func conflictGroup(for course: Course, in courses: [Course]) -> [Course] {
        guard showAllCourses else { return [course] }
        return courses.filter {
            $0.weekday == course.weekday
                && $0.startPeriod == course.startPeriod
                && $0.duration == course.duration
        }
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

    private func dateLabel(dayIndex: Int) -> String {
        let calendar = Calendar(identifier: .gregorian)
        let date: Date
        if demo {
            let semesterStart = calendar.date(from: DateComponents(year: 2026, month: 7, day: 13)) ?? Date()
            date = calendar.date(byAdding: .day, value: (selectedWeek - 1) * 7 + dayIndex, to: semesterStart) ?? semesterStart
        } else {
            let weekday = calendar.component(.weekday, from: Date())
            let mondayOffset = -((weekday + 5) % 7) + (selectedWeek - model.currentWeek) * 7
            date = calendar.date(byAdding: .day, value: mondayOffset + dayIndex, to: Date()) ?? Date()
        }
        let components = calendar.dateComponents([.month, .day], from: date)
        return String(format: "%02d-%02d", components.month ?? 0, components.day ?? 0)
    }

    private var demo: Bool { AppRuntime.isDemoSession }

    private func shortLocation(_ location: String) -> String {
        location.replacingOccurrences(of: "博学北楼", with: "博北")
            .replacingOccurrences(of: "博学南楼", with: "博南")
            .replacingOccurrences(of: "笃行南楼", with: "笃南")
            .replacingOccurrences(of: "笃行北楼", with: "笃北")
            .replacingOccurrences(of: "互联大楼", with: "互楼")
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
