import AppIntents
import SwiftUI

struct SettingsView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.openURL) private var openURL
    @EnvironmentObject private var toastCenter: AppToastCenter
    @ObservedObject var onboardingModel: OnboardingViewModel
    @ObservedObject var appModel: AppModel
    @State private var showClearConfirmation = false
    @State private var showUpdateLog = false
    @State private var updateResult: AppUpdateResult?
    @State private var isCheckingUpdate = false
    @State private var feedbackMessage: String?
    @State private var showsPrivacyConsent = false

    var body: some View {
        Form {
            Section { appCard.listRowInsets(EdgeInsets()) }
            Section("账户信息") { accountCard }
            Section {
                NavigationLink {
                    AndroidPreferencesView(onboardingModel: onboardingModel, appModel: appModel).androidDetailScreen()
                } label: { Label("偏好设置", systemImage: "slider.horizontal.3") }
                .buttonStyle(SettingsPressFeedbackStyle())
                .accessibilityIdentifier("settings.preferences")
            }
            Section("关于") {
                NavigationLink { ThirdPartyLicensesView().androidDetailScreen() } label: {
                    Label("开源协议", systemImage: "doc.text")
                }
                .buttonStyle(SettingsPressFeedbackStyle())
                NavigationLink { ContributorsView().androidDetailScreen() } label: {
                    Label("贡献名单", systemImage: "person.2")
                }
                .buttonStyle(SettingsPressFeedbackStyle())
                .accessibilityIdentifier("settings.contributors")
                settingsButton("意见反馈", systemImage: AndroidParitySymbol.feedback) {
                    openURL(AgreementDocument.communityQQGroupURL) { accepted in
                        if !accepted { feedbackMessage = "请安装 QQ 后重试，或手动加入反馈群：1006203134" }
                    }
                }
                .accessibilityIdentifier("settings.feedback")
                settingsButton("清除本机数据", systemImage: "line.3.horizontal.decrease.circle") {
                    showClearConfirmation = true
                }
                .accessibilityIdentifier("settings.clear-data")
                settingsButton(isCheckingUpdate ? "正在检查…" : "检查更新", systemImage: "arrow.triangle.2.circlepath") {
                    guard !isCheckingUpdate else { return }
                    isCheckingUpdate = true
                    Task {
                        defer { isCheckingUpdate = false }
                        do {
                            let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
                            updateResult = try await AppUpdateChecker().check(currentVersion: version)
                        } catch {
                            updateResult = AppUpdateResult(message: "检查更新失败：\(error.localizedDescription)", destination: nil)
                        }
                    }
                }
                .disabled(isCheckingUpdate)
                settingsButton("更新说明", systemImage: "doc.text") { showUpdateLog = true }
                    .accessibilityIdentifier("settings.update-notes")
            }
        }
        .navigationTitle("设置")
        .navigationBarTitleDisplayMode(.large)
        .toolbar(.visible, for: .navigationBar)
        .confirmationDialog("清除本机数据？", isPresented: $showClearConfirmation, titleVisibility: .visible) {
            Button("清除", role: .destructive) {
                Task {
                    await AppDataCleaner.clearCaches()
                    await appModel.signOut()
                    await onboardingModel.resetConsent()
                }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("将退出登录，并清除课表、缓存和隐私选择。")
        }
        .alert("更新说明", isPresented: $showUpdateLog) {
            Button("确定", role: .cancel) {}
        } message: {
            Text("优化校园码、课表周指示器和贡献名单，完善 Siri 引导与课程倒计时。")
        }
        .alert("检查更新", isPresented: Binding(
            get: { updateResult != nil },
            set: { if !$0 { updateResult = nil } }
        )) {
            if let destination = updateResult?.destination {
                Button("查看") { openURL(destination) }
            }
            Button("知道了", role: .cancel) { updateResult = nil }
        } message: { Text(updateResult?.message ?? "") }
        .alert("意见反馈", isPresented: Binding(
            get: { feedbackMessage != nil },
            set: { if !$0 { feedbackMessage = nil } }
        )) {
            Button("知道了", role: .cancel) { feedbackMessage = nil }
        } message: { Text(feedbackMessage ?? "") }
        .sheet(isPresented: $showsPrivacyConsent) {
            PrivacyConsentSheet(
                accept: onboardingModel.consent.privacyDecision == .accepted ? nil : {
                    Task {
                        await onboardingModel.setPrivacyDecisionAndConfirm(.accepted)
                        await appModel.prepareForRealLogin()
                        showsPrivacyConsent = false
                        toastCenter.show("已同意，请登录校园账号")
                    }
                }
            )
        }
    }

    private var appCard: some View {
        AndroidCard(radius: 32, background: AndroidParityPalette.primaryContainer(colorScheme)) {
            HStack(spacing: 16) {
                Image("AppMark")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 72, height: 72)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                VStack(alignment: .leading) {
                    Text("安大通").font(.title2)
                    Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1.0").font(.headline)
                }
                Spacer()
            }
            .padding(.horizontal, 24).padding(.vertical, 16)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("settings.app-card")
    }

    private var accountCard: some View {
        let user: User? = switch appModel.sessionState {
        case let .authenticated(user), let .experience(user): user
        default: nil
        }
        return VStack(alignment: .leading, spacing: 28) {
            Text(user?.name ?? "未登录").font(.title2)
            Button {
                if appModel.isExperienceMode {
                    if onboardingModel.consent.privacyDecision == .accepted {
                        Task { await appModel.prepareForRealLogin() }
                    } else {
                        showsPrivacyConsent = true
                    }
                } else {
                    Task { await appModel.signOut() }
                }
            } label: {
                Label(
                    appModel.isExperienceMode ? "登录真实账号" : "重新登录",
                    systemImage: "rectangle.portrait.and.arrow.forward"
                )
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(SettingsPressFeedbackStyle())
            .accessibilityIdentifier("settings.account-login")
        }
        .padding(.vertical, 8)
    }

    private func settingsButton(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage).frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(SettingsPressFeedbackStyle())
    }

}

