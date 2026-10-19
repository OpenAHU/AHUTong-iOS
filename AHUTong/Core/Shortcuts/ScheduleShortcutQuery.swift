import Foundation

enum CampusScheduleCalendar {
    static var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        value.firstWeekday = 2
        return value
    }

    // A date selected in Shortcuts means that calendar day, even abroad.
    static func selectedDay(_ date: Date, inputCalendar: Calendar) -> Date? {
        var local = Calendar(identifier: .gregorian)
        local.timeZone = inputCalendar.timeZone
        return calendar.date(from: local.dateComponents([.year, .month, .day], from: date))
    }
}

struct ShortcutScheduleSnapshot: Codable, Equatable, Sendable {
    let semester: Semester
    let semesterStart: Date
    let updatedAt: Date?
    let courses: [Course]

    static func make(
        semester: Semester,
        courses: [Course],
        currentWeek: Int,
        referenceDate: Date,
        updatedAt: Date?
    ) -> Self? {
        let calendar = CampusScheduleCalendar.calendar
        guard (1...20).contains(currentWeek),
              courses.allSatisfy(\.isStructurallyValid),
              let monday = calendar.dateInterval(of: .weekOfYear, for: referenceDate)?.start,
              let start = calendar.date(byAdding: .day, value: -(currentWeek - 1) * 7, to: monday) else {
            return nil
        }
        return Self(semester: semester, semesterStart: start, updatedAt: updatedAt, courses: courses)
    }
}

struct ScheduleShortcutStore: Sendable {
    private let store: JSONStore<ShortcutScheduleSnapshot>

    init(userID: String, dataStore: any DataStore = AppPersistence.migratingDefaults()) {
        store = JSONStore(
            store: UserScopedStore(store: dataStore, userID: userID),
            key: "shortcuts.schedule.v1"
        )
    }

    func load() async throws -> ShortcutScheduleSnapshot? { try await store.load() }

    func record(
        courses: [Course],
        semester: Semester,
        currentWeek: Int?,
        source: ScheduleSnapshotSource,
        at date: Date = Date()
    ) async throws {
        let previous = try? await store.load()
        let sameSemester = previous?.semester == semester ? previous : nil
        // A homepage cache read can finish after a manual refresh. Keep the
        // newer recorded courses rather than relabeling an older cache as fresh.
        let recordedCourses = source == .remote ? courses : (sameSemester?.courses ?? courses)
        // Never invent week 1 when the week endpoint fails. An existing anchor
        // remains usable offline; without one the shortcut reports missing data.
        let snapshot: ShortcutScheduleSnapshot?
        if let currentWeek {
            snapshot = .make(
                semester: semester, courses: recordedCourses, currentWeek: currentWeek,
                referenceDate: date,
                updatedAt: source == .remote ? date : sameSemester?.updatedAt
            )
        } else if let sameSemester, recordedCourses.allSatisfy(\.isStructurallyValid) {
            snapshot = ShortcutScheduleSnapshot(
                semester: semester, semesterStart: sameSemester.semesterStart,
                updatedAt: source == .remote ? date : sameSemester.updatedAt, courses: recordedCourses
            )
        } else {
            snapshot = nil
        }
        if let snapshot { try await store.save(snapshot) }
    }
}

struct ScheduleShortcutResult: Equatable, Sendable {
    enum Status: Equatable, Sendable {
        case courses, noClasses, noData, outsideSemester, setupRequired, signInRequired, unavailable
    }

    let status: Status
    let text: String

