import SwiftUI

struct SettingsView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.openURL) private var openURL
    @ObservedObject var onboardingModel: OnboardingViewModel
    @ObservedObject var appModel: AppModel
    @State private var showClearConfirmation = false
    @State private var showUpdateLog = false
    @State private var updateResult: AppUpdateResult?
    @State private var isCheckingUpdate = false
    @State private var feedbackMessage: String?
    @State private var debugTapCount = 0
    @State private var lastDebugTap = Date.distantPast
    @State private var showsDebug = false

    var body: some View {
        AndroidScreen {
            ScrollView {
                VStack(spacing: 24) {
                    AndroidHeader(title: "设置", large: true)
                    appCard
                    section("账户信息")
                    accountCard
                    NavigationLink {
                        AndroidPreferencesView(onboardingModel: onboardingModel, appModel: appModel).androidDetailScreen()
                    } label: {
                        AndroidSettingRow(label: "偏好设置", systemImage: "slider.horizontal.3")
                            .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
                            .padding(.horizontal, 16)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("settings.preferences")
                    section("关于")
                    settingsGroup {
                        NavigationLink { ThirdPartyLicensesView().androidDetailScreen() } label: {
                            AndroidSettingRow(label: "开源协议", systemImage: "doc.text")
                        }
                        .buttonStyle(.plain)
                        NavigationLink { ContributorsView().androidDetailScreen() } label: {
                            AndroidSettingRow(label: "贡献名单", systemImage: "person.2")
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("settings.contributors")
                        NavigationLink {
                            OperationsDiagnosticsView(userID: currentUser?.studentID, appModel: appModel).androidDetailScreen()
                        } label: {
                            AndroidSettingRow(label: "Debug", systemImage: "terminal")
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("settings.debug")
                        AndroidSettingButton(label: "意见反馈", systemImage: AndroidParitySymbol.feedback) {
                            let url = URL(string: "mqqapi://card/show_pslcard?src_type=internal&version=1&uin=1006203134&card_type=group&source=qrcode")!
                            openURL(url) { accepted in
                                if !accepted { feedbackMessage = "请安装 QQ 后重试，或手动加入反馈群：1006203134" }
                            }
                        }
                        .accessibilityIdentifier("settings.feedback")
                        AndroidSettingButton(label: "清除缓存", systemImage: "line.3.horizontal.decrease.circle") {
                            showClearConfirmation = true
                        }
                        AndroidSettingButton(label: "检查更新", systemImage: "arrow.triangle.2.circlepath") {
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
                    await AppDataCleaner.clearCaches()
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
        .navigationDestination(isPresented: $showsDebug) {
            OperationsDiagnosticsView(userID: currentUser?.studentID, appModel: appModel).androidDetailScreen()
        }
    }

    private var appCard: some View {
        AndroidCard(radius: 32, background: AndroidParityPalette.primaryContainer(colorScheme)) {
            HStack(spacing: 16) {
                AndroidAppMark()
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
        .contentShape(Rectangle())
        .onTapGesture(perform: registerDebugTap)
        .accessibilityIdentifier("settings.app-card")
    }

    private var accountCard: some View {
        let user: User? = if case let .authenticated(user) = appModel.sessionState { user } else { nil }
        return VStack(alignment: .leading, spacing: 28) {
            Text(user?.name ?? "未登录").font(.title2)
            Button {
                Task { await appModel.signOut() }
            } label: {
                Label("重新登录", systemImage: "rectangle.portrait.and.arrow.forward")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.plain)
        }
        .padding(24)
        .background(AndroidParityPalette.surface(colorScheme), in: RoundedRectangle(cornerRadius: 32, style: .continuous))
        .padding(.horizontal, 16)
    }

    private func section(_ text: String) -> some View {
        Text(text).font(.headline.bold()).frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 24)
    }

    private var currentUser: User? {
        if case let .authenticated(user) = appModel.sessionState { return user }
        return nil
    }

    private func registerDebugTap() {
        let now = Date()
        debugTapCount = now.timeIntervalSince(lastDebugTap) <= 1 ? debugTapCount + 1 : 1
        lastDebugTap = now
        if debugTapCount >= 8 {
            debugTapCount = 0
            showsDebug = true
        }
    }

    private func settingsGroup<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 2, content: content).clipShape(RoundedRectangle(cornerRadius: 32)).padding(.horizontal, 16)
    }
}

private struct AndroidAppMark: View {
    var body: some View {
        VStack(spacing: 2) {
            Text("安大通")
                .androidScaledFont(size: 12, relativeTo: .caption, weight: .bold)
                .foregroundStyle(.white)
                .padding(.horizontal, 6).padding(.vertical, 3)
                .background(Color(red: 240 / 255, green: 112 / 255, blue: 62 / 255), in: RoundedRectangle(cornerRadius: 3))
            Image(systemName: "building.columns")
                .font(.system(size: 27, weight: .light))
                .foregroundStyle(.gray)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.white, in: Circle())
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
final class PreferencesModel: ObservableObject {
    @Published var errorMessage: String?
    private let api: any CampusCoreAPI
    private let reminder = CourseReminderCoordinator()
    private let liveActivity = CourseLiveActivityCoordinator()
    private let demo: Bool

    init(api: any CampusCoreAPI, demo: Bool = AppRuntime.isDemoSession) {
        self.api = api
        self.demo = demo
    }

    func setReminders(_ enabled: Bool) async -> Bool {
        // UI parity fixtures must not inherit notification authorization left by
        // another Simulator test. Production still exercises UserNotifications.
        if demo { return enabled }
        do {
            let courses = try await api.schedule()
            let week = try await api.currentWeek()
            let result = try await reminder.setEnabled(
                enabled,
                courses: courses,
                currentWeek: week,
                now: Date()
            )
            if enabled && !result { errorMessage = "未授予通知权限，无法开启课前提醒" }
            return result
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func setLiveActivity(_ enabled: Bool) async -> Bool {
        if demo { return enabled }
        do {
            async let courses = api.schedule()
            async let week = api.currentWeek()
            let (loadedCourses, loadedWeek) = try await (courses, week)
            let result = try await liveActivity.setEnabled(
                enabled,
                courses: loadedCourses,
                currentWeek: loadedWeek
            )
            if enabled && !result { errorMessage = "系统未允许实时活动，或未来两周暂无课程" }
            return result
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }
}

private struct AndroidPreferencesView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.openURL) private var openURL
    @StateObject private var model: PreferencesModel
    @AppStorage("notifications.course-reminders") private var reminders = false
    @AppStorage("notifications.live-activity") private var liveActivity = false
    @AppStorage("visual.liquid-glass") private var liquidGlass = true
    @AppStorage("theme.color") private var themeColor = "blue"
    @State private var showsIslandExplanation = false
    @State private var showsCustomColor = false
    @State private var customColor = ""

    init(onboardingModel: OnboardingViewModel, appModel: AppModel) {
        _ = onboardingModel
        _model = StateObject(wrappedValue: PreferencesModel(api: appModel.campusAPI))
    }

    var body: some View {
        AndroidScreen {
            ScrollView {
                VStack(spacing: 24) {
                    Text("偏好设置")
                        .font(.largeTitle)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 32)

                    preferenceSection("通知") {
                        preferenceRow(
                            title: "课前提醒",
                            detail: "上课前 10 分钟提醒下一节课",
                            isOn: reminders,
                            identifier: "preferences.course-reminders"
                        ) {
                            Task {
                                let actual = await model.setReminders(!reminders)
                                reminders = actual
                            }
                        }
                    }

                    preferenceSection("通知增强") {
                        preferenceRow(
                            title: "课前倒计时岛卡提醒（实验性）",
                            detail: "仅部分系统支持 需同时开启课前提醒",
                            isOn: liveActivity,
                            identifier: "preferences.island-reminder"
                        ) {
                            guard reminders || liveActivity else {
                                model.errorMessage = "请先开启课前提醒"
                                return
                            }
                            Task { liveActivity = await model.setLiveActivity(!liveActivity) }
                        }
                        Button("管理系统实时活动权限") {
                            if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                        }
                            .frame(maxWidth: .infinity, alignment: .trailing)
                            .buttonStyle(.plain)
                            .foregroundStyle(AndroidThemeColor.color(for: themeColor))
                            .padding(.vertical, 8)
                    }

                    preferenceSection("液态玻璃") {
                        preferenceRow(title: "启用液态玻璃效果", isOn: liquidGlass, identifier: "preferences.liquid-glass") {
                            liquidGlass.toggle()
                        }
                    }

                    preferenceSection("主题颜色") {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(alignment: .top, spacing: 16) {
                                themeSwatch(value: customColorValue, name: "自定义", custom: true)
                                ForEach(Array(AndroidThemeColor.options.enumerated()), id: \.offset) { _, option in
                                    themeSwatch(value: option.value, name: option.name)
                                }
                            }
                        }
                    }
                }
                .padding(16)
                .padding(.bottom, 64)
            }
        }
        .alert("无法更新提醒", isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) {
            Button("确定", role: .cancel) {}
        } message: { Text(model.errorMessage ?? "") }
        .alert("iOS 平台说明", isPresented: $showsIslandExplanation) {
            Button("确定", role: .cancel) {}
        } message: {
            Text("iOS 使用 Live Activity 在锁定屏幕和灵动岛显示下一节课倒计时。可在“设置 → 安大通 → 实时活动”中管理系统权限。")
        }
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
        .accessibilityIdentifier("preferences.screen")
    }

    private func preferenceSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title).font(.title3)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(AndroidParityPalette.surface(colorScheme), in: RoundedRectangle(cornerRadius: 16))
    }

    private func preferenceRow(
        title: String,
        detail: String? = nil,
        isOn: Bool,
        identifier: String? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).foregroundStyle(.primary)
                    if let detail {
                        Text(detail)
                            .font(.subheadline)
                            .foregroundStyle(AndroidParityPalette.secondaryText(colorScheme))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                AndroidPreferenceToggle(isOn: isOn)
            }
            .padding(.vertical, 8)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(identifier ?? "")
        .accessibilityValue(isOn ? "开启" : "关闭")
    }

    private var customColorValue: String {
        AndroidThemeColor.options.contains(where: { $0.value == themeColor }) || ["blue", "green", "purple", "orange"].contains(themeColor)
            ? "#FF007FAC"
            : themeColor
    }

    private func themeSwatch(value: String, name: String, custom: Bool = false) -> some View {
        let selected = custom
            ? !AndroidThemeColor.options.contains(where: { $0.value == themeColor }) && !["blue", "green", "purple", "orange"].contains(themeColor)
            : themeColor == value || (value == "default" && themeColor == "blue")
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
        .buttonStyle(.plain)
    }
}

private struct AndroidPreferenceToggle: View {
    let isOn: Bool

    var body: some View {
        ZStack(alignment: isOn ? .trailing : .leading) {
            Capsule()
                .fill(isOn ? AndroidParityPalette.liquidToggle : Color.secondary.opacity(0.24))
                .frame(width: 52, height: 32)
            Circle()
                .fill(.white)
                .frame(width: 26, height: 26)
                .padding(3)
                .shadow(color: .black.opacity(0.12), radius: 2, y: 1)
        }
        .animation(.easeInOut(duration: 0.18), value: isOn)
        .accessibilityValue(isOn ? "开启" : "关闭")
    }
}

private struct ThirdPartyLicensesView: View {
    @Environment(\.colorScheme) private var colorScheme
    private let entries = [
        LicenseEntry(name: "AndroidX", author: "Google", url: "https://source.android.com", license: "Apache Software License 2.0"),
        LicenseEntry(name: "Material", author: "Google", url: "https://source.android.com", license: "Apache Software License 2.0"),
        LicenseEntry(name: "Gson", author: "Google", url: "https://github.com/google/gson", license: "Apache Software License 2.0"),
        LicenseEntry(name: "OkHttp", author: "Square", url: "https://github.com/square/okhttp", license: "Apache Software License 2.0"),
        LicenseEntry(name: "Retrofit", author: "Square", url: "https://github.com/square/retrofit", license: "Apache Software License 2.0"),
        LicenseEntry(name: "Jsoup", author: "jsoup.org", url: "https://jsoup.org/", license: "MIT License"),
        LicenseEntry(name: "MMKV", author: "Tencent", url: "https://github.com/Tencent/MMKV", license: "BSD 3-Clause License"),
        LicenseEntry(name: "Coil", author: "Coil Contributors", url: "https://github.com/coil-kt/coil", license: "Apache Software License 2.0"),
        LicenseEntry(name: "PersistentCookieJar", author: "Fran Montiel", url: "https://github.com/franmontiel/PersistentCookieJar", license: "Apache Software License 2.0"),
        LicenseEntry(name: "ZXing Android Embedded", author: "JourneyApps", url: "https://github.com/journeyapps/zxing-android-embedded", license: "Apache Software License 2.0"),
        LicenseEntry(name: "Monet", author: "Kyant0", url: "https://github.com/Kyant0/Monet", license: "Apache Software License 2.0"),
        LicenseEntry(name: "Backdrop", author: "Kyant0", url: "https://github.com/Kyant0/AndroidLiquidGlass", license: "Apache Software License 2.0"),
        LicenseEntry(name: "Capsule", author: "Kyant0", url: "https://github.com/Kyant0/Capsule", license: "Apache Software License 2.0"),
        LicenseEntry(name: "AHUTong SDK / GuiXu / Rust crates", author: "OpenAHU 与各 crate 作者", url: "https://github.com/OpenAHU/AHUTong-sdk", license: "版本与许可证由 Cargo.lock 固定")
    ]
    var body: some View {
        AndroidScreen {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    AndroidHeader(title: "开源许可证", large: true)
                    ForEach(entries) { entry in
                        Link(destination: entry.url) {
                            HStack {
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(entry.name).font(.headline).foregroundStyle(.primary)
                                    Text(entry.author).foregroundStyle(.primary)
                                    Text(entry.license).font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "arrow.up.right.square").foregroundStyle(AndroidParityPalette.systemTheme)
                            }
                            .padding(16)
                            .background(AndroidParityPalette.surface(colorScheme), in: RoundedRectangle(cornerRadius: 16))
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 16)
                    }
                }
            }
        }
    }

    private struct LicenseEntry: Identifiable {
        let name: String
        let author: String
        let url: URL
        let license: String

        var id: String { name }

        init(name: String, author: String, url: String, license: String) {
            self.name = name
            self.author = author
            self.url = URL(string: url)!
            self.license = license
        }
    }
}

struct ContributorEntry: Identifiable, Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        case partner
        case developer(qq: String)
    }

    let name: String
    let description: String
    let kind: Kind

    var id: String {
        switch kind {
        case .partner: "partner-\(name)"
        case let .developer(qq): "developer-\(qq)"
        }
    }

    var qq: String? {
        guard case let .developer(qq) = kind else { return nil }
        return qq
    }

    var avatarURL: URL? {
        guard let qq else { return nil }
        return URL(string: "https://q1.qlogo.cn/g?b=qq&nk=\(qq)&s=640")
    }

    var contactURL: URL? {
        guard let qq else { return nil }
        return URL(string: "mqqapi://card/show_pslcard?&uin=\(qq)")
    }
}

