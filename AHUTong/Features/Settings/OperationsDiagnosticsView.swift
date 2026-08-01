import SwiftUI
import UserNotifications

@MainActor
final class OperationsDiagnosticsModel: ObservableObject {
    @Published private(set) var states: [GrayFeatureState] = []
    @Published private(set) var diagnostics = ReleaseDiagnostics.current()
    @Published private(set) var operationMessage: String?

    private let service = GrayReleaseService()
    private let userID: String?
    private let demo: Bool

    init(
        userID: String?,
        demo: Bool = AppRuntime.isDemoSession
    ) {
        self.userID = userID
        self.demo = demo
    }

    func load() async {
        diagnostics = ReleaseDiagnostics.current()
        let versionCode = Int(diagnostics.build) ?? 0
        var loaded: [GrayFeatureState] = []
        for feature in GrayFeatures.all {
            let storedOverride = UserDefaults.standard.string(forKey: overrideKey(feature))
            let overrideMode = storedOverride.flatMap(GrayOverride.init(rawValue:)) ?? .follow
            if demo {
                loaded.append(await service.localState(feature: feature, userID: userID, overrideMode: overrideMode))
            } else {
                loaded.append(await service.state(
                    feature: feature,
                    userID: userID,
                    versionCode: versionCode,
                    versionName: diagnostics.version,
                    overrideMode: overrideMode
                ))
            }
        }
        states = loaded
    }

    func setOverride(_ overrideMode: GrayOverride, for feature: GrayFeature) async {
        let key = overrideKey(feature)
        if overrideMode == .follow {
            UserDefaults.standard.removeObject(forKey: key)
        } else {
            UserDefaults.standard.set(overrideMode.rawValue, forKey: key)
        }
        await load()
        NotificationCenter.default.post(name: .grayFeatureOverrideChanged, object: nil)
    }

    func scheduleDebugNotification() async {
        do {
            let center = UNUserNotificationCenter.current()
            let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            guard granted else {
                operationMessage = "通知权限未授予"
                return
            }
            let content = UNMutableNotificationContent()
            content.title = "安大通 Debug 通知"
            content.body = "这是一条 5 秒后触发的课前提醒测试。"
            content.sound = .default
            let request = UNNotificationRequest(
                identifier: "debug.course-reminder.\(UUID().uuidString)",
                content: content,
                trigger: UNTimeIntervalNotificationTrigger(timeInterval: 5, repeats: false)
            )
            try await center.add(request)
            operationMessage = "测试通知已安排，约 5 秒后触发"
        } catch {
            operationMessage = error.localizedDescription
        }
    }

    func startDebugLiveActivity() async {
        let now = Date()
        let calendar = Calendar.current
        let weekdayValue = calendar.component(.weekday, from: now)
        let todayWeekday = weekdayValue == 1 ? 7 : weekdayValue - 1
        let minutes = calendar.component(.hour, from: now) * 60 + calendar.component(.minute, from: now)
        let starts = [1: 480, 2: 530, 3: 590, 4: 640, 5: 690, 6: 840, 7: 890, 8: 950, 9: 1_000, 10: 1_050, 11: 1_140, 12: 1_190, 13: 1_240]
        let laterToday = starts.sorted { $0.value < $1.value }.first { $0.value > minutes + 2 }
        let weekday = laterToday == nil ? todayWeekday % 7 + 1 : todayWeekday
        let startPeriod = laterToday?.key ?? 1
        let course = Course(
            weekday: weekday,
            startWeek: 1,
            endWeek: 1,
            location: "Debug 教室",
            name: "Live Activity 测试",
            teacher: "",
            duration: 1,
            startPeriod: startPeriod,
            courseID: "debug-live-activity",
            weekIndexes: [1, 2]
        )
        do {
            let started = try await CourseLiveActivityCoordinator().setEnabled(
                true,
                courses: [course],
                currentWeek: 1,
                now: now,
                calendar: calendar
            )
            operationMessage = started ? "Live Activity 已启动" : "系统未允许实时活动"
        } catch {
            operationMessage = error.localizedDescription
        }
    }

    func setOperationMessage(_ value: String?) {
        operationMessage = value
    }

    private func overrideKey(_ feature: GrayFeature) -> String {
        "debug.gray.\(feature.key)"
    }
}

struct OperationsDiagnosticsView: View {
    @Environment(\.colorScheme) private var colorScheme
    @StateObject private var model: OperationsDiagnosticsModel
    @ObservedObject private var appModel: AppModel
    @AppStorage(DebugRuntimeSettings.mockEnabledKey) private var mockEnabled = false
    @AppStorage(DebugRuntimeSettings.scenarioKey) private var mockScenario = DemoDataState.normal.rawValue
    @AppStorage(DebugRuntimeSettings.timeKey) private var mockTimestamp = 0.0
    @State private var selectedEndpoint = DebugRuntimeSettings.endpoints[0]
    @State private var endpointJSON = "{}"
    @State private var jsonMessage: String?

