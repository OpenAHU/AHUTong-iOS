import Foundation

enum ScheduleWidgetStatus: String, Codable, Equatable, Sendable {
    case ready
    case empty
    case signedOut
    case expired
    case sharingUnavailable
}

struct ScheduleWidgetCourse: Codable, Identifiable, Equatable, Sendable {
    let id: String
    let weekday: Int
    let startPeriod: Int
    let endPeriod: Int
    let name: String
    let location: String
    let weekIndexes: [Int]?
}

struct ScheduleWidgetSnapshot: Codable, Equatable, Sendable {
    let status: ScheduleWidgetStatus
    let currentWeek: Int
    let updatedAt: Date
    let courses: [ScheduleWidgetCourse]
    let allCourses: [ScheduleWidgetCourse]?

    static func make(courses: [Course], currentWeek: Int, updatedAt: Date = Date()) -> Self {
        let values = courses.map {
                ScheduleWidgetCourse(
                    id: $0.id,
                    weekday: $0.weekday,
                    startPeriod: $0.startPeriod,
                    endPeriod: $0.endPeriod,
                    name: $0.name,
                    location: $0.location,
                    weekIndexes: $0.activeWeeks
                )
            }
            .sorted { ($0.weekday, $0.startPeriod, $0.name) < ($1.weekday, $1.startPeriod, $1.name) }
        let snapshot = Self(
            status: values.isEmpty ? .empty : .ready,
            currentWeek: currentWeek,
            updatedAt: updatedAt,
            courses: values,
            allCourses: values
        )
        return snapshot.resolved(at: updatedAt)
    }

    static func unavailable(_ status: ScheduleWidgetStatus, updatedAt: Date = Date()) -> Self {
        Self(status: status, currentWeek: 1, updatedAt: updatedAt, courses: [], allCourses: [])
    }

    var synchronizationSummary: String {
        switch status {
        case .ready: "已同步第 \(currentWeek) 周，共 \(courses.count) 门课程"
        case .empty: "已同步，第 \(currentWeek) 周暂无课程"
        case .signedOut: "尚未同步课表，请打开课表同步"
        case .expired: "课表同步失败，请打开课表重试"
        case .sharingUnavailable: "当前安装无法共享课表，请检查签名权限"
        }
    }

    /// Counts and state only: never include course titles, locations or IDs.
    var diagnosticSummary: String {
        """
        Snapshot status: \(status.rawValue)
        Snapshot week: \(currentWeek)
        Snapshot active courses: \(courses.count)
        Snapshot total courses: \((allCourses ?? courses).count)
        """
    }

    func resolved(at date: Date, calendar: Calendar = ScheduleCalendar.campus) -> Self {
        guard status == .ready || status == .empty else { return self }
        let offset = ScheduleCalendar.weekOffset(from: updatedAt, to: date, calendar: calendar)
        let week = max(1, min(20, currentWeek + offset))
        let source = allCourses ?? courses
        let active = source.filter { ($0.weekIndexes ?? [currentWeek]).contains(week) }
        return Self(
            status: active.isEmpty ? .empty : .ready,
            currentWeek: week,
            updatedAt: updatedAt,
            courses: active,
            allCourses: source
        )
    }
}

actor ScheduleWidgetSnapshotStore {
    static let shared = ScheduleWidgetSnapshotStore()
    nonisolated static var sharing: WidgetSharingResolution {
        WidgetSharingResolution.resolve(.bundled()) {
            FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: $0)
        }
    }
    nonisolated static var sharedContainerURL: URL? {
        sharing.containerURL
    }

    private let explicitFileURL: URL?
    private let container: @Sendable () -> URL?
    private var fileURL: URL? {
        explicitFileURL ?? container()?.appendingPathComponent("schedule-widget.json")
    }

    init(fileURL: URL? = nil) {
        explicitFileURL = fileURL
        if fileURL == nil {
            container = { Self.sharedContainerURL }
        } else {
            container = { nil }
        }
    }

    init(containerURL: URL?) {
        explicitFileURL = nil
        container = { containerURL }
    }

    init(container: @escaping @Sendable () -> URL?) {
        explicitFileURL = nil
        self.container = container
    }

    /// WidgetKit's callback-based provider API is synchronous. Reading this
    /// tiny, atomically-written snapshot directly avoids sending its
    /// non-Sendable completion handler across an actor boundary.
    nonisolated static func loadSharedSnapshot() -> ScheduleWidgetSnapshot {
        decode(from: sharedContainerURL?.appendingPathComponent("schedule-widget.json"))
    }

    func load() -> ScheduleWidgetSnapshot {
        Self.decode(from: fileURL)
    }

    func save(_ snapshot: ScheduleWidgetSnapshot) throws {
        guard let fileURL else { throw ScheduleWidgetStoreError.sharingUnavailable }
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        // Course snapshots must remain readable by WidgetKit while locked after
        // the first unlock. Credentials never enter this shared file.
        try JSONEncoder().encode(snapshot).write(to: fileURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }


    private nonisolated static func decode(from fileURL: URL?) -> ScheduleWidgetSnapshot {
        guard let fileURL else { return .unavailable(.sharingUnavailable) }
        guard let data = try? Data(contentsOf: fileURL),
              let snapshot = try? JSONDecoder().decode(ScheduleWidgetSnapshot.self, from: data) else {
            return .unavailable(.signedOut)
        }
        return snapshot
    }
}

enum ScheduleWidgetStoreError: Error {
    case sharingUnavailable
}
