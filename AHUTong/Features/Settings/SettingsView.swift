import SwiftUI

struct SettingsView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.openURL) private var openURL
    @ObservedObject var onboardingModel: OnboardingViewModel
    @ObservedObject var appModel: AppModel
    @State private var showClearConfirmation = false
    @State private var showUpdateLog = false

    var body: some View {
        AndroidScreen {
            ScrollView {
                VStack(spacing: 24) {
                    AndroidHeader(title: "设置", large: true)
                    appCard
                    section("账户信息")
                    settingsGroup {
                        accountRow
                        NavigationLink {
                            AndroidPreferencesView(onboardingModel: onboardingModel, appModel: appModel).androidDetailScreen()
                        } label: {
                            AndroidSettingRow(label: "偏好设置", systemImage: "slider.horizontal.3")
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("settings.preferences")
                        AndroidSettingButton(label: "退出登录", systemImage: "rectangle.portrait.and.arrow.right") {
                            Task { await appModel.signOut() }
                        }
                    }
                    section("关于")
                    settingsGroup {
                        NavigationLink { ThirdPartyLicensesView().androidDetailScreen() } label: {
                            AndroidSettingRow(label: "开源许可证", systemImage: "doc.text")
                        }
                        .buttonStyle(.plain)
                        NavigationLink { ContributorsView().androidDetailScreen() } label: {
                            AndroidSettingRow(label: "贡献者", systemImage: "person.2")
                        }
                        .buttonStyle(.plain)
                        AndroidSettingButton(label: "意见反馈", systemImage: "bubble.left.and.exclamationmark") {
                            openURL(URL(string: "https://github.com/OpenAHU/AHUTong-iOS/issues")!)
                        }
                        AndroidSettingButton(label: "清除缓存", systemImage: "line.3.horizontal.decrease.circle") {
                            showClearConfirmation = true
                        }
                        AndroidSettingButton(label: "检查更新", systemImage: "arrow.triangle.2.circlepath") {
                            showUpdateLog = true
                        }
                        AndroidSettingButton(label: "更新说明", systemImage: "doc.text") { showUpdateLog = true }
                    }
                }
                .padding(.bottom, 96)
            }
            .scrollIndicators(.hidden)
        }
        .confirmationDialog("您的登录状态、课表等信息将会被永久清除", isPresented: $showClearConfirmation, titleVisibility: .visible) {
            Button("清除", role: .destructive) {
                Task {
                    AppDataCleaner.clearCaches()
                    await appModel.signOut()
                    await onboardingModel.resetConsent()
                }
            }
            Button("取消", role: .cancel) {}
        }
        .alert("更新说明", isPresented: $showUpdateLog) {
            Button("确定", role: .cancel) {}
        } message: {
            Text("测试版本由 GitHub Actions 构建；七天签名到期后需要重新签名安装。")
        }
    }

    private var appCard: some View {
        AndroidCard(radius: 32, background: AndroidParityPalette.primaryContainer(colorScheme)) {
            HStack(spacing: 16) {
                ZStack {
                    Capsule().fill(Color.white)
                    Image(systemName: "a.circle.fill").font(.system(size: 56, weight: .bold)).foregroundStyle(AndroidParityPalette.brand)
                }
                .frame(width: 72, height: 72)
                VStack(alignment: .leading) {
                    Text("安大通").font(.title2)
                    Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1.0").font(.headline)
                }
                Spacer()
            }
            .padding(.horizontal, 24).padding(.vertical, 16)
        }
        .padding(.horizontal, 16)
    }

    private var accountRow: some View {
        let user: User? = if case let .authenticated(user) = appModel.sessionState { user } else { nil }
        return HStack(spacing: 16) {
            Image(systemName: "person.crop.circle.fill").font(.title2).frame(width: 24)
            VStack(alignment: .leading, spacing: 3) {
                Text(user?.name ?? "未登录").font(.headline)
                Text(user?.studentID ?? "").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 24).padding(.vertical, 16)
        .background(AndroidParityPalette.surface(colorScheme))
    }

    private func section(_ text: String) -> some View {
        Text(text).font(.headline.bold()).frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 24)
    }

    private func settingsGroup<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 2, content: content).clipShape(RoundedRectangle(cornerRadius: 32)).padding(.horizontal, 16)
    }
}

private struct AndroidSettingRow: View {
    @Environment(\.colorScheme) private var colorScheme
    let label: String
    let systemImage: String
    var detail: String? = nil

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: systemImage).frame(width: 24)
            Text(label).font(.headline)
            Spacer()
            if let detail { Text(detail).font(.caption).foregroundStyle(.secondary) }
        }
        .padding(.horizontal, 24).padding(.vertical, 16)
        .background(AndroidParityPalette.surface(colorScheme)).contentShape(Rectangle())
    }
}

private struct AndroidSettingButton: View {
    let label: String
    let systemImage: String
    let action: () -> Void
    var body: some View { Button(action: action) { AndroidSettingRow(label: label, systemImage: systemImage) }.buttonStyle(.plain) }
}

@MainActor
private final class PreferencesModel: ObservableObject {
    @Published var errorMessage: String?
    private let api: any CampusCoreAPI
    private let reminder = CourseReminderCoordinator()

    init(api: any CampusCoreAPI) { self.api = api }