private struct ShortcutsGuideView: View {
    @Environment(\.openURL) private var openURL
    var body: some View {
        AndroidScreen {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    AndroidHeader(title: "Siri 与快捷指令")
                    Text("语音打开校园码，或查询某天的课表。")
                        .foregroundStyle(.secondary)
                    AndroidCard {
                        VStack(alignment: .leading, spacing: 12) {
                            Label("先允许 Siri 调用", systemImage: "mic").font(.headline)
                            Text("在系统设置中开启 Siri，并在“安大通”的“Siri”或“Apple 智能与 Siri”中，打开“与 Siri 请求搭配使用”（若有）。")
                                .font(.subheadline).foregroundStyle(.secondary)
                            Button("前往系统设置") {
                                if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                            }
                            .buttonStyle(SettingsPressFeedbackStyle())
                            .accessibilityIdentifier("shortcuts.siri-settings")
                        }
                        .frame(maxWidth: .infinity, alignment: .leading).padding(20)
                    }
                    ShortcutsLink()
                        .shortcutsLinkStyle(.automaticOutline)
                        .buttonStyle(SettingsPressFeedbackStyle(cornerRadius: 16))
                        .accessibilityIdentifier("shortcuts.open")
                    guideCard(
                        "打开付款码", icon: "qrcode",
                        phrase: "“打开安大通付款”\n“打开安大通付款码”",
                        detail: "推荐直接说完整名称。需要登录真实账号。"
                    )
                    guideCard(
                        "只说“打开校园码”", icon: "waveform",
                        phrase: "“打开校园码”",
                        detail: "在“快捷指令”中新建指令，添加安大通的“打开付款码”动作，命名为“打开校园码”。先在快捷指令中点运行一次，再对 Siri 说“运行快捷指令打开校园码”。若被当作搜索，改名为“安大通校园码”后再试。"
                    )
                    guideCard(
                        "查询指定日期课表", icon: "calendar",
                        phrase: "“用安大通查询课表”",
                        detail: "添加动作后，将日期设为“当前日期”或“每次询问”，也可连接“朗读文本”。"
                    )
                    Text("课表依据本机最近同步或导入的数据，离线也可查询；临时调课请先在 App 中刷新。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Text("找不到动作？先打开一次安大通，再到系统“快捷指令”中搜索“安大通”。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("shortcuts.discovery-help")
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
            .scrollIndicators(.hidden)
        }
        .accessibilityIdentifier("shortcuts.guide")
    }

    private func guideCard(_ title: String, icon: String, phrase: String, detail: String) -> some View {
        AndroidCard {
            VStack(alignment: .leading, spacing: 12) {
                Label(title, systemImage: icon).font(.headline)
                Text(phrase).font(.headline).foregroundStyle(.tint)
                Text(detail).font(.subheadline).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
        }
    }
}

struct SettingsPressFeedbackState: Equatable {
    let scale: CGFloat
    let opacity: Double
    let highlightOpacity: Double

    init(isPressed: Bool, reduceMotion: Bool) {
        scale = isPressed && !reduceMotion ? 0.985 : 1
        opacity = isPressed ? 0.78 : 1
        highlightOpacity = isPressed ? 0.08 : 0
    }
}

struct SettingsPressFeedbackStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let cornerRadius: CGFloat

    init(cornerRadius: CGFloat = 12) {
        self.cornerRadius = cornerRadius
    }

    func makeBody(configuration: Configuration) -> some View {
        let state = SettingsPressFeedbackState(
            isPressed: configuration.isPressed,
            reduceMotion: reduceMotion
        )
        return configuration.label
            .scaleEffect(state.scale)
            .opacity(state.opacity)
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color.primary.opacity(state.highlightOpacity))
                    .allowsHitTesting(false)
            }
            .animation(
                reduceMotion ? nil : .easeOut(duration: 0.12),
                value: configuration.isPressed
            )
            .sensoryFeedback(.impact(weight: .light, intensity: 0.55), trigger: configuration.isPressed) { oldValue, newValue in
                !oldValue && newValue
            }
    }
}

