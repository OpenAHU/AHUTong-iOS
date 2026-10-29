import SwiftUI

struct RootView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("theme.color", store: AppRuntime.sessionDefaults) private var themeColor = AndroidThemeColor.defaultValue
    @State private var selectedTab: AppTab = .home
    @StateObject private var onboardingModel: OnboardingViewModel
    @StateObject private var appModel: AppModel
    @StateObject private var toastCenter = AppToastCenter()
    @State private var restoredConsentKey = ""
    @StateObject private var shortcutNavigation = ShortcutNavigation.shared
    @State private var homePath = NavigationPath()
    @State private var schedulePath = NavigationPath()
    @State private var settingsPath = NavigationPath()
    @State private var toolsPath = NavigationPath()
    @State private var toolsSearchText = ""
    @State private var toolsSearchPresented = false
    @State private var scheduleHeaderAction: ScheduleHeaderAction?
    @State private var showsScanner = false
    @State private var paymentCodeRequestID: UUID?

    init(
        consentStore: any AgreementConsentStoring = AgreementConsentStore(
            store: UserDefaultsDataStore()
        )
    ) {
        let isolated = AppRuntime.usesIsolatedUITestStorage
        let testStore = UserDefaultsDataStore(suiteName: AppRuntime.uiTestDefaultsSuite)
        _onboardingModel = StateObject(
            wrappedValue: OnboardingViewModel(store: isolated
                ? AgreementConsentStore(store: testStore) : consentStore)
        )
        if isolated {
            let secureStore = InMemorySecureStore()
            _appModel = StateObject(wrappedValue: AppModel(
                sessionStore: CampusSessionStore(secureStore: secureStore),
                credentialStore: CredentialStore(secureStore: secureStore),
                experienceScheduleStore: ExperienceScheduleStore(store: testStore),
                defaults: AppRuntime.sessionDefaults,
                accountCacheCleaner: {}
            ))
        } else {
            _appModel = StateObject(wrappedValue: AppModel())
        }
    }

    var body: some View {
        Group {
            if !onboardingModel.isLoaded {
                AppSplashView()
            } else if !onboardingModel.consent.isComplete {
                NavigationStack {
                    OnboardingView(model: onboardingModel)
                }
            } else if appModel.sessionState == .loading {
                AppSplashView()
            } else if appModel.sessionState == .signedOut {
                LoginView(appModel: appModel, onboardingModel: onboardingModel)
            } else {
                TabView(selection: tabSelection) {
                    ForEach(availableTabs) { tab in
                        NavigationStack(path: navigationPath(for: tab)) {
                            destination(for: tab)
                                .navigationDestination(for: ToolItem.self) { tool in
                                    ToolDestination(tool: tool, appModel: appModel)
                                }
                                .toolbar { rootToolbar(for: tab) }
                        }
                        .tabItem {
                            Label {
                                Text(tab.title)
                            } icon: {
                                Image(tab.iconAssetName).renderingMode(.template)
                            }
                                .accessibilityIdentifier("tab.\(tab.rawValue)")
                        }
                        .tag(tab)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(AndroidParityRootBackground())
                .sheet(isPresented: $showsScanner) { ScanView() }
            }
        }
        .environmentObject(toastCenter)
        .defaultAppStorage(AppRuntime.sessionDefaults)
        .overlay { AppToastOverlay(center: toastCenter) }
        .task {
            let isolated = AppRuntime.usesIsolatedUITestStorage
            if isolated && ProcessInfo.processInfo.arguments.contains("--reset-onboarding") {
                AppRuntime.sessionDefaults.removeObject(forKey: AppModel.experienceEnabledKey)
            }
            await onboardingModel.load(
                resetForUITesting: isolated && ProcessInfo.processInfo.arguments.contains("--reset-onboarding"),
                acceptForUITesting: isolated && ProcessInfo.processInfo.arguments.contains("--demo-consent")
            )
            await restoreForCurrentConsent()
        }
        .onChange(of: onboardingModel.consent) { _, consent in
            AppDiagnostics.shared.updateConsent(consent)
            Task {
                await restoreForCurrentConsent()
                handleShortcutRequest()
            }
        }
        .onOpenURL { url in
            if let destination = ShortcutDestination(url: url) {
                shortcutNavigation.request(destination)
                return
            }
            guard url.scheme == "ahutong" else { return }
            if url.host == "schedule" {
                selectedTab = .schedule
            }
        }
        .tint(themeTint)
        .onChange(of: selectedTab) { previous, _ in
            // Discard a departing utility/settings stack even when selection
            // changes through a deep link instead of the system tab binding.
            if previous == .tools || previous == .settings { resetNavigationRoot(previous) }
        }
        .onChange(of: appModel.sessionState) { _, state in
            switch state {
            case .authenticated: break
            default:
                paymentCodeRequestID = nil
                homePath = NavigationPath()
                schedulePath = NavigationPath()
                resetNavigationRoot(.tools)
                resetNavigationRoot(.settings)
            }
            if case .experience = state, !availableTabs.contains(selectedTab) {
                selectedTab = .schedule
            }
            handleShortcutRequest()
            Task {
                await rescheduleCourseRemindersIfNeeded()
            }
        }
        .onChange(of: shortcutNavigation.pendingRequest, initial: true) { _, _ in
            handleShortcutRequest()
        }
        .onReceive(NotificationCenter.default.publisher(for: .campusCredentialsRejected)) { _ in
            guard !AppRuntime.isDemoSession else { return }
            Task { await appModel.handleCredentialsRejected() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .campusReauthenticationRequired)) { _ in
            guard !AppRuntime.isDemoSession else { return }
            Task { await appModel.requireReauthentication() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .campusCardAutomaticLoginFailed)) { notification in
            guard let reason = notification.object as? String else { return }
            toastCenter.show("校园服务自动登录失败：\(reason)")
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSSystemTimeZoneDidChange)) { _ in
            Task { await rescheduleCourseRemindersIfNeeded() }
        }
        .onChange(of: scenePhase) { _, phase in
            Task {
                if phase == .active {
                    await SystemCourseLiveActivityManager.shared.sceneChanged(isActive: true)
                    await rescheduleCourseRemindersIfNeeded()
                } else if phase == .background {
                    await SystemCourseLiveActivityManager.shared.sceneChanged(isActive: false)
                }
            }
        }
    }

    private var tabSelection: Binding<AppTab> {
        Binding(get: { selectedTab }, set: { tab in
            withAnimation(reduceMotion ? nil : .smooth(duration: 0.3)) {
                if tab == .tools || tab == .settings { resetNavigationRoot(tab) }
                selectedTab = tab
            }
        })
    }

    @ToolbarContentBuilder
    private func rootToolbar(for tab: AppTab) -> some ToolbarContent {
        if (tab == .schedule || tab == .tools), navigationPath(for: tab).wrappedValue.isEmpty {
            // Both native bars receive the same update during the tab transition.
            // UIKit can then animate its glass group instead of crossfading two unrelated groups.
            ToolbarItemGroup(placement: .topBarTrailing) {
                if selectedTab == .schedule {
                    Button("回到当前周", systemImage: "location") { scheduleHeaderAction = .currentWeek }
                        .accessibilityIdentifier("schedule.action.回到当前周")
                    Button("课表设置", systemImage: "gearshape") { scheduleHeaderAction = .settings }
                        .accessibilityIdentifier("schedule.settings")
                    Button("刷新课表", systemImage: "arrow.clockwise") { scheduleHeaderAction = .refresh }
                        .accessibilityIdentifier("schedule.refresh")
                } else if selectedTab == .tools {
                    Button("扫一扫", systemImage: "qrcode.viewfinder") { showsScanner = true }
                        .accessibilityIdentifier("tools.scan")
                    Button("编辑首页", systemImage: "square.grid.2x2") {
                        AppRuntime.sessionDefaults.set(true, forKey: "home.request-edit")
                        selectedTab = .home
                    }
                    .accessibilityIdentifier("tools.edit-home")
                }
            }
        }
    }

    private func resetNavigationRoot(_ tab: AppTab) {
        switch tab {
        case .tools:
            toolsPath = NavigationPath()
            toolsSearchPresented = false
            toolsSearchText = ""
        case .settings: settingsPath = NavigationPath()
        case .home: homePath = NavigationPath()
        default: break
        }
    }

    private func navigationPath(for tab: AppTab) -> Binding<NavigationPath> {
        switch tab {
        case .home: $homePath
        case .schedule: $schedulePath
        case .settings: $settingsPath
        case .tools: $toolsPath
        }
    }

    @ViewBuilder
    private func destination(for tab: AppTab) -> some View {
        switch tab {
        case .home:
            HomeView(
                appModel: appModel,
                paymentCodeRequestID: paymentCodeRequestID
            ) {
                selectedTab = .schedule
            }
        case .schedule:
            ScheduleView(appModel: appModel, headerAction: $scheduleHeaderAction)
        case .tools:
            ToolsView(appModel: appModel, searchText: $toolsSearchText, searchPresented: $toolsSearchPresented, onOpenSchedule: {
                selectedTab = .schedule
            })
        case .settings:
            SettingsView(onboardingModel: onboardingModel, appModel: appModel)
        }
    }

    private func handleShortcutRequest() {
        guard onboardingModel.consent.isComplete,
              let request = shortcutNavigation.pendingRequest else { return }
        switch appModel.sessionState {
        case .loading, .signedOut:
            // Keep a cold-start request until setup and a real login finish.
            return
        case .experience:
            resetNavigationRoot(.settings)
            selectedTab = .settings
            toastCenter.show("付款码需要登录真实校园账号，请先登录")
        case .authenticated:
            paymentCodeRequestID = request.id
            resetNavigationRoot(.home)
            selectedTab = .home
        }
        shortcutNavigation.consume(request)
    }

    private var themeTint: Color {
        AndroidThemeColor.color(for: themeColor)
    }

    private var availableTabs: [AppTab] {
        if case .experience = appModel.sessionState {
            return [.schedule, .settings]
        }
        return AppTab.allCases
    }

    private func restoreForCurrentConsent() async {
        AppDiagnostics.shared.updateConsent(onboardingModel.consent)
        guard onboardingModel.isLoaded, onboardingModel.consent.isComplete else { return }
        let key = "\(onboardingModel.consent.confirmedVersion ?? 0)-\(onboardingModel.consent.privacyDecision.rawValue)-\(AppRuntime.isDemoSession)"
        guard key != restoredConsentKey else { return }
        restoredConsentKey = key
        guard appModel.sessionState == .loading || appModel.sessionState == .signedOut else {
            return
        }
        await appModel.restore(
            privacyDecision: onboardingModel.consent.privacyDecision,
            demoSession: AppRuntime.isDemoSession
        )
    }

    private func rescheduleCourseRemindersIfNeeded() async {
        guard !AppRuntime.isDemoSession else { return }
        let liveActivityEnabled = UserDefaults.standard.bool(forKey: "notifications.live-activity")
        guard case let .authenticated(user) = appModel.sessionState else {
            _ = try? await CourseLiveActivityCoordinator.shared.setEnabled(false, courses: [], currentWeek: 1)
            return
        }
        guard CourseReminderMaintenancePolicy.shouldRefresh(
            isDemoSession: AppRuntime.isDemoSession,
            remindersEnabled: UserDefaults.standard.bool(forKey: "notifications.course-reminders"),
            isAuthenticated: true,
            liveActivityEnabled: liveActivityEnabled
        ) else {
            _ = try? await CourseLiveActivityCoordinator.shared.setEnabled(false, courses: [], currentWeek: 1)
            return
        }
        do {
            async let courses = appModel.campusAPI.schedule()
            async let week = appModel.campusAPI.currentWeek()
            let (loadedCourses, loadedWeek) = try await (courses, week)
            guard case let .authenticated(currentUser) = appModel.sessionState,
                  currentUser.studentID == user.studentID else { return }
            if UserDefaults.standard.bool(forKey: "notifications.course-reminders") {
                _ = try? await CourseReminderCoordinator().setEnabled(
                    true,
                    courses: loadedCourses,
                    currentWeek: loadedWeek
                )
            }
            _ = try await CourseLiveActivityCoordinator.shared.setEnabled(
                UserDefaults.standard.bool(forKey: "notifications.live-activity"),
                courses: loadedCourses,
                currentWeek: loadedWeek
            )
        } catch {
            // Foreground maintenance is best-effort; existing pending requests remain valid.
        }
    }
}

enum CourseReminderMaintenancePolicy {
    static func shouldRefresh(
        isDemoSession: Bool,
        remindersEnabled: Bool,
        isAuthenticated: Bool,
        liveActivityEnabled: Bool = false
    ) -> Bool {
        !isDemoSession && (remindersEnabled || liveActivityEnabled) && isAuthenticated
    }
}

private struct AndroidParityRootBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        AndroidParityPalette.background(colorScheme).ignoresSafeArea()
    }
}

struct AppSplashView: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 24) {
            Image("AppMark")
                .resizable()
                .scaledToFit()
                .frame(width: 136, height: 136)
                .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
                .padding(4)
                .accessibilityLabel("安大通应用图标")
                .accessibilityIdentifier("splash.app-icon")

            Text("安大通")
                .font(.largeTitle)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AndroidParityPalette.background(colorScheme).ignoresSafeArea())
        .accessibilityIdentifier("splash.android-parity")
    }
}
#Preview {
    RootView()
}

#Preview("开屏") {
    AppSplashView()
}
