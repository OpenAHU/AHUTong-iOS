import Foundation

enum ScheduleTextFormatter {
    private static let locationReplacements = [
        "博学北楼": "博北",
        "博学南楼": "博南",
        "笃行南楼": "笃南",
        "笃行北楼": "笃北",
        "互联大楼": "互楼",
        "体育场": "体"
    ]

    static func shortLocation(_ value: String?) -> String {
        var result = value ?? ""
        for (source, replacement) in locationReplacements {
            result = result.replacingOccurrences(of: source, with: replacement)
        }
        result = result
            .replacingOccurrences(of: #"\s*\[[^\]]*]"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return result.isEmpty ? "未知" : result
    }

    static func weekRange(for course: Course) -> String {
        let weeks = Array(Set(course.activeWeeks.filter { $0 > 0 })).sorted()
        guard let first = weeks.first, let last = weeks.last else {
            if course.startWeek == course.endWeek, course.startWeek > 0 {
                return "\(course.startWeek)周"
            }
            if course.startWeek > 0, course.endWeek > 0 {
                return "\(course.startWeek)-\(course.endWeek)周"
            }
            return "周次未知"
        }
        if first == last { return "\(first)周" }
        if zip(weeks, weeks.dropFirst()).allSatisfy({ $1 - $0 == 1 }) {
            return "\(first)-\(last)周"
        }
        if zip(weeks, weeks.dropFirst()).allSatisfy({ $1 - $0 == 2 }) {
            return "\(first)-\(last)\(first.isMultiple(of: 2) ? "双" : "单")周"
        }
        return weeks.map(String.init).joined(separator: "/") + "周"
    }
}
