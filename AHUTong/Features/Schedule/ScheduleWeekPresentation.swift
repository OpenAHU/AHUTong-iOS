import SwiftUI

/// Translates the visible week without changing the school's Monday-based dates.
struct ScheduleWeekPresentation: Equatable, Sendable {
    static let sundayFirstKey = "schedule.sunday-first"
    var sundayFirst = false

    var weekdays: [Int] { sundayFirst ? [7, 1, 2, 3, 4, 5, 6] : Array(1...7) }
    // The final Sunday needs its own trailing page when the preceding Sunday
    // is shown before Monday. It is labelled 学期末, never a 21st teaching week.
    var pages: ClosedRange<Int> { 1...(sundayFirst ? 21 : 20) }

    func column(for weekday: Int) -> Int { sundayFirst ? weekday % 7 : weekday - 1 }

    func teachingWeek(weekday: Int, page: Int) -> Int {
        sundayFirst && weekday == 7 ? page - 1 : page
    }

    func page(teachingWeek: Int, weekday: Int) -> Int {
        teachingWeek + (sundayFirst && weekday == 7 ? 1 : 0)
    }

    func clamped(_ page: Int) -> Int { min(max(page, pages.lowerBound), pages.upperBound) }
    func title(page: Int) -> String { page > 20 ? "末" : String(page) }
    func accessibilityTitle(page: Int) -> String { page > 20 ? "学期末" : "第\(page)周" }

    static func weekdayTitle(_ weekday: Int) -> String {
        [1: "周一", 2: "周二", 3: "周三", 4: "周四", 5: "周五", 6: "周六", 7: "周日"][weekday] ?? ""
    }
}

enum ScheduleInactiveCourseStyle {
    static func background(_ scheme: ColorScheme) -> Color {
        Color(white: scheme == .dark ? 0.18 : 0.90)
    }
    static func foreground(_ scheme: ColorScheme) -> Color {
        Color(white: scheme == .dark ? 0.76 : 0.36)
    }
}