@MainActor
final class PreferencesModel: ObservableObject {
    @Published var errorMessage: String?
    @Published private(set) var isUpdatingReminders = false
    @Published private(set) var isUpdatingLiveActivity = false
    private let repository: ScheduleRepository
    private let weekRepository: ScheduleWeekRepository
    private let reminder: CourseReminderCoordinator
    private let liveActivity: CourseLiveActivityCoordinator
    private let demo: Bool

    init(
        api: any CampusCoreAPI, userID: String = "guest", demo: Bool = AppRuntime.isDemoSession,
        store: any DataStore = AppPersistence.migratingDefaults(),
        reminder: CourseReminderCoordinator = CourseReminderCoordinator(),
        liveActivity: CourseLiveActivityCoordinator = .shared
    ) {
        self.demo = demo
        self.reminder = reminder
        self.liveActivity = liveActivity
        let cache = UserScopedStore(store: store, userID: userID)
        repository = ScheduleRepository(remote: RustScheduleRemoteDataSource(api: api), cache: cache)
        weekRepository = ScheduleWeekRepository(api: api, cache: cache, semester: Semester.current())
    }

    private func schedule() async throws -> (courses: [Course], week: Int) {
        async let courses = repository.load(semester: Semester.current(), policy: .cacheFirst)
        let cachedWeek = await weekRepository.cached()
        let week = cachedWeek.isFallback ? try await weekRepository.refresh() : cachedWeek
        return (try await courses.courses, week.week)
    }

    func setReminders(_ enabled: Bool) async -> Bool {
        isUpdatingReminders = true
        defer { isUpdatingReminders = false }
        if demo {
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--demo-slow-notification-update") {
                try? await Task.sleep(for: .seconds(3))
            }
            #endif
            return enabled
        }
        do {
            // Turning a reminder off must never depend on school network availability.
            if !enabled { return try await reminder.setEnabled(false, courses: [], currentWeek: 1) }
            guard try await reminder.requestPermissionIfNeeded() else {
                errorMessage = "未授予通知权限，无法开启课前提醒"
                return false
            }
            let schedule = try await schedule()
            let result = try await reminder.setEnabled(true, courses: schedule.courses, currentWeek: schedule.week)
            if !result { errorMessage = "未授予通知权限，无法开启课前提醒" }
            return result
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func setLiveActivity(_ enabled: Bool) async -> Bool {
        isUpdatingLiveActivity = true
        defer { isUpdatingLiveActivity = false }
        if demo {
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--demo-slow-notification-update") {
                try? await Task.sleep(for: .seconds(3))
            }
            #endif
            return enabled
        }
        do {
            if !enabled { return try await liveActivity.setEnabled(false, courses: [], currentWeek: 1) }
            guard await liveActivity.activitiesEnabled() else {
                errorMessage = "系统未允许实时活动，请在系统设置中开启"
                return false
            }
            let schedule = try await schedule()
            let result = try await liveActivity.setEnabled(true, courses: schedule.courses, currentWeek: schedule.week)
            if !result { errorMessage = "系统未允许实时活动，请在系统设置中开启" }
            return result
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }
}

private struct AndroidPreferencesView: View {
    @Environment(\.openURL) private var openURL
    @EnvironmentObject private var toastCenter: AppToastCenter
    @ObservedObject private var onboardingModel: OnboardingViewModel
    @ObservedObject private var appModel: AppModel
    @StateObject private var model: PreferencesModel
    @AppStorage("notifications.course-reminders") private var reminders = false
    @AppStorage("notifications.live-activity") private var liveActivity = false
    @AppStorage("theme.color") private var themeColor = AndroidThemeColor.defaultValue
    @AppStorage private var prefersCMB: Bool
    @State private var showsCustomColor = false
    @State private var showsPrivacyConsent = false
    @State private var customColor = ""

