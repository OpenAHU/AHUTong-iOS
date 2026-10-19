import Foundation

/// Campus timetables use Gregorian dates and Monday-based teaching weeks.
enum ScheduleCalendar {
    private static let periodStarts = [
        1: (8, 0), 2: (8, 50), 3: (9, 50), 4: (10, 40), 5: (11, 30),
        6: (14, 0), 7: (14, 50), 8: (15, 50), 9: (16, 40), 10: (17, 30),
        11: (19, 0), 12: (19, 50), 13: (20, 40)
    ]

    static func startTime(period: Int, on date: Date, calendar: Calendar = campus) -> Date? {
        guard let time = periodStarts[period] else { return nil }
        return calendar.date(bySettingHour: time.0, minute: time.1, second: 0, of: date)
    }

    static func endTime(period: Int, on date: Date, calendar: Calendar = campus) -> Date? {
        guard let start = startTime(period: period, on: date, calendar: calendar) else { return nil }
        return calendar.date(byAdding: .minute, value: 45, to: start)
    }

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