    init(
        userID: String?,
        appModel: AppModel
    ) {
        self.appModel = appModel
        _model = StateObject(wrappedValue: OperationsDiagnosticsModel(
            userID: userID
        ))
    }

    var body: some View {
        AndroidScreen {
            ScrollView {
                VStack(spacing: 24) {
                    AndroidHeader(title: "Debug", large: true)

                    debugSection(
                        title: "Mock 数据源",
                        subtitle: "切换后重新进入目标页面生效；支付 Mock 永远使用演示网关，不会发起真实扣款。"
                    ) {
                        Toggle("启用 Mock 数据源", isOn: $mockEnabled)
                            .accessibilityIdentifier("debug.mock.enabled")
                        Picker("场景", selection: $mockScenario) {
                            ForEach([DemoDataState.normal, .loading, .empty, .error], id: \.rawValue) {
                                Text($0.rawValue).tag($0.rawValue)
                            }
                        }
                        .pickerStyle(.segmented)
                        DatePicker(
                            "模拟时间",
                            selection: Binding(
                                get: { mockTimestamp > 0 ? Date(timeIntervalSince1970: mockTimestamp) : DemoDataState.referenceDate },
                                set: { mockTimestamp = $0.timeIntervalSince1970 }
                            )
                        )
                        Button("恢复真实时间") { mockTimestamp = 0 }
                            .buttonStyle(.plain)
                            .foregroundStyle(.tint)
                    }

                    debugSection(
                        title: "接口 JSON 编辑",
                        subtitle: "保存前执行 JSON 语法校验，用于固定现场复现数据；场景诊断会显示当前端点和字节数。"
                    ) {
                        Picker("端点", selection: $selectedEndpoint) {
                            ForEach(DebugRuntimeSettings.endpoints, id: \.self) { Text($0).tag($0) }
                        }
                        .onChange(of: selectedEndpoint) { _, value in
                            endpointJSON = DebugRuntimeSettings.endpointJSON(value)
                            jsonMessage = nil
                        }
                        TextEditor(text: $endpointJSON)
                            .font(.system(.caption, design: .monospaced))
                            .frame(minHeight: 150)
                            .padding(8)
                            .background(AndroidParityPalette.background(colorScheme), in: RoundedRectangle(cornerRadius: 12))
                            .accessibilityIdentifier("debug.mock.json")
                        HStack {
                            Button("重置") {
                                endpointJSON = "{}"
                                UserDefaults.standard.removeObject(forKey: DebugRuntimeSettings.endpointKeyPrefix + selectedEndpoint)
                                jsonMessage = "已重置"
                            }
                            Spacer()
                            Button("校验并保存") { saveEndpointJSON() }
                        }
                        .buttonStyle(.plain)
                        if let jsonMessage {
                            Text(jsonMessage).font(.caption).foregroundStyle(.secondary)
                        }
                    }

                    debugSection(
                        title: "灰度测试",
                        subtitle: "优先读取服务端配置，失败时按账号摘要本地兜底；不会上传原始学号。"
                    ) {
                        ForEach(model.states, id: \.feature.key) { state in
                            grayCard(state)
                        }
                    }

                    debugSection(title: "发布诊断") {
                        DebugStatusRow(label: "版本", value: "\(model.diagnostics.version) (\(model.diagnostics.build))")
                        DebugStatusRow(
                            label: "App 隐私清单",
                            value: model.diagnostics.privacy.exists ? "已内嵌" : "缺失",
                            warning: !model.diagnostics.privacy.exists
                        )
                        DebugStatusRow(
                            label: "跨站跟踪",
                            value: model.diagnostics.privacy.trackingDisabled ? "关闭" : "需检查",
                            warning: !model.diagnostics.privacy.trackingDisabled
                        )
                        DebugStatusRow(
                            label: "支付生产网关",
                            value: model.diagnostics.productionPaymentGatewayConfigured ? "已配置（客户端协议兼容）" : "未配置"
                        )
                    }

                    debugSection(
                        title: "支付验收",
                        subtitle: "自动化只验证离线协议契约；真实小额支付仅由授权用户在真机手动执行。"
                    ) {
                        NavigationLink {
                            CMBRechargeView(
                                appModel: appModel,
                                mode: .noDebitAcceptance
                            )
                            .androidDetailScreen()
                        } label: {
                            operationsNavigationRow(
                                title: "招商银行扣款前 HEAD 探测",
                                detail: "不创建 WebView，不执行脚本或发送请求体",
                                systemImage: "building.columns"
                            )
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier(
                            "operations.cmb-acceptance.entry"
                        )
                    }

                    debugSection(title: "隐私与日志") {
                        DebugStatusRow(label: "支付信息声明", value: model.diagnostics.privacy.declaresPaymentInfo ? "已声明" : "缺失")
                        DebugStatusRow(label: "第三方崩溃上报", value: model.diagnostics.thirdPartyCrashReportingEnabled ? "开启" : "未接入")
                        DebugStatusRow(label: "敏感日志", value: "脱敏器可用；Debug 不展示凭据")
                        Text("密码、Token、Cookie、Authorization、手机号和长数字标识在进入统一日志前会被替换；支付密码只保留在当前内存流程中。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    debugSection(title: "维护") {
                        Button("清除业务缓存") {
                            Task {
                                await AppDataCleaner.clearCaches()
                                model.setOperationMessage("业务缓存已清除")
                            }
                        }
                        Button("清除 Cookie 并重新认证") {
                            Task {
                                do {
                                    try await appModel.campusAPI.initialize(cookiesJSON: "")
                                    try await appModel.campusAPI.refreshSession()
                                    model.setOperationMessage("Cookie 已刷新")
                                } catch {
                                    model.setOperationMessage(error.localizedDescription)
                                }
                            }
                        }
                        Button("清除 Cookie、Token 与登录状态", role: .destructive) {
                            Task { await appModel.signOut() }
                        }
                    }

                    debugSection(title: "通知测试") {
                        Button("5 秒后发送普通课前提醒") {
                            Task { await model.scheduleDebugNotification() }
                        }
                        Button("启动 Live Activity 测试") {
                            Task { await model.startDebugLiveActivity() }
                        }
                        Text("普通通知验证权限与触发链路；Live Activity 会在锁定屏幕和支持的灵动岛设备显示。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    debugSection(title: "归档与安装") {
                        Text("GitHub Actions 生成未签名 IPA 与 Release Archive；免费 Apple ID 需在本机使用 Personal Team、AltStore 或 Sideloadly 每 7 天重新签名。")
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Button("重新运行诊断") { Task { await model.load() } }
                            .buttonStyle(.plain)
                            .foregroundStyle(.tint)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                            .accessibilityIdentifier("operations.refresh")
                    }
                }
                .padding(.bottom, 64)
            }
        }
        .alert("Debug", isPresented: Binding(
            get: { model.operationMessage != nil },
            set: { if !$0 { model.setOperationMessage(nil) } }
        )) {
            Button("确定", role: .cancel) { model.setOperationMessage(nil) }
        } message: {
            Text(model.operationMessage ?? "")
        }
        .accessibilityIdentifier("operations.debug.screen")
        .task {
            endpointJSON = DebugRuntimeSettings.endpointJSON(selectedEndpoint)
            await model.load()
        }
    }

    private func grayCard(_ state: GrayFeatureState) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(state.feature.title).font(.headline)
                    Text(state.feature.description).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Text(state.enabled ? "开启" : "关闭")
                    .font(.caption.bold())
                    .foregroundStyle(state.enabled ? Color.green : Color.secondary)
            }
            Text("分桶 \(state.bucket) · 比例 \(state.rolloutPercentage)% · \(state.reason)")
                .font(.caption)
                .foregroundStyle(.secondary)
#if DEBUG
            HStack {
                Text("覆盖")
                Spacer()
                Menu(state.overrideMode.label) {
                    ForEach(GrayOverride.allCases, id: \.rawValue) { overrideMode in
                        Button(overrideMode.label) {
                            Task { await model.setOverride(overrideMode, for: state.feature) }
                        }
                    }
                }
            }
#endif
        }
        .padding(16)
        .background(AndroidParityPalette.background(colorScheme), in: RoundedRectangle(cornerRadius: 16))
    }

