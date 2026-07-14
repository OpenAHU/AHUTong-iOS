import Foundation

enum ScheduleWidgetStatus: String, Codable, Equatable, Sendable {
    case ready
    case empty
    case signedOut
    case expired
}

struct ScheduleWidgetCourse: Codable, Identifiable, Equatable, Sendable {
    let id: String
    let weekday: Int
    let startPeriod: Int
    let endPeriod: Int
    let name: String
    let location: String
}

struct ScheduleWidgetSnapshot: Codable, Equatable, Sendable {
    let status: ScheduleWidgetStatus
    let currentWeek: Int
    let updatedAt: Date
    let courses: [ScheduleWidgetCourse]

    static func make(courses: [Course], currentWeek: Int, updatedAt: Date = Date()) -> Self {
        let values = courses
            .filter { $0.occurs(inWeek: currentWeek) }
            .map {
                ScheduleWidgetCourse(
                    id: $0.id,
                    weekday: $0.weekday,
                    startPeriod: $0.startPeriod,
                    endPeriod: $0.endPeriod,
                    name: $0.name,
                    location: $0.location
                )
            }
            .sorted { ($0.weekday, $0.startPeriod, $0.name) < ($1.weekday, $1.startPeriod, $1.name) }
        return Self(status: values.isEmpty ? .empty : .ready, currentWeek: currentWeek, updatedAt: updatedAt, courses: values)
    }

    static func unavailable(_ status: ScheduleWidgetStatus, updatedAt: Date = Date()) -> Self {
        Self(status: status, currentWeek: 1, updatedAt: updatedAt, courses: [])
    }
}

actor ScheduleWidgetSnapshotStore {
    static let shared = ScheduleWidgetSnapshotStore()
    static let appGroup = "group.com.openahu.ahutong.shared"

    private let fileURL: URL

    init(fileURL: URL? = nil) {
        if let fileURL {
            self.fileURL = fileURL
        } else if let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: Self.appGroup) {
            self.fileURL = container.appendingPathComponent("schedule-widget.json")
        } else {
            let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            self.fileURL = base.appendingPathComponent("AHUTong/schedule-widget.json")
        }
    }

    /// WidgetKit's callback-based provider API is synchronous. Reading this
    /// tiny, atomically-written snapshot directly avoids sending its
    /// non-Sendable completion handler across an actor boundary.
    nonisolated static func loadSharedSnapshot() -> ScheduleWidgetSnapshot {
        let fileURL: URL
        if let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup) {
            fileURL = container.appendingPathComponent("schedule-widget.json")
        } else {
            let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            fileURL = base.appendingPathComponent("AHUTong/schedule-widget.json")
        }
        return decode(from: fileURL)
    }

    func load() -> ScheduleWidgetSnapshot {
        Self.decode(from: fileURL)
    }

    func save(_ snapshot: ScheduleWidgetSnapshot) throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try JSONEncoder().encode(snapshot).write(to: fileURL, options: .atomic)
    }


    private nonisolated static func decode(from fileURL: URL) -> ScheduleWidgetSnapshot {
        guard let data = try? Data(contentsOf: fileURL),
              let snapshot = try? JSONDecoder().decode(ScheduleWidgetSnapshot.self, from: data) else {
            return .unavailable(.signedOut)
        }
        return snapshot
    }
}
