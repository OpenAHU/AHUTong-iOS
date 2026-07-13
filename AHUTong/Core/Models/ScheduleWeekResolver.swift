import Foundation

enum ScheduleConfigSource: String, Codable, Sendable {
    case local
    case remote
    case fallback
}

struct SchedulePosition: Equatable, Sendable {
    let week: Int
    let weekday: Int
    let semesterStart: Date
    let source: ScheduleConfigSource
}

enum ScheduleWeekResolver {
    static func resolve(
        semesterStart: Date,
        now: Date,
        source: ScheduleConfigSource = .local,
        calendar: Calendar
    ) -> SchedulePosition {
        let start = calendar.startOfDay(for: semesterStart)
        let today = calendar.startOfDay(for: now)
        let elapsedDays = max(calendar.dateComponents([.day], from: start, to: today).day ?? 0, 0)
        return SchedulePosition(
            week: elapsedDays / 7 + 1,
            weekday: isoWeekday(for: today, calendar: calendar),
            semesterStart: start,
            source: source
        )
    }

    static func fallback(now: Date, calendar: Calendar) -> SchedulePosition {
        let today = calendar.startOfDay(for: now)
        let weekday = isoWeekday(for: today, calendar: calendar)
        let monday = calendar.date(byAdding: .day, value: -(weekday - 1), to: today) ?? today
        return SchedulePosition(
            week: 1,
            weekday: weekday,
            semesterStart: monday,
            source: .fallback
        )
    }

    private static func isoWeekday(for date: Date, calendar: Calendar) -> Int {
        let weekday = calendar.component(.weekday, from: date)
        return (weekday + 5) % 7 + 1
    }
}
