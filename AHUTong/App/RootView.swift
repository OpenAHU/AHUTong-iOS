import SwiftUI

struct RootView: View {
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("theme.color") private var themeColor = "blue"
    @State private var selectedTab: AppTab = .home
    @StateObject private var onboardingModel: OnboardingViewModel
    @StateObject private var appModel: AppModel
    @StateObject private var grayGate = GrayFeatureGateModel()
    @StateObject private var toastCenter = AppToastCenter()
    @State private var restoredConsentKey = ""
    @State private var campusCardLogin: CampusCardLoginRequest?

    init(
        consentStore: any AgreementConsentStoring = AgreementConsentStore(
            store: UserDefaultsDataStore()
        )
    ) {
        _onboardingModel = StateObject(
            wrappedValue: OnboardingViewModel(store: consentStore)
        )
        _appModel = StateObject(wrappedValue: AppModel())
    }

    var body: some View {
        Group {
            if !onboardingModel.isLoaded {
                AndroidSplashView()
            } else if !onboardingModel.consent.isComplete {
                NavigationStack {
                    OnboardingView(model: onboardingModel)
                }
            } else if appModel.sessionState == .loading {
                AndroidSplashView()
            } else if appModel.sessionState == .signedOut {
                LoginView(appModel: appModel, onboardingModel: onboardingModel)
            } else {
                TabView(selection: $selectedTab) {
                    ForEach(availableTabs) { tab in
                        NavigationStack {
                            destination(for: tab)
                        }
                        .tabItem {
                            Label(tab.title, systemImage: tab.systemImage)
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
        .overlay { AppToastOverlay(center: toastCenter) }
        .task {
            if ProcessInfo.processInfo.arguments.contains("--reset-onboarding") {
                UserDefaults.standard.removeObject(forKey: AppModel.experienceEnabledKey)
            }
            await onboardingModel.load(
                resetForUITesting: ProcessInfo.processInfo.arguments.contains("--reset-onboarding"),
                acceptForUITesting: ProcessInfo.processInfo.arguments.contains("--demo-consent")
            )
            await restoreForCurrentConsent()
        }
        .onChange(of: onboardingModel.consent) { _, _ in
            Task { await restoreForCurrentConsent() }
        }
        .onOpenURL { url in
            guard url.scheme == "ahutong" else { return }
            if url.host == "schedule" {
                selectedTab = .schedule
            }
        }
        .tint(themeTint)
        .onChange(of: appModel.sessionState) { _, state in
            if case .experience = state, !availableTabs.contains(selectedTab) {
                selectedTab = .schedule
            }
            Task { await reloadGrayGate() }
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
        .onReceive(NotificationCenter.default.publisher(for: .campusCardAuthenticationRequired)) { _ in
            guard !AppRuntime.isDemoSession else { return }
            Task {
                guard let credentials = await appModel.currentCredentials() else {
                    toastCenter.show("本机没有可用的校园账号凭据")
                    await CampusInteractiveAuthenticationCoordinator.shared.fail(
                        CampusWebAuthenticationError.credentialsUnavailable
                    )
                    return
                }
                campusCardLogin = CampusCardLoginRequest(credentials: credentials)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .campusCardAutomaticRefreshFailed)) { notification in
            guard let reason = notification.object as? String else { return }
            toastCenter.show("[测试] 校园卡自动续期失败：\(reason)")
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSSystemTimeZoneDidChange)) { _ in
            Task { await rescheduleCourseRemindersIfNeeded() }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await rescheduleCourseRemindersIfNeeded() } }
        }
        .fullScreenCover(item: $campusCardLogin) { request in
            CampusWebLoginScreen(
                mode: .visibleCampusCard(request.credentials),
                title: "校园服务登录"
            ) { result in
                switch result {
                case let .success(authentication):
                    Task {
                        do {
                            try await appModel.completeCampusCardLogin(authentication)
                            await CampusInteractiveAuthenticationCoordinator.shared.succeed()
                            NotificationCenter.default.post(name: .campusCardSessionRestored, object: nil)
                            toastCenter.show("校园卡登录已恢复")
                        } catch {
                            await CampusInteractiveAuthenticationCoordinator.shared.fail(
                                error as? CampusWebAuthenticationError ?? .invalidResponse
                            )
                            toastCenter.show(error.localizedDescription)
                        }
                    }
                case let .failure(error):
                    Task {
                        await CampusInteractiveAuthenticationCoordinator.shared.fail(
                            error as? CampusWebAuthenticationError ?? .navigationFailed
                        )
                    }
                    toastCenter.show(error.localizedDescription)
                }
            }
        }
    }

    @ViewBuilder
    private func destination(for tab: AppTab) -> some View {
        switch tab {
        case .home:
            HomeView(appModel: appModel, homeEditEnabled: grayGate.homeEditEnabled) {
                selectedTab = .schedule
            }
        case .schedule:
            ScheduleView(appModel: appModel)
        case .tools:
            ToolsView(appModel: appModel, homeEditEnabled: grayGate.homeEditEnabled) {
                UserDefaults.standard.set(true, forKey: "home.request-edit")
                selectedTab = .home
            }
        case .settings:
            SettingsView(onboardingModel: onboardingModel, appModel: appModel)
        }
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
        let isAuthenticated: Bool
        if case .authenticated = appModel.sessionState {
            isAuthenticated = true
        } else {
            isAuthenticated = false
        }
        guard CourseReminderMaintenancePolicy.shouldRefresh(
            isDemoSession: AppRuntime.isDemoSession,
            remindersEnabled: UserDefaults.standard.bool(forKey: "notifications.course-reminders"),
            isAuthenticated: isAuthenticated
        ) else { return }
        do {
            async let courses = appModel.campusAPI.schedule()
            async let week = appModel.campusAPI.currentWeek()
            let (loadedCourses, loadedWeek) = try await (courses, week)
            _ = try await CourseReminderCoordinator().setEnabled(
                true,
                courses: loadedCourses,
                currentWeek: loadedWeek
            )
        } catch {
            // Foreground maintenance is best-effort; existing pending requests remain valid.
        }
    }
}

private struct CampusCardLoginRequest: Identifiable {
    let id = UUID()
    let credentials: LoginCredentials
}

enum CourseReminderMaintenancePolicy {
    static func shouldRefresh(
        isDemoSession: Bool,
        remindersEnabled: Bool,
        isAuthenticated: Bool
    ) -> Bool {
        !isDemoSession && remindersEnabled && isAuthenticated
    }
}

private struct AndroidParityRootBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        AndroidParityPalette.background(colorScheme).ignoresSafeArea()
    }
}

private struct AndroidSplashView: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 24) {
            ZStack {
                Capsule(style: .continuous)
                    .fill(AndroidParityPalette.surface(colorScheme))
                Image(systemName: "a.circle.fill")
                    .font(.system(size: 104, weight: .bold))
                    .foregroundStyle(AndroidParityPalette.brand)
            }
            .frame(width: 136, height: 136)
            .padding(4)

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