    init(onboardingModel: OnboardingViewModel, appModel: AppModel) {
        _onboardingModel = ObservedObject(wrappedValue: onboardingModel)
        _appModel = ObservedObject(wrappedValue: appModel)
        let userID = if case let .authenticated(user) = appModel.sessionState {
            user.studentID
        } else {
            "guest"
        }
        _model = StateObject(wrappedValue: PreferencesModel(api: appModel.campusAPI, userID: userID))
        _prefersCMB = AppStorage(
            wrappedValue: false,
            AccountPreferenceKey.make("payment.cmb-card-recharge-preferred", userID: userID)
        )
    }

    var body: some View {
        Form {
            Section("隐私与登录") {
                preferenceToggle(
                    title: "保存登录信息并自动续期",
                    detail: "在本机安全保存，用于自动登录",
                    isOn: Binding(get: { onboardingModel.consent.privacyDecision == .accepted }, set: { _ in changePrivacyConsent() }),
                    identifier: "preferences.privacy-consent"
                )
                Button("查看隐私政策", systemImage: "hand.raised") { showsPrivacyConsent = true }
                    .buttonStyle(SettingsPressFeedbackStyle())
                    .accessibilityIdentifier("preferences.privacy-policy")
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("preferences.privacy-section")

            Section {
                NavigationLink {
                    ShortcutsGuideView().androidDetailScreen()
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Siri 与快捷指令")
                        Text("语音打开校园码，查询课表").font(.subheadline).foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(SettingsPressFeedbackStyle())
                .accessibilityIdentifier("preferences.shortcuts")
            }

            if !appModel.isExperienceMode {
                Section("充值") {
                    preferenceToggle(title: "总是使用招商银行充值", detail: "首页充值直接打开招商银行",
                                     isOn: $prefersCMB, identifier: "preferences.cmb-card-recharge")
                }
                Section("通知") {
                    preferenceToggle(
                        title: "课前提醒", detail: "上课前 10 分钟提醒下一节课",
                        isOn: Binding(get: { reminders }, set: { enabled in
                            reminders = enabled
                            Task { reminders = await model.setReminders(enabled) }
                        }), identifier: "preferences.course-reminders"
                    )
                    .disabled(model.isUpdatingReminders)
                    if model.isUpdatingReminders { ProgressView("正在更新提醒…").font(.footnote) }
                }
                Section {
                    preferenceToggle(
                        title: "课程倒计时岛卡", detail: "课前 10 分钟内显示，上课时结束",
                        isOn: Binding(get: { liveActivity }, set: { enabled in
                            liveActivity = enabled
                            Task { liveActivity = await model.setLiveActivity(enabled) }
                        }), identifier: "preferences.island-reminder"
                    )
                    .disabled(model.isUpdatingLiveActivity)
                    if model.isUpdatingLiveActivity { ProgressView("正在更新实时活动…").font(.footnote) }
                    Button("管理系统实时活动权限") {
                        if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                    }
                    .buttonStyle(SettingsPressFeedbackStyle())
                } header: { Text("通知增强") } footer: {
                    Text("打开 App 或刷新课表时更新。课中不显示；后台运行受限时会提前结束。")
                }
            }

            Section("主题颜色") {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 16) {
                        themeSwatch(value: customColorValue, name: "自定义", custom: true)
                        ForEach(Array(AndroidThemeColor.options.enumerated()), id: \.offset) { _, option in
                            themeSwatch(value: option.value, name: option.name)
                        }
                    }
                    .padding(.vertical, 8)
                }
            }
        }
        .navigationTitle("偏好设置")
        .navigationBarTitleDisplayMode(.inline)
        .alert("无法更新提醒", isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) {
            Button("确定", role: .cancel) {}
        } message: { Text(model.errorMessage ?? "") }
        .alert("自定义主题颜色", isPresented: $showsCustomColor) {
            TextField("#FF007FAC", text: $customColor)
            Button("取消", role: .cancel) {}
            Button("确定") {
                let value = customColor.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
                if value.range(of: "^#[0-9A-F]{8}$", options: .regularExpression) != nil {
                    themeColor = value
                }
            }
        } message: {
            Text("请输入 ARGB Hex 颜色代码（例如 #FF007FAC）")
        }
        .sheet(isPresented: $showsPrivacyConsent) {
            PrivacyConsentSheet(
                accept: onboardingModel.consent.privacyDecision == .accepted ? nil : {
                    Task {
                        await onboardingModel.setPrivacyDecisionAndConfirm(.accepted)
                        await appModel.prepareForRealLogin()
                        showsPrivacyConsent = false
                        toastCenter.show("已同意，请登录校园账号")
                    }
                }
            )
        }
        .accessibilityIdentifier("preferences.screen")
    }