    func setReminders(_ enabled: Bool) async -> Bool {
        do {
            let courses = try await api.schedule()
            let week = try await api.currentWeek()
            let result = try await reminder.setEnabled(enabled, courses: courses, currentWeek: week)
            if enabled && !result { errorMessage = "未授予通知权限，无法开启课前提醒" }
            return result
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }
}

private struct AndroidPreferencesView: View {
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject var onboardingModel: OnboardingViewModel
    @StateObject private var model: PreferencesModel
    @AppStorage("home.default-payment-code") private var showPaymentCode = false
    @AppStorage("schedule.show-all") private var showAllCourses = false
    @AppStorage("notifications.course-reminders") private var reminders = false
    @AppStorage("visual.liquid-glass") private var liquidGlass = true
    @AppStorage("theme.color") private var themeColor = "blue"

    init(onboardingModel: OnboardingViewModel, appModel: AppModel) {
        self.onboardingModel = onboardingModel
        _model = StateObject(wrappedValue: PreferencesModel(api: appModel.campusAPI))
    }

    var body: some View {
        AndroidScreen {
            ScrollView {
                VStack(spacing: 24) {
                    AndroidHeader(title: "偏好设置", large: true)
                    preferenceSection("主页") {
                        Toggle("主页默认显示支付二维码", isOn: $showPaymentCode)
                        Text("校园卡可用时，首页余额入口将直接显示付款码。")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    preferenceSection("课表") {
                        Toggle("总览课表", isOn: $showAllCourses)
                        Text("显示全部周次的课程，非本周课程使用灰色标识。")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    preferenceSection("通知") {
                        Toggle("课前提醒", isOn: Binding(get: { reminders }, set: { value in
                            Task {
                                let actual = await model.setReminders(value)
                                reminders = actual
                            }
                        }))
                        Text("每节课开始前 10 分钟提醒；课表刷新后会重新安排。")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    preferenceSection("液态玻璃") {
                        Toggle("启用液态玻璃效果", isOn: $liquidGlass)
                    }
                    preferenceSection("主题颜色") {
                        Picker("主题颜色", selection: $themeColor) {
                            Text("蓝色").tag("blue"); Text("绿色").tag("green"); Text("紫色").tag("purple"); Text("橙色").tag("orange")
                        }
                        .pickerStyle(.segmented)
                    }
                    preferenceSection("协议与隐私") {
                        ForEach(AgreementDocument.allCases) { document in
                            NavigationLink { AgreementDetailView(document: document) } label: {
                                HStack { Image(systemName: "doc.text"); Text(document.title); Spacer(); Image(systemName: "chevron.right") }
                            }
                            .buttonStyle(.plain)
                        }
                        Button("撤回同意并重新确认", role: .destructive) { Task { await onboardingModel.resetConsent() } }
                    }
                }
                .padding(.bottom, 32)
            }
        }
        .alert("无法更新提醒", isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) {
            Button("确定", role: .cancel) {}
        } message: { Text(model.errorMessage ?? "") }
        .accessibilityIdentifier("preferences.screen")
    }

    private func preferenceSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title).font(.title3.bold())
            VStack(alignment: .leading, spacing: 12, content: content)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(18)
                .background(AndroidParityPalette.surface(colorScheme), in: RoundedRectangle(cornerRadius: 24))
        }
        .padding(.horizontal, 16)
    }
}

private struct ThirdPartyLicensesView: View {
    private let entries = [
        ("AHUTong SDK", "OpenAHU/AHUTong-sdk @ 8c2d6b8", "项目许可证与源码见固定子模块"),
        ("GuiXu", "Yukon163/GuiXu @ 2481ab3", "Apache License 2.0"),
        ("Rust crates", "Cargo.lock 固定依赖", "MIT / Apache-2.0 等，逐项版本见 Vendor/sdk/Cargo.lock")
    ]
    var body: some View {
        AndroidScreen {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    AndroidHeader(title: "开源许可证", large: true)
                    ForEach(entries, id: \.0) { entry in
                        VStack(alignment: .leading, spacing: 5) { Text(entry.0).font(.headline); Text(entry.1); Text(entry.2).font(.caption).foregroundStyle(.secondary) }
                            .padding(.horizontal, 24)
                    }
                }
            }
        }
    }
}

private struct ContributorsView: View {
    @Environment(\.openURL) private var openURL
    var body: some View {
        AndroidScreen {
            VStack(alignment: .leading, spacing: 24) {
                AndroidHeader(title: "贡献者", large: true)
                Text("感谢 OpenAHU 社区、Android 客户端与 iOS 迁移的所有贡献者。完整、实时名单以仓库 Contributors 页面为准。")
                    .padding(.horizontal, 24)
                Button("查看完整贡献者名单") { openURL(URL(string: "https://github.com/OpenAHU/AHUTong-iOS/graphs/contributors")!) }
                    .buttonStyle(.borderedProminent).padding(.horizontal, 24)
                Spacer()
            }
        }
    }
}

private enum AppDataCleaner {
    static func clearCaches() {
        if let support = try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: false) {
            try? FileManager.default.removeItem(at: support.appendingPathComponent("AHUTong/Cache", isDirectory: true))
        }
        ["home.widget-layout", "schedule.show-all", "schedule.preview-next", "home.default-payment-code", "notifications.course-reminders"].forEach {
            UserDefaults.standard.removeObject(forKey: $0)
        }
    }
}
