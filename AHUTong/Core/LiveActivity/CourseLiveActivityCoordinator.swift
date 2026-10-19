import ActivityKit
import Foundation
import UIKit

protocol CourseLiveActivityManaging: Sendable {
    func activitiesEnabled() async -> Bool
    func reconcile(_ plan: CourseLiveActivityPlan?) async throws
}

actor SystemCourseLiveActivityManager: CourseLiveActivityManaging {
    static let shared = SystemCourseLiveActivityManager()
    private var revision = 0
    private var deadlineTask: Task<Void, Never>?
    private var stateTask: Task<Void, Never>?
    private var backgroundTask: Task<Void, Never>?
    private var isForeground = true
    private var sceneRevision = 0

    func activitiesEnabled() -> Bool {
        ActivityAuthorizationInfo().areActivitiesEnabled
    }

    func reconcile(_ plan: CourseLiveActivityPlan?) async throws {
        revision += 1
        let currentRevision = revision
        deadlineTask?.cancel()
        stateTask?.cancel()
        backgroundTask?.cancel()
        deadlineTask = nil
        stateTask = nil
        backgroundTask = nil
        await CourseActivityBackgroundExecution.end()
        guard revision == currentRevision else { return }
        let plan = plan.flatMap { $0.startDate > Date() ? $0 : nil }
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
        let content = ActivityContent(state: state, staleDate: plan.startDate)
        let current: Activity<CourseActivityAttributes>
        if let retained {
            if retained.content.state != state { await retained.update(content) }
            current = retained
        } else {
            current = try Activity.request(
                attributes: CourseActivityAttributes(courseID: plan.courseID),
                content: content,
                pushType: nil
            )
        }
        guard revision == currentRevision else { return }
        deadlineTask = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(max(0, plan.startDate.timeIntervalSinceNow))) }
            catch { return }
            await self?.finishIfCurrent(currentRevision)
        }
        stateTask = Task { [weak self] in
            for await state in current.activityStateUpdates {
                guard !Task.isCancelled else { return }
                if state == .stale || state == .ended || state == .dismissed {
                    await self?.finishIfCurrent(currentRevision)
                    return
                }
            }
        }
        if !isForeground { await sceneChanged(isActive: false) }
    }

    func sceneChanged(isActive: Bool) async {
        sceneRevision += 1
        let currentSceneRevision = sceneRevision
        isForeground = isActive
        backgroundTask?.cancel()
        backgroundTask = nil
        await CourseActivityBackgroundExecution.end()
        guard sceneRevision == currentSceneRevision,
              !isForeground, !Activity<CourseActivityAttributes>.activities.isEmpty else { return }
        let currentRevision = revision
        let remaining = await CourseActivityBackgroundExecution.begin {
            Task { await self.finishInBackground(currentRevision, scene: currentSceneRevision) }
        }
        guard revision == currentRevision, sceneRevision == currentSceneRevision else { return }
        // End early before suspension rather than leave a course activity on
        // the island after class starts. APNs is required for a deadline that
        // remains reliable after the app process is terminated.
        backgroundTask = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(max(0, min(remaining - 2, CourseActivityTiming.maximumLifetime)))) }
            catch { return }
            await self?.finishInBackground(currentRevision, scene: currentSceneRevision)
        }
    }

    private func finishInBackground(_ expected: Int, scene: Int) async {
        guard !isForeground, sceneRevision == scene else { return }
        await finishIfCurrent(expected)
    }

    private func finishIfCurrent(_ expected: Int) async {
        guard revision == expected else { return }
        try? await reconcile(nil)
    }
}

@MainActor
private enum CourseActivityBackgroundExecution {
    static var identifier: UIBackgroundTaskIdentifier = .invalid

    static func begin(expiration: @escaping @MainActor @Sendable () -> Void) -> TimeInterval {
        identifier = UIApplication.shared.beginBackgroundTask(withName: "Finish course reminder", expirationHandler: expiration)
        return UIApplication.shared.backgroundTimeRemaining
    }

    static func end() {
        guard identifier != .invalid else { return }
        UIApplication.shared.endBackgroundTask(identifier)
        identifier = .invalid
    }
}

actor CourseLiveActivityCoordinator {
    static let shared = CourseLiveActivityCoordinator()

    private let manager: any CourseLiveActivityManaging
    private let planner = CourseLiveActivityPlanner()
    private var revision = 0
    private var desiredEnabled = false

    init(manager: any CourseLiveActivityManaging = SystemCourseLiveActivityManager.shared) {
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
