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

    func nextCourse(
        courses: [Course],
        currentWeek: Int,
        now: Date,
        calendar: Calendar = ScheduleCalendar.campus
    ) -> CourseLiveActivityPlan? {
        guard currentWeek > 0 else { return nil }
        let weekday = (calendar.component(.weekday, from: now) + 5) % 7 + 1
        return courses.compactMap { course -> CourseLiveActivityPlan? in
            guard course.isStructurallyValid,
                  (1...13).contains(course.startPeriod),
                  course.duration <= 14 - course.startPeriod,
                  course.weekday == weekday,
                  course.occurs(inWeek: currentWeek),
                  let start = ScheduleCalendar.startTime(period: course.startPeriod, on: now, calendar: calendar),
                  let end = ScheduleCalendar.endTime(period: course.endPeriod, on: now, calendar: calendar),
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
