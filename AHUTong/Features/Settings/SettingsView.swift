import SwiftUI

struct SettingsView: View {
    @ObservedObject var onboardingModel: OnboardingViewModel

    var body: some View {
        List {
            Section("协议与隐私") {
                ForEach(AgreementDocument.allCases) { document in
                    NavigationLink(document.title) {
                        AgreementDetailView(document: document)
                    }
                }

                Button("撤回同意并重新确认", role: .destructive) {
                    Task { await onboardingModel.resetConsent() }
                }
            }

            Section("后续迁移") {
                Text("账号、主题、提醒和缓存管理将在后续功能切片接入。")
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("设置")
    }
}