    private func debugSection<Content: View>(
        title: String,
        subtitle: String? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        AndroidCard(radius: 16) {
            VStack(alignment: .leading, spacing: 16) {
                Text(title).font(.title3)
                if let subtitle {
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                }
                content()
            }
            .padding(16)
        }
        .padding(.horizontal, 16)
    }

    private func operationsNavigationRow(
        title: String,
        detail: String,
        systemImage: String
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .foregroundStyle(.primary)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 12)
            Image(systemName: "chevron.right")
                .font(.caption.bold())
                .foregroundStyle(.tertiary)
        }
        .contentShape(Rectangle())
    }

    private func saveEndpointJSON() {
        do {
            try DebugRuntimeSettings.setEndpointJSON(endpointJSON, endpoint: selectedEndpoint)
            jsonMessage = "JSON 有效，已保存（\(endpointJSON.utf8.count) bytes）"
        } catch {
            jsonMessage = "JSON 无效：\(error.localizedDescription)"
        }
    }
}

private struct DebugStatusRow: View {
    let label: String
    let value: String
    var warning = false

    var body: some View {
        HStack(alignment: .top) {
            Text(label)
            Spacer(minLength: 16)
            Text(value)
                .multilineTextAlignment(.trailing)
                .foregroundStyle(warning ? Color.orange : Color.secondary)
        }
        .font(.subheadline)
    }
}
