import ActivityKit
import Foundation

actor CourseLiveActivityCoordinator {
    func setEnabled(
        _ enabled: Bool,
        courses: [Course],
        currentWeek: Int,
        now: Date = Date(),
        calendar: Calendar = .current
    ) async throws -> Bool {
        for activity in Activity<CourseActivityAttributes>.activities {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
        guard enabled else { return false }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return false }
        guard let next = nextCourse(courses: courses, currentWeek: currentWeek, now: now, calendar: calendar) else {
            return false
        }

        let attributes = CourseActivityAttributes(courseID: next.course.id)
        let state = CourseActivityAttributes.ContentState(
            courseName: next.course.name,
            location: next.course.location,
            startDate: next.start,
            endDate: next.end
        )
        let content = ActivityContent(state: state, staleDate: next.end)
        _ = try Activity.request(attributes: attributes, content: content, pushType: nil)
        return true
    }

    private func nextCourse(
        courses: [Course],
        currentWeek: Int,
        now: Date,
        calendar: Calendar
    ) -> (course: Course, start: Date, end: Date)? {
        let times = [
            1: (8, 0), 2: (8, 50), 3: (9, 50), 4: (10, 40), 5: (11, 30),
            6: (14, 0), 7: (14, 50), 8: (15, 50), 9: (16, 40), 10: (17, 30),
            11: (19, 0), 12: (19, 50), 13: (20, 40)
        ]
        let weekday = calendar.component(.weekday, from: now)
        let monday = calendar.date(byAdding: .day, value: -((weekday + 5) % 7), to: calendar.startOfDay(for: now)) ?? now
        let candidates = (0..<14).flatMap { offset -> [(Course, Date, Date)] in
            guard let day = calendar.date(byAdding: .day, value: offset, to: monday) else { return [] }
            let week = currentWeek + offset / 7
            let dayOfWeek = offset % 7 + 1
            return courses.filter { $0.weekday == dayOfWeek && $0.occurs(inWeek: week) }.compactMap { course in
                guard let value = times[course.startPeriod],
                      let start = calendar.date(bySettingHour: value.0, minute: value.1, second: 0, of: day),
                      let end = calendar.date(byAdding: .minute, value: max(1, course.duration) * 50 - 5, to: start),
                      end > now else { return nil }
                return (course, start, end)
            }
        }
        return candidates.sorted { $0.1 < $1.1 }.first
    }
}
