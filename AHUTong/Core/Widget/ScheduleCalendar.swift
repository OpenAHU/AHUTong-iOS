import Foundation

/// Campus timetables use Gregorian dates and Monday-based teaching weeks.
enum ScheduleCalendar {
    static var campus: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        calendar.firstWeekday = 2
        return calendar
    }

    static func monday(containing date: Date, calendar: Calendar = campus) -> Date {
        let day = calendar.startOfDay(for: date)
        let offset = (calendar.component(.weekday, from: day) + 5) % 7
        return calendar.date(byAdding: .day, value: -offset, to: day) ?? day
    }

    static func weekOffset(from source: Date, to target: Date, calendar: Calendar = campus) -> Int {
        let days = calendar.dateComponents(
            [.day], from: monday(containing: source, calendar: calendar),
            to: monday(containing: target, calendar: calendar)
        ).day ?? 0
        return days / 7
    }

    static func date(
        week: Int, weekday: Int, currentWeek: Int, referenceDate: Date,
        calendar: Calendar = campus
    ) -> Date? {
        guard (1...7).contains(weekday) else { return nil }
        return calendar.date(
            byAdding: .day, value: (week - currentWeek) * 7 + weekday - 1,
            to: monday(containing: referenceDate, calendar: calendar)
        )
    }
}
