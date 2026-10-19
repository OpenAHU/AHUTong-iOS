import Foundation

struct CourseLiveActivityPlan: Equatable, Sendable {
    let courseID: String
    let courseName: String
    let location: String
    let startDate: Date
    let endDate: Date
}

struct CourseLiveActivityPlanner: Sendable {
    // Do not start an activity that would expire before the course finishes.
    static let maximumLifetime = CourseActivityTiming.maximumLifetime

    private let periodStarts = [
        1: (8, 0), 2: (8, 50), 3: (9, 50), 4: (10, 40), 5: (11, 30),
        6: (14, 0), 7: (14, 50), 8: (15, 50), 9: (16, 40), 10: (17, 30),
        11: (19, 0), 12: (19, 50), 13: (20, 40)
    ]

    func nextCourse(
        courses: [Course],
        currentWeek: Int,
        now: Date,
        calendar: Calendar = .current
    ) -> CourseLiveActivityPlan? {
        guard currentWeek > 0 else { return nil }
        let weekday = (calendar.component(.weekday, from: now) + 5) % 7 + 1
        return courses.compactMap { course -> CourseLiveActivityPlan? in
            guard course.isStructurallyValid,
                  (1...13).contains(course.startPeriod),
                  course.duration <= 14 - course.startPeriod,
                  course.weekday == weekday,
                  course.occurs(inWeek: currentWeek),
                  let first = periodStarts[course.startPeriod],
                  let last = periodStarts[course.endPeriod],
                  let start = calendar.date(bySettingHour: first.0, minute: first.1, second: 0, of: now),
                  let lastStart = calendar.date(bySettingHour: last.0, minute: last.1, second: 0, of: now),
                  let end = calendar.date(byAdding: .minute, value: 45, to: lastStart),
                  end > now,
                  end.timeIntervalSince(now) <= Self.maximumLifetime else { return nil }
            return CourseLiveActivityPlan(
                courseID: course.id,
                courseName: course.name,
                location: course.location,
                startDate: start,
                endDate: end
            )
        }
        .sorted {
            if $0.startDate != $1.startDate { return $0.startDate < $1.startDate }
            return $0.courseID < $1.courseID
        }
        .first
    }
}
