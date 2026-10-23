import SwiftUI

struct RootView: View {
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("theme.color") private var themeColor = AndroidThemeColor.defaultValue
    @State private var selectedTab: AppTab = .home
    @StateObject private var onboardingModel: OnboardingViewModel
    @StateObject private var appModel: AppModel
    @StateObject private var grayGate = GrayFeatureGateModel()
    @StateObject private var toastCenter = AppToastCenter()
    @State private var restoredConsentKey = ""
    @StateObject private var shortcutNavigation = ShortcutNavigation.shared
    @State private var homeNavigationID = UUID()
    @State private var settingsNavigationID = UUID()
    @State private var toolsNavigationID = UUID()
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
                        NavigationStack {
                            destination(for: tab)
                        }
                        .id(navigationID(for: tab))
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
            }
        }
        .environmentObject(toastCenter)
        .defaultAppStorage(AppRuntime.sessionDefaults)
        .overlay { AppToastOverlay(center: toastCenter) }
        .task {
            if ProcessInfo.processInfo.arguments.contains("--reset-onboarding") {
                AppRuntime.sessionDefaults.removeObject(forKey: AppModel.experienceEnabledKey)
            }
            await onboardingModel.load(
                resetForUITesting: ProcessInfo.processInfo.arguments.contains("--reset-onboarding"),
                acceptForUITesting: ProcessInfo.processInfo.arguments.contains("--demo-consent")
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
            default: paymentCodeRequestID = nil
            }
            if case .experience = state, !availableTabs.contains(selectedTab) {
                selectedTab = .schedule
            }
            handleShortcutRequest()
            Task {
                await reloadGrayGate()
                await rescheduleCourseRemindersIfNeeded()
            }
        }
        .onChange(of: shortcutNavigation.pendingRequest, initial: true) { _, _ in
            handleShortcutRequest()
        }
        .onReceive(NotificationCenter.default.publisher(for: .grayFeatureOverrideChanged)) { _ in
            Task { await reloadGrayGate() }
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
            if tab == .tools || tab == .settings { resetNavigationRoot(tab) }
            selectedTab = tab
        })
    }

    private func resetNavigationRoot(_ tab: AppTab) {
        switch tab {
        case .tools: toolsNavigationID = UUID()
        case .settings: settingsNavigationID = UUID()
        default: break
        }
    }

    private func navigationID(for tab: AppTab) -> String {
        switch tab {
        case .home: homeNavigationID.uuidString
        case .settings: settingsNavigationID.uuidString
        case .tools: toolsNavigationID.uuidString
        default: tab.rawValue
        }
    }

    @ViewBuilder
    private func destination(for tab: AppTab) -> some View {
        switch tab {
        case .home:
            HomeView(
                appModel: appModel,
                homeEditEnabled: grayGate.homeEditEnabled,
                paymentCodeRequestID: paymentCodeRequestID
            ) {
                selectedTab = .schedule
            }
        case .schedule:
            ScheduleView(appModel: appModel)
        case .tools:
            ToolsView(appModel: appModel, homeEditEnabled: grayGate.homeEditEnabled, onOpenSchedule: {
                selectedTab = .schedule
            }) {
                AppRuntime.sessionDefaults.set(true, forKey: "home.request-edit")
                selectedTab = .home
            }
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
            settingsNavigationID = UUID()
            selectedTab = .settings
            toastCenter.show("付款码需要登录真实校园账号，请先登录")
        case .authenticated:
            paymentCodeRequestID = request.id
            homeNavigationID = UUID()
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
        await reloadGrayGate()
    }

    private func reloadGrayGate() async {
        let userID: String?
        if case let .authenticated(user) = appModel.sessionState { userID = user.studentID } else { userID = nil }
        await grayGate.load(
            userID: userID,
            demo: AppRuntime.isDemoSession
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
