import ActivityKit
import Foundation

protocol CourseLiveActivityManaging: Sendable {
    func activitiesEnabled() async -> Bool
    func reconcile(_ plan: CourseLiveActivityPlan?) async throws
}

actor SystemCourseLiveActivityManager: CourseLiveActivityManaging {
    private var revision = 0

    func activitiesEnabled() -> Bool {
        ActivityAuthorizationInfo().areActivitiesEnabled
    }

    func reconcile(_ plan: CourseLiveActivityPlan?) async throws {
        revision += 1
        let currentRevision = revision
        var retained: Activity<CourseActivityAttributes>?
        for activity in Activity<CourseActivityAttributes>.activities {
            if let plan,
               retained == nil,
               activity.attributes.courseID == plan.courseID,
               activity.content.state.startDate == plan.startDate,
               activity.content.state.endDate == plan.endDate,
               activity.activityState == .active {
                retained = activity
            } else {
                await activity.end(nil, dismissalPolicy: .immediate)
                guard revision == currentRevision else { return }
            }
        }
        guard let plan, revision == currentRevision else { return }
        let state = CourseActivityAttributes.ContentState(
            courseName: plan.courseName,
            location: plan.location,
            startDate: plan.startDate,
            endDate: plan.endDate
        )
        let content = ActivityContent(state: state, staleDate: plan.endDate)
        if let retained {
            if retained.content.state != state { await retained.update(content) }
        } else {
            _ = try Activity.request(
                attributes: CourseActivityAttributes(courseID: plan.courseID),
                content: content,
                pushType: nil
            )
        }
    }
}

actor CourseLiveActivityCoordinator {
    static let shared = CourseLiveActivityCoordinator()

    private let manager: any CourseLiveActivityManaging
    private let planner = CourseLiveActivityPlanner()
    private var revision = 0
    private var desiredEnabled = false

    init(manager: any CourseLiveActivityManaging = SystemCourseLiveActivityManager()) {
        self.manager = manager
    }

    /// Returns the accepted preference, even when no eligible course exists yet.
    func setEnabled(
        _ enabled: Bool,
        courses: [Course],
        currentWeek: Int,
        now: Date = Date(),
        calendar: Calendar = ScheduleCalendar.campus
    ) async throws -> Bool {
        revision += 1
        let currentRevision = revision
        desiredEnabled = enabled
        guard enabled else {
            try await manager.reconcile(nil)
            return desiredEnabled
        }
        let authorized = await manager.activitiesEnabled()
        guard revision == currentRevision else { return desiredEnabled }
        guard authorized else {
            desiredEnabled = false
            try await manager.reconcile(nil)
            return desiredEnabled
        }
        try await manager.reconcile(
            planner.nextCourse(courses: courses, currentWeek: currentWeek, now: now, calendar: calendar)
        )
        return desiredEnabled
    }
}