    private func changePrivacyConsent() {
        if onboardingModel.consent.privacyDecision == .accepted {
            Task {
                await onboardingModel.setPrivacyDecisionAndConfirm(.declined)
                await appModel.enterExperienceMode()
                toastCenter.show("已切换为体验账户，仅保留课表和设置")
            }
        } else {
            showsPrivacyConsent = true
        }
    }

    private func preferenceToggle(
        title: String, detail: String, isOn: Binding<Bool>, identifier: String
    ) -> some View {
        Toggle(isOn: isOn) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                Text(detail).font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .accessibilityIdentifier(identifier)
        .sensoryFeedback(.selection, trigger: isOn.wrappedValue)
    }

    private var customColorValue: String {
        AndroidThemeColor.options.contains(where: { $0.value == AndroidThemeColor.canonicalValue(themeColor) }) || ["green", "purple", "orange"].contains(themeColor)
            ? "#FF007FAC"
            : themeColor
    }

    private func themeSwatch(value: String, name: String, custom: Bool = false) -> some View {
        let selected = custom
            ? !AndroidThemeColor.options.contains(where: { $0.value == AndroidThemeColor.canonicalValue(themeColor) }) && !["green", "purple", "orange"].contains(themeColor)
            : AndroidThemeColor.canonicalValue(themeColor) == value
        return Button {
            if custom {
                customColor = selected ? themeColor : ""
                showsCustomColor = true
            } else {
                themeColor = value
            }
        } label: {
            VStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(custom && !selected ? Color.secondary.opacity(0.12) : AndroidThemeColor.color(for: value))
                        .frame(width: 48, height: 48)
                    if custom && !selected {
                        Image(systemName: "plus").foregroundStyle(.secondary)
                    } else if selected {
                        Image(systemName: "checkmark").foregroundStyle(.white)
                    }
                }
                Text(name)
                    .font(.caption)
                    .foregroundStyle(selected ? AndroidThemeColor.color(for: themeColor) : .primary)
                    .fixedSize()
            }
        }
        .buttonStyle(SettingsPressFeedbackStyle())
        .accessibilityLabel(name)
        .accessibilityValue(selected ? "已选中" : "")
        .accessibilityIdentifier("preferences.theme.\(custom ? "custom" : value)")
    }
}

private struct PrivacyConsentSheet: View {
    @Environment(\.dismiss) private var dismiss
    let accept: (() -> Void)?

    var body: some View {
        NavigationStack {
            ScrollView {
                Text(AgreementDocument.privacy.body)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(20)
            }
            .navigationTitle(AgreementDocument.privacy.title)
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom) {
                HStack(spacing: 12) {
                    Button(accept == nil ? "关闭" : "取消") { dismiss() }
                        .buttonStyle(.bordered)
                    if let accept {
                        Button("同意并去登录", action: accept)
                            .buttonStyle(.borderedProminent)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(.regularMaterial)
            }
        }
        .presentationDetents([.large])
        .accessibilityIdentifier("settings.privacy-consent-sheet")
    }
}

struct IOSLicenseEntry: Identifiable, Equatable, Sendable {
    let name: String
    let author: String
    let url: URL
    let license: String
    let bundledDocuments: [String]

