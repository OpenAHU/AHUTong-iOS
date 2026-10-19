import AppIntents
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
        let manager = SystemCourseLiveActivityManager()
        guard !arguments.contains("--demo-live-activity-clear") else {
            try? await manager.reconcile(nil)
            liveActivityFixtureStatus = "已清理"
            return
        }
        let now = Date()
        do {
            try await manager.reconcile(CourseLiveActivityPlan(
                courseID: "live-activity-ui-fixture",
                courseName: "实时活动倒计时验证",
                location: "博学南楼 A101",
                startDate: now.addingTimeInterval(90),
                endDate: now.addingTimeInterval(10 * 60)
            ))
            liveActivityFixtureStatus = "已创建"
        } catch {
            liveActivityFixtureStatus = error.localizedDescription
        }
    }
    #endif
}
