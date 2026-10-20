import AppIntents
import ActivityKit
import SwiftUI

@main
struct AHUTongApp: App {
    #if DEBUG
    @Environment(\.scenePhase) private var scenePhase
    @State private var liveActivityFixtureStatus = ""
    #endif
    init() {
        RetiredPreferenceCleaner.clean()
        AHUTongShortcuts.updateAppShortcutParameters()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                #if DEBUG
                .task(id: scenePhase) {
                    if scenePhase == .active { await runLiveActivityUITestFixture() }
                }
                .overlay(alignment: .bottom) {
                    if ProcessInfo.processInfo.arguments.contains("--demo-live-activity") {
                        Text(liveActivityFixtureStatus)
                            .accessibilityIdentifier("live-activity.fixture.status")
                    }
                }
                #endif
        }
    }

    #if DEBUG
    private func runLiveActivityUITestFixture() async {
        let arguments = ProcessInfo.processInfo.arguments
        guard AppRuntime.isDemoSession, arguments.contains("--demo-live-activity") else { return }
        let manager = SystemCourseLiveActivityManager.shared
        guard !arguments.contains("--demo-live-activity-clear") else {
            try? await manager.reconcile(nil)
            liveActivityFixtureStatus = "已清理"
            return
        }
        let now = Date()
        let leadTime: TimeInterval = arguments.contains("--demo-live-activity-too-early") ? 10_038
            : arguments.contains("--demo-live-activity-ten-minutes") ? 600 : 90
        do {
            try await manager.reconcile(CourseLiveActivityPlan(
                courseID: "live-activity-ui-fixture",
                courseName: "数据库原理与应用",
                location: "博学南楼 B101",
                startDate: now.addingTimeInterval(leadTime),
                endDate: now.addingTimeInterval(leadTime + 95 * 60)
            ))
            liveActivityFixtureStatus = Activity<CourseActivityAttributes>.activities.isEmpty ? "未创建" : "已创建"
            if let activity = Activity<CourseActivityAttributes>.activities.first(where: { $0.attributes.courseID == "live-activity-ui-fixture" }) {
                for await state in activity.activityStateUpdates {
                    guard !Task.isCancelled else { return }
                    if state == .ended || state == .dismissed {
                        liveActivityFixtureStatus = "已结束"
                        return
                    }
                }
            }
        } catch {
            liveActivityFixtureStatus = error.localizedDescription
        }
    }
    #endif
}
