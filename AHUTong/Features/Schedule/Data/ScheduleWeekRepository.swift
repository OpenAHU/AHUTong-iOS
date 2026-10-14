import Foundation

struct ScheduleWeekSnapshot: Codable, Equatable, Sendable {
    let week: Int
    let referenceDate: Date
    var isFallback = false

    func resolved(at date: Date) -> Self {
        Self(
            week: ScheduleWeekNavigation.clamped(
                week + ScheduleCalendar.weekOffset(from: referenceDate, to: date)
            ),
            referenceDate: date,
            isFallback: isFallback
        )
    }
}

struct ScheduleWeekRepository: Sendable {
    private let api: any CampusCoreAPI
    private let store: JSONStore<ScheduleWeekSnapshot>
    private let now: @Sendable () -> Date

    init(
        api: any CampusCoreAPI, cache: UserScopedStore, semester: Semester,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.api = api
        self.now = now
        store = JSONStore(store: cache, key: "schedule.week.\(semester.rawValue)")
    }

    func cached() async -> ScheduleWeekSnapshot {
        if let snapshot = try? await store.load(), (1...20).contains(snapshot.week) {
            return snapshot.resolved(at: now())
        }
        return ScheduleWeekSnapshot(week: 1, referenceDate: now(), isFallback: true)
    }

    func refresh() async throws -> ScheduleWeekSnapshot {
        let week = try await api.currentWeek()
        try Task.checkCancellation()
        guard (1...20).contains(week) else { throw CampusCoreError.invalidResponse }
        let snapshot = ScheduleWeekSnapshot(week: week, referenceDate: now())
        try await store.save(snapshot)
        return snapshot
    }
}
