import SwiftUI

struct SettingsView: View {
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject var onboardingModel: OnboardingViewModel
    @State private var showClearConfirmation = false
    @State private var showUpdateLog = false

    var body: some View {
        AndroidScreen {
            ScrollView {
                VStack(spacing: 24) {
                    AndroidHeader(title: "设置", large: true)
                    appCard

                    Text("账户信息")
                        .font(.headline)
                        .fontWeight(.bold)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 24)

                    settingsGroup {
                        NavigationLink {
                            AndroidPreferencesView(onboardingModel: onboardingModel)
                                .androidDetailScreen()
                        } label: {
                            AndroidSettingRow(label: "偏好设置", systemImage: "slider.horizontal.3")
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("settings.preferences")
                    }

                    Text("关于")
                        .font(.headline)
                        .fontWeight(.bold)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 24)

                    settingsGroup {
                        NavigationLink {
                            AndroidTextPage(title: "开源许可证", text: "第三方许可证清单将在正式依赖锁定后生成。")
                                .androidDetailScreen()
                        } label: {
                            AndroidSettingRow(label: "开源许可证", systemImage: "doc.text")
                        }
                        .buttonStyle(.plain)

                        NavigationLink {
                            AndroidTextPage(title: "贡献者", text: "感谢所有参与安大通建设的贡献者。")
                                .androidDetailScreen()
                        } label: {
                            AndroidSettingRow(label: "贡献者", systemImage: "person.2")
                        }
                        .buttonStyle(.plain)

                        AndroidSettingButton(label: "意见反馈", systemImage: "bubble.left.and.exclamationmark") {}
                        AndroidSettingButton(label: "清除缓存", systemImage: "line.3.horizontal.decrease.circle") {
                            showClearConfirmation = true
                        }
                        AndroidSettingButton(label: "检查更新", systemImage: "arrow.triangle.2.circlepath") {
                            showUpdateLog = true
                        }
                        AndroidSettingButton(label: "更新说明", systemImage: "doc.text") {
                            showUpdateLog = true
                        }
                    }
                }
                .padding(.bottom, 96)
            }
            .scrollIndicators(.hidden)
        }
        .confirmationDialog(
            "您的登录状态、课表等信息将会被永久清除",
            isPresented: $showClearConfirmation,
            titleVisibility: .visible
        ) {
            Button("清除", role: .destructive) {
                Task { await onboardingModel.resetConsent() }
            }
            Button("取消", role: .cancel) {}
        }
        .alert("更新说明", isPresented: $showUpdateLog) {
            Button("确定", role: .cancel) {}
        } message: {
            Text("当前为迁移测试版本，请通过 GitHub Actions 获取最新构建。")
        }
        .accessibilityIdentifier("screen.settings")
    }

    private var appCard: some View {
        AndroidCard(radius: 32, background: AndroidParityPalette.primaryContainer(colorScheme)) {
            HStack(spacing: 16) {
                ZStack {
                    Capsule().fill(Color.white)
                    Image(systemName: "a.circle.fill")
                        .font(.system(size: 56, weight: .bold))
                        .foregroundStyle(AndroidParityPalette.brand)
                }
                .frame(width: 72, height: 72)

                VStack(alignment: .leading) {
                    Text("安大通").font(.title2)
                    Text("0.1.0").font(.headline)
                }
                Spacer()
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
        }
        .padding(.horizontal, 16)
    }

    private func settingsGroup<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 2, content: content)
            .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
            .padding(.horizontal, 16)
    }
}

private struct AndroidSettingRow: View {
    @Environment(\.colorScheme) private var colorScheme
    let label: String
    let systemImage: String

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: systemImage).frame(width: 24)
            Text(label).font(.headline)
            Spacer()
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
        .background(AndroidParityPalette.surface(colorScheme))
        .contentShape(Rectangle())
    }
}

private struct AndroidSettingButton: View {
    let label: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            AndroidSettingRow(label: label, systemImage: systemImage)
        }
        .buttonStyle(.plain)
    }
}

private struct AndroidPreferencesView: View {
    @ObservedObject var onboardingModel: OnboardingViewModel

    var body: some View {
        AndroidScreen {
            ScrollView {
                VStack(spacing: 24) {
                    AndroidHeader(title: "偏好设置", large: true)

                    Text("协议与隐私")
                        .font(.headline)
                        .fontWeight(.bold)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 24)

                    VStack(spacing: 2) {
                        ForEach(AgreementDocument.allCases) { document in
                            NavigationLink {
                                AgreementDetailView(document: document)
                            } label: {
                                AndroidSettingRow(label: document.title, systemImage: "doc.text")
                            }
                            .buttonStyle(.plain)
                        }
                        AndroidSettingButton(label: "撤回同意并重新确认", systemImage: "arrow.uturn.backward") {
                            Task { await onboardingModel.resetConsent() }
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
                    .padding(.horizontal, 16)
                }
            }
        }
    }
}

private struct AndroidTextPage: View {
    let title: String
    let text: String

    var body: some View {
        AndroidScreen {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    AndroidHeader(title: title, large: true)
                    Text(text).font(.body).padding(.horizontal, 24)
                }
            }
        }
    }
}
