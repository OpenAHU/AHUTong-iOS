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
                    weekIndexes: $0.weekIndexes
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
    nonisolated static let sharing = WidgetSharingResolution.resolve(.bundled()) {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: $0)
    }
    nonisolated static var sharedContainerURL: URL? {
        sharing.containerURL
    }

    private let fileURL: URL?

    init(fileURL: URL? = nil) {
        if let fileURL {
            self.fileURL = fileURL
        } else if let container = Self.sharedContainerURL {
            self.fileURL = container.appendingPathComponent("schedule-widget.json")
        } else {
            self.fileURL = nil
        }
    }

    init(containerURL: URL?) {
        fileURL = containerURL?.appendingPathComponent("schedule-widget.json")
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
        try JSONEncoder().encode(snapshot).write(to: fileURL, options: .atomic)
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
