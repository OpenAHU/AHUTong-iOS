import SwiftUI

struct RootView: View {
    @State private var selectedTab: AppTab = .home
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
                ProgressView("正在读取协议状态")
            } else if !onboardingModel.consent.isComplete {
                NavigationStack {
                    OnboardingView(model: onboardingModel)
                }
            } else {
                TabView(selection: $selectedTab) {
                    ForEach(AppTab.allCases) { tab in
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
#Preview {
    RootView()
}