    var id: String { name }
}

enum IOSLicenseCatalog {
    static let entries = [
        IOSLicenseEntry(
            name: "Sentry SDK 9.31.0",
            author: "Sentry",
            url: URL(string: "https://github.com/getsentry/sentry-cocoa")!,
            license: "MIT License",
            bundledDocuments: ["Sentry-LICENSE.txt"]
        ),
        IOSLicenseEntry(
            name: "Material Icons",
            author: "The Android Open Source Project",
            url: URL(string: "https://github.com/google/material-design-icons")!,
            license: "Apache License 2.0",
            bundledDocuments: ["MaterialIcons-NOTICE.txt", "MaterialIcons-LICENSE.txt"]
        ),
        IOSLicenseEntry(
            name: "GuiXu (Rust rewrite)",
            author: "Delsart 与 GuiXu Rust contributors",
            url: URL(string: "https://github.com/Yukon163/GuiXu/tree/rust-rewrite")!,
            license: "Apache License 2.0",
            bundledDocuments: ["NOTICE", "LICENSE"]
        ),
        IOSLicenseEntry(
            name: "AHUTong Rust SDK",
            author: "OpenAHU contributors",
            url: URL(string: "https://github.com/OpenAHU/AHUTong-sdk")!,
            license: "源码仓库尚未声明独立许可证",
            bundledDocuments: []
        ),
        IOSLicenseEntry(
            name: "Rust dependency inventory",
            author: "各 crate 作者",
            url: URL(string: "https://github.com/OpenAHU/AHUTong-sdk/blob/master/Cargo.lock")!,
            license: "精确版本由随构建固定的 Cargo.lock 记录；各项遵循其上游许可证",
            bundledDocuments: []
        )
    ]
}

private struct ThirdPartyLicensesView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.openURL) private var openURL
    @State private var selectedEntry: IOSLicenseEntry?

    var body: some View {
        AndroidScreen {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    AndroidHeader(title: "开源许可证", large: true)
                    ForEach(IOSLicenseCatalog.entries) { entry in
                        Button {
                            if entry.bundledDocuments.isEmpty {
                                openURL(entry.url)
                            } else {
                                selectedEntry = entry
                            }
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(entry.name).font(.headline).foregroundStyle(.primary)
                                    Text(entry.author).foregroundStyle(.primary)
                                    Text(entry.license).font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: entry.bundledDocuments.isEmpty ? "arrow.up.right.square" : "doc.text.magnifyingglass")
                                    .foregroundStyle(AndroidParityPalette.systemTheme)
                            }
                            .padding(16)
                            .background(AndroidParityPalette.surface(colorScheme), in: RoundedRectangle(cornerRadius: 16))
                        }
                        .buttonStyle(SettingsPressFeedbackStyle(cornerRadius: 16))
                        .padding(.horizontal, 16)
                    }
                }
            }
        }
        .sheet(item: $selectedEntry) { entry in
            NavigationStack {
                ScrollView {
                    Text(bundledText(for: entry))
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(20)
                }
                .navigationTitle(entry.name)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("关闭") { selectedEntry = nil }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("查看源码") { openURL(entry.url) }
                    }
                }
            }
        }
    }

    private func bundledText(for entry: IOSLicenseEntry) -> String {
        entry.bundledDocuments.map { resource in
            guard let url = Bundle.main.url(forResource: resource, withExtension: nil),
                  let value = try? String(contentsOf: url, encoding: .utf8) else {
                return "无法读取 \(resource)"
            }
            return value
        }
        .joined(separator: "\n\n")
    }
}

@MainActor
enum AppDataCleaner {
    static func clearCaches() async {
        _ = try? await CourseLiveActivityCoordinator.shared.setEnabled(false, courses: [], currentWeek: 1)
        await AppPersistence.clearCaches()
        if let support = try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: false) {
            try? FileManager.default.removeItem(at: support.appendingPathComponent("AHUTong/Cache", isDirectory: true))
            try? FileManager.default.removeItem(at: support.appendingPathComponent("AHUTong/Repository", isDirectory: true))
            try? FileManager.default.removeItem(at: support.appendingPathComponent("AHUTong/schedule-widget.json"))
        }
        let exact = ["home.widget-layout", "schedule.show-all", "schedule.preview-next", "home.default-payment-code", "notifications.course-reminders", "notifications.live-activity"]
        let prefixes = ["campus-card.balance.", "payments.pending-order.", DebugRuntimeSettings.endpointKeyPrefix]
        for key in UserDefaults.standard.dictionaryRepresentation().keys where exact.contains(key) || prefixes.contains(where: key.hasPrefix) {
            UserDefaults.standard.removeObject(forKey: key)
        }
        try? await AppRuntime.widgetSnapshotStore.save(.unavailable(.signedOut))
    }
}
