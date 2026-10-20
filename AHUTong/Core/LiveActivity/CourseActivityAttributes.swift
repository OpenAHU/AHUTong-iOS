import ActivityKit
import Foundation

struct CourseActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable, Sendable {
        let courseName: String
        let location: String
        let startDate: Date
        let endDate: Date

        func isBeforeClass(at date: Date) -> Bool { date < startDate }

        func countdownInterval(to target: Date) -> ClosedRange<Date> {
            // Bounded native timers stop at the deadline. Passing pauseTime
            // would pause immediately rather than schedule a future pause.
            min(startDate, target).addingTimeInterval(-CourseActivityTiming.preclassWindow)...target
        }
    }

    let courseID: String
}

enum CourseActivityTiming {
    static let maximumLifetime: TimeInterval = 8 * 60 * 60
    static let preclassWindow: TimeInterval = 10 * 60

    static func isWithinPreclassWindow(startDate: Date, now: Date) -> Bool {
        let remaining = startDate.timeIntervalSince(now)
        return remaining > 0 && remaining <= preclassWindow
    }
}