enum ContributorsCatalog {
    static let partners = [
        ContributorEntry(
            name: "Hello~",
            description: "We are waiting for you!\nGet connection with us now!\nClick me for more info!",
            kind: .partner
        )
    ]

    static let developers = [
        ContributorEntry(name: "高玉灿（20级）", description: "架构规划、页面设计、爬虫", kind: .developer(qq: "468766131")),
        ContributorEntry(name: "谭哲昊（21级）", description: "架构规划、小组件", kind: .developer(qq: "330771794")),
        ContributorEntry(name: "王学雷（22级）", description: "页面设计、交互设计、新技术探索", kind: .developer(qq: "257314409")),
        ContributorEntry(name: "徐健灿（22级）", description: "爬虫、交互设计", kind: .developer(qq: "3148336396")),
        ContributorEntry(name: "王    钰（22级）", description: "架构规划、爬虫", kind: .developer(qq: "605606366"))
    ]
}

private struct ContributorsView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.openURL) private var openURL
    @State private var informationMessage: String?

    var body: some View {
        AndroidScreen {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    AndroidHeader(title: "贡献名单", large: true)
                        .accessibilityIdentifier("contributors.screen")
                    contributorSection(title: "加入我们", entries: ContributorsCatalog.partners)
                    contributorSection(title: "开发者", entries: ContributorsCatalog.developers)
                }
                .padding(.bottom, 80)
            }
            .scrollIndicators(.hidden)
        }
        .alert("提示", isPresented: Binding(
            get: { informationMessage != nil },
            set: { if !$0 { informationMessage = nil } }
        )) {
            Button("知道了", role: .cancel) { informationMessage = nil }
        } message: {
            Text(informationMessage ?? "")
        }
    }

    private func contributorSection(title: String, entries: [ContributorEntry]) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title)
                .font(.title3.bold())
                .padding(.horizontal, 24)

            VStack(spacing: 2) {
                ForEach(entries) { entry in
                    Button { open(entry) } label: {
                        HStack(spacing: 24) {
                            if entry.avatarURL != nil {
                                contributorAvatar(entry)
                            }
                            VStack(alignment: .leading, spacing: 4) {
                                Text(entry.name)
                                    .font(.title3.bold())
                                Text(entry.description)
                                    .font(.body)
                                    .foregroundStyle(AndroidParityPalette.secondaryText(colorScheme))
                                if let qq = entry.qq {
                                    Text("QQ: \(qq)")
                                        .font(.callout)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(.horizontal, 24)
                        .padding(.vertical, 16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(AndroidParityPalette.raisedSurface(colorScheme))
                        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("contributors.entry.\(entry.id)")
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
            .padding(.horizontal, 16)
        }
    }

    private func contributorAvatar(_ entry: ContributorEntry) -> some View {
        AsyncImage(url: entry.avatarURL) { phase in
            if case let .success(image) = phase {
                image.resizable().scaledToFill()
            } else {
                ZStack {
                    AndroidParityPalette.primaryContainer(colorScheme)
                    Image(systemName: "person.fill")
                        .font(.title2)
                        .foregroundStyle(AndroidParityPalette.accent)
                }
            }
        }
        .frame(width: 64, height: 64)
        .clipShape(Circle())
    }

    private func open(_ entry: ContributorEntry) {
        guard let url = entry.contactURL else {
            informationMessage = "请联系任意一位小伙伴"
            return
        }
        openURL(url)
    }
}

enum AppDataCleaner {
    static func clearCaches() async {
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
        try? await ScheduleWidgetSnapshotStore.shared.save(.unavailable(.signedOut))
    }
}
