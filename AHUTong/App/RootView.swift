import SwiftUI

struct RootView: View {
    @AppStorage("theme.color") private var themeColor = "blue"
    @State private var selectedTab: AppTab = .home
    @State private var isDetailVisible = false
    @StateObject private var onboardingModel: OnboardingViewModel
    @StateObject private var appModel: AppModel

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
                LoginView(appModel: appModel)
            } else {
                ZStack(alignment: .bottom) {
                    NavigationStack {
                        destination(for: selectedTab)
                    }
                    .id(selectedTab)

                    if !isDetailVisible {
                        AndroidBottomBar(selection: $selectedTab)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(AndroidParityRootBackground())
                .onChange(of: selectedTab) { _, _ in
                    isDetailVisible = false
                }
                .onPreferenceChange(AndroidDetailVisibilityKey.self) { isDetailVisible = $0 }
            }
        }
        .task {
            async let onboarding: Void = onboardingModel.load(
                resetForUITesting: ProcessInfo.processInfo.arguments.contains("--reset-onboarding"),
                acceptForUITesting: ProcessInfo.processInfo.arguments.contains("--demo-consent")
            )
            async let session: Void = appModel.restore(
                demoSession: ProcessInfo.processInfo.arguments.contains("--demo-session")
            )
            _ = await (onboarding, session)
        }
        .tint(themeTint)
    }

    @ViewBuilder
    private func destination(for tab: AppTab) -> some View {
        switch tab {
        case .home:
            HomeView(appModel: appModel)
        case .schedule:
            ScheduleView(appModel: appModel)
        case .tools:
            ToolsView(appModel: appModel) {
                UserDefaults.standard.set(true, forKey: "home.request-edit")
                selectedTab = .home
            }
        case .settings:
            SettingsView(onboardingModel: onboardingModel, appModel: appModel)
        }
    }

    private var themeTint: Color {
        switch themeColor {
        case "green": .green
        case "purple": .purple
        case "orange": .orange
        default: AndroidParityPalette.brand
        }
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
