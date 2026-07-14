import SwiftUI

@MainActor
final class OperationsDiagnosticsModel: ObservableObject {
    @Published private(set) var states: [GrayFeatureState] = []
    @Published private(set) var diagnostics = ReleaseDiagnostics.current()

    private let service = GrayReleaseService()
    private let userID: String?
    private let demo: Bool

    init(userID: String?, demo: Bool = ProcessInfo.processInfo.arguments.contains("--demo-session")) {
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
    }

    private func overrideKey(_ feature: GrayFeature) -> String {
        "debug.gray.\(feature.key)"
    }
}

struct OperationsDiagnosticsView: View {
    @Environment(\.colorScheme) private var colorScheme
    @StateObject private var model: OperationsDiagnosticsModel

    init(userID: String?) {
        _model = StateObject(wrappedValue: OperationsDiagnosticsModel(userID: userID))
    }

    var body: some View {
        AndroidScreen {
            ScrollView {
                VStack(spacing: 24) {
                    AndroidHeader(title: "Debug", large: true)

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
                            value: model.diagnostics.productionPaymentGatewayConfigured ? "已配置" : "安全阻断"
                        )
                    }

                    debugSection(title: "隐私与日志") {
                        DebugStatusRow(label: "支付信息声明", value: model.diagnostics.privacy.declaresPaymentInfo ? "已声明" : "缺失")
                        DebugStatusRow(label: "第三方崩溃上报", value: model.diagnostics.thirdPartyCrashReportingEnabled ? "开启" : "未接入")
                        DebugStatusRow(label: "敏感日志", value: "统一脱敏")
                        Text("密码、Token、Cookie、Authorization、手机号和长数字标识在进入统一日志前会被替换；支付密码只保留在当前内存流程中。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
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
        .accessibilityIdentifier("operations.debug.screen")
        .task { await model.load() }
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
