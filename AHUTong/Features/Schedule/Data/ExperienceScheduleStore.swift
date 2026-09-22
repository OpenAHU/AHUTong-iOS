import Foundation

struct ExperienceScheduleDocumentV1: Codable, Equatable, Sendable {
    let version: Int
    let semester: Semester
    let currentWeek: Int
    let courses: [Course]
}

struct ExperienceScheduleSnapshot: Codable, Equatable, Sendable {
    static let currentVersion = 1

    var version = currentVersion
    var currentWeek = 1
    var updatedAt = Date.distantPast
    var coursesBySemester: [String: [Course]] = [:]

    func resolvedCurrentWeek(at date: Date = Date(), calendar: Calendar = .current) -> Int {
        guard updatedAt != .distantPast else { return min(max(currentWeek, 1), 20) }
        let sourceStart = calendar.dateInterval(of: .weekOfYear, for: updatedAt)?.start ?? updatedAt
        let targetStart = calendar.dateInterval(of: .weekOfYear, for: date)?.start ?? date
        let offset = calendar.dateComponents([.weekOfYear], from: sourceStart, to: targetStart).weekOfYear ?? 0
        return min(max(currentWeek + offset, 1), 20)
    }
}

enum ExperienceScheduleError: LocalizedError, Equatable, Sendable {
    case fileTooLarge
    case unsupportedVersion
    case unsupportedSemester
    case invalidCurrentWeek
    case tooManyCourses
    case invalidCourse
    case invalidDocument

    var errorDescription: String? {
        switch self {
        case .fileTooLarge: "课表文件不能超过 1 MB"
        case .unsupportedVersion: "不支持该课表文件版本"
        case .unsupportedSemester: "只能导入当前或下一学期的课表"
        case .invalidCurrentWeek: "当前周必须在 1 到 20 之间"
        case .tooManyCourses: "单个文件最多包含 500 门课程"
        case .invalidCourse: "课表中包含无效的课程数据"
        case .invalidDocument: "无法读取课表 JSON 文件"
        }
    }
}

struct ExperienceScheduleStore: Sendable {
    static let maximumDocumentSize = 1_048_576
    static let maximumCourseCount = 500

    private let store: any DataStore
    private let key = "experience.schedule.snapshot.v1"

    init(store: any DataStore = AppPersistence.migratingDefaults()) {
        self.store = store
    }

    func snapshot() async -> ExperienceScheduleSnapshot {
        guard let data = try? await store.data(forKey: key),
              let value = try? JSONDecoder().decode(ExperienceScheduleSnapshot.self, from: data),
              value.version == ExperienceScheduleSnapshot.currentVersion else {
            return ExperienceScheduleSnapshot()
        }
        return value
    }

    func courses(for semester: Semester) async -> [Course] {
        await snapshot().coursesBySemester[semester.rawValue] ?? []
    }

    func save(
        courses: [Course],
        semester: Semester,
        currentWeek: Int,
        updatesCurrentWeek: Bool = true
    ) async throws {
        let normalized = try validate(courses)
        var value = await snapshot()
        if updatesCurrentWeek {
            value.currentWeek = min(max(currentWeek, 1), 20)
        } else {
            value.currentWeek = value.resolvedCurrentWeek()
        }
        value.updatedAt = Date()
        value.coursesBySemester[semester.rawValue] = normalized
        try await persist(value)
    }

    func importDocument(
        _ data: Data,
        allowedSemesters: Set<Semester>
    ) async throws -> Semester {
        guard data.count <= Self.maximumDocumentSize else {
            throw ExperienceScheduleError.fileTooLarge
        }
        let document: ExperienceScheduleDocumentV1
        do {
            document = try JSONDecoder().decode(ExperienceScheduleDocumentV1.self, from: data)
        } catch {
            throw ExperienceScheduleError.invalidDocument
        }
        guard document.version == 1 else {
            throw ExperienceScheduleError.unsupportedVersion
        }
        guard allowedSemesters.contains(document.semester) else {
            throw ExperienceScheduleError.unsupportedSemester
        }
        guard (1...20).contains(document.currentWeek) else {
            throw ExperienceScheduleError.invalidCurrentWeek
        }
        try await save(
            courses: document.courses,
            semester: document.semester,
            currentWeek: document.currentWeek,
            updatesCurrentWeek: document.semester == Semester.current()
        )
        return document.semester
    }

    func preserveAccountCache(userID: String) async {
        let source = AppPersistence.migratingDefaults()
        let scoped = UserScopedStore(store: source, userID: userID)
        let current = Semester.current()
        let next = current.next
        let currentCourses = try? await JSONStore<[Course]>(
            store: scoped,
            key: "schedule.\(current.rawValue)"
        ).load()
        let nextCourses = try? await JSONStore<[Course]>(
            store: scoped,
            key: "schedule.\(next.rawValue)"
        ).load()
        let widgetWeek = await ScheduleWidgetSnapshotStore.shared.load().resolved(at: Date()).currentWeek
        if let currentCourses {
            try? await save(courses: currentCourses, semester: current, currentWeek: widgetWeek)
        }
        if let nextCourses {
            try? await save(
                courses: nextCourses,
                semester: next,
                currentWeek: widgetWeek,
                updatesCurrentWeek: false
            )
        }
    }

    func clear() async {
        try? await store.removeValue(forKey: key)
    }

    func replace(with snapshot: ExperienceScheduleSnapshot) async throws {
        var normalized = ExperienceScheduleSnapshot()
        normalized.currentWeek = min(max(snapshot.currentWeek, 1), 20)
        normalized.updatedAt = snapshot.updatedAt
        for (semester, courses) in snapshot.coursesBySemester {
            normalized.coursesBySemester[semester] = try validate(courses)
        }
        try await persist(normalized)
    }

    private func validate(_ courses: [Course]) throws -> [Course] {
        guard courses.count <= Self.maximumCourseCount else {
            throw ExperienceScheduleError.tooManyCourses
        }
        guard courses.allSatisfy(\.isStructurallyValid) else {
            throw ExperienceScheduleError.invalidCourse
        }
        var seen: Set<String> = []
        return courses.filter { seen.insert($0.id).inserted }
    }

    private func persist(_ snapshot: ExperienceScheduleSnapshot) async throws {
        try await store.set(try JSONEncoder().encode(snapshot), forKey: key)
    }
}
