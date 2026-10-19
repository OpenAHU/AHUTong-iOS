import ActivityKit
import Foundation

actor CourseLiveActivityCoordinator {
    func setEnabled(
        _ enabled: Bool,
        courses: [Course],
        currentWeek: Int,
        now: Date = Date(),
        calendar: Calendar = ScheduleCalendar.campus
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
        let weekday = calendar.component(.weekday, from: now)
        let monday = calendar.date(byAdding: .day, value: -((weekday + 5) % 7), to: calendar.startOfDay(for: now)) ?? now
        let candidates = (0..<14).flatMap { offset -> [(Course, Date, Date)] in
            guard let day = calendar.date(byAdding: .day, value: offset, to: monday) else { return [] }
            let week = currentWeek + offset / 7
            let dayOfWeek = offset % 7 + 1
            return courses.filter { $0.weekday == dayOfWeek && $0.occurs(inWeek: week) }.compactMap { course in
                guard let start = ScheduleCalendar.startTime(period: course.startPeriod, on: day, calendar: calendar),
                      let end = ScheduleCalendar.endTime(period: course.endPeriod, on: day, calendar: calendar),
                      end > now else { return nil }
                return (course, start, end)
            }
        }
        return candidates.sorted { $0.1 < $1.1 }.first
    }
}