    static func query(snapshot: ShortcutScheduleSnapshot?, day: Date) -> Self {
        let calendar = CampusScheduleCalendar.calendar
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy.MM.dd"
        let heading = formatter.string(from: day)
        guard let snapshot,
              snapshot.courses.allSatisfy(\.isStructurallyValid),
              let days = calendar.dateComponents(
                [.day], from: calendar.startOfDay(for: snapshot.semesterStart),
                to: calendar.startOfDay(for: day)
              ).day else {
            return Self(status: .noData, text: "尚无可用课表数据，请先打开安大通同步课表，或在体验账户中导入课表。")
        }
        guard (0..<140).contains(days) else {
            return Self(status: .outsideSemester, text: "\(heading)超出本机已同步学期的范围，无法判断当天是否有课。请打开安大通确认该学期课表。")
        }
        let week = days / 7 + 1
        let weekday = (calendar.component(.weekday, from: day) + 5) % 7 + 1
        var seen: Set<String> = []
        let courses = snapshot.courses.filter {
            $0.weekday == weekday && $0.occurs(inWeek: week) && seen.insert($0.id).inserted
        }.sorted {
            if $0.startPeriod != $1.startPeriod { return $0.startPeriod < $1.startPeriod }
            if $0.endPeriod != $1.endPeriod { return $0.endPeriod < $1.endPeriod }
            return $0.name < $1.name
        }
        let freshness: String
        if let updatedAt = snapshot.updatedAt {
            formatter.dateFormat = "MM.dd HH:mm"
            freshness = "同步于\(formatter.string(from: updatedAt))"
        } else {
            freshness = "本机缓存课表 · 同步时间未知"
        }
        let dayHeading = "\(heading) 第\(week)周周\(["一", "二", "三", "四", "五", "六", "日"][weekday - 1])"
        guard !courses.isEmpty else {
            return Self(status: .noClasses, text: "\(dayHeading)\n当天没有课程\n\(freshness)")
        }
        let lines = courses.map { course in
            let location = course.location.trimmingCharacters(in: .whitespacesAndNewlines)
            let periods = course.startPeriod == course.endPeriod ? "\(course.startPeriod)" : "\(course.startPeriod)–\(course.endPeriod)"
            return "\(periods)节 \(course.name) \(location.isEmpty ? "地点待公布" : location)"
        }
        return Self(
            status: .courses,
            text: ([dayHeading] + lines + [freshness]).joined(separator: "\n")
        )
    }
}

struct ScheduleShortcutService: Sendable {
    private let dataStore: any DataStore
    private let sessionStore: CampusSessionStore
    private let consentStore: any AgreementConsentStoring
    private let experienceEnabled: @Sendable () -> Bool

    init(
        dataStore: any DataStore = AppPersistence.migratingDefaults(),
        sessionStore: CampusSessionStore = CampusSessionStore(),
        consentStore: any AgreementConsentStoring = AgreementConsentStore(store: UserDefaultsDataStore()),
        experienceEnabled: @escaping @Sendable () -> Bool = {
            UserDefaults.standard.bool(forKey: "session.experience-enabled")
        }
    ) {
        self.dataStore = dataStore
        self.sessionStore = sessionStore
        self.consentStore = consentStore
        self.experienceEnabled = experienceEnabled
    }

    func query(date: Date, inputCalendar: Calendar = .current) async -> ScheduleShortcutResult {
        do {
            let consent = try await consentStore.load()
            guard consent.isComplete else {
                return .init(status: .setupRequired, text: "请先打开安大通完成首次设置，再使用课表快捷指令。")
            }
            guard let day = CampusScheduleCalendar.selectedDay(date, inputCalendar: inputCalendar) else {
                return .init(status: .unavailable, text: "无法识别查询日期，请重新选择日期。")
            }
            if experienceEnabled() {
                let value = await ExperienceScheduleStore(store: dataStore).snapshot()
                let semester = Semester.current(date: value.updatedAt, calendar: CampusScheduleCalendar.calendar)
                let snapshot = value.coursesBySemester[semester.rawValue].flatMap { courses in
                    ShortcutScheduleSnapshot.make(
                        semester: semester, courses: courses, currentWeek: value.currentWeek,
                        referenceDate: value.updatedAt, updatedAt: value.updatedAt
                    )
                }
                return .query(snapshot: snapshot, day: day)
            }
            guard consent.privacyDecision == .accepted,
                  let session = try await sessionStore.load(),
                  !session.user.studentID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return .init(status: .signInRequired, text: "请先打开安大通登录，或选择体验账户并导入课表。")
            }
            let snapshot = try await ScheduleShortcutStore(
                userID: session.user.studentID, dataStore: dataStore
            ).load()
            return .query(snapshot: snapshot, day: day)
        } catch is DecodingError {
            return .query(snapshot: nil, day: date)
        } catch {
            return .init(status: .unavailable, text: "暂时无法读取本机课表，请解锁设备并打开安大通后重试。")
        }
    }
}
