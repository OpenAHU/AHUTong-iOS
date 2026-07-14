import SwiftUI

struct RootView: View {
    @State private var selectedTab: AppTab = .home
    @State private var isDetailVisible = false
    @StateObject private var onboardingModel: OnboardingViewModel

    init(
        consentStore: any AgreementConsentStoring = AgreementConsentStore(
            store: UserDefaultsDataStore()
        )
    ) {
        _onboardingModel = StateObject(
            wrappedValue: OnboardingViewModel(store: consentStore)
        )
    }

    var body: some View {
        Group {
            if !onboardingModel.isLoaded {
                AndroidSplashView()
            } else if !onboardingModel.consent.isComplete {
                NavigationStack {
                    OnboardingView(model: onboardingModel)
                }
            } else {
                ZStack(alignment: .bottom) {
                    TabView(selection: $selectedTab) {
                        ForEach(AppTab.allCases) { tab in
                            NavigationStack {
                                destination(for: tab)
                            }
                            .tag(tab)
                        }
                    }
                    .toolbar(.hidden, for: .tabBar)

                    if !isDetailVisible {
                        AndroidBottomBar(selection: $selectedTab)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                .background(AndroidParityRootBackground())
                .onPreferenceChange(AndroidDetailVisibilityKey.self) { isDetailVisible = $0 }
            }
        }
        .task {
            await onboardingModel.load(
                resetForUITesting: ProcessInfo.processInfo.arguments.contains("--reset-onboarding")
            )
        }
    }

    @ViewBuilder
    private func destination(for tab: AppTab) -> some View {
        switch tab {
        case .home:
            HomeView()
        case .schedule:
            ScheduleView()
        case .tools:
            ToolsView()
        case .settings:
            SettingsView(onboardingModel: onboardingModel)
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
