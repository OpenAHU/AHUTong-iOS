import SafariServices
import SwiftUI

struct OfficialPaymentPortalProbeView: View {
    @ObservedObject var model: OperationsDiagnosticsModel
    @State private var showsOpenConfirmation = false
    @State private var showsOfficialPortal = false

    var body: some View {
        AndroidScreen {
            ScrollView {
                VStack(spacing: 24) {
                    AndroidHeader(title: "支付无扣款验收", large: true)
                        .accessibilityIdentifier(
                            "operations.payment-probe.screen"
                        )

                    explanationCard
                    probeCard
                    officialPortalCard
                }
                .padding(.bottom, 48)
            }
            .scrollIndicators(.hidden)
        }
        .confirmationDialog(
            "确认打开学校官方页面？",
            isPresented: $showsOpenConfirmation,
            titleVisibility: .visible
        ) {
            Button("继续打开") {
                showsOfficialPortal = true
            }
            .accessibilityIdentifier(
                "operations.payment-probe.open-confirm"
            )
            Button("取消", role: .cancel) {}
                .accessibilityIdentifier(
                    "operations.payment-probe.open-cancel"
                )
        } message: {
            Text(
                "只检查登录页或业务列表，不要点击最终支付确认。"
                    + "打开或关闭页面不会被记为支付成功。"
            )
        }
        .sheet(isPresented: $showsOfficialPortal) {
            OperationsOfficialPaymentPortalView(
                url: OfficialSchoolPaymentPortal.loginURL
            )
            .ignoresSafeArea()
        }
    }

    private var explanationCard: some View {
        AndroidCard(radius: 16) {
            VStack(alignment: .leading, spacing: 12) {
                Label("无凭据安全探测", systemImage: "checkmark.shield")
                    .font(.headline)
                Text(
                    "只向学校官方入口发送一次无账号凭据的 HEAD 请求，"
                        + "不跟随登录跳转，不携带 Cookie、Token、账号、"
                        + "金额或订单，也不会打开支付页面。"
                )
                .font(.subheadline)
                .foregroundStyle(.secondary)
                Text(
                    "探测通过只表示官方登录入口当前可达，"
                        + "不表示原生支付网关已配置，也不表示任何支付成功。"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
        }
        .padding(.horizontal, 16)
    }

    @ViewBuilder
    private var probeCard: some View {
        AndroidCard(radius: 16) {
            VStack(alignment: .leading, spacing: 16) {
                Text("学校官方入口")
                    .font(.title3)

                switch model.paymentPortalProbePhase {
                case .idle:
                    statusRow(label: "状态", value: "尚未探测")
                    runButton(title: "运行无扣款探测")
                case .running:
                    HStack(spacing: 12) {
                        ProgressView()
                            .accessibilityIdentifier(
                                "operations.payment-probe.progress"
                            )
                        Text("正在执行无凭据 HEAD 探测…")
                            .foregroundStyle(.secondary)
                    }
                case let .passed(report):
                    passedResult(report)
                    runButton(title: "重新探测")
                case let .failed(failure):
                    failedResult(failure)
                    runButton(title: "重试")
                        .accessibilityIdentifier(
                            "operations.payment-probe.retry"
                        )
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
        }
        .padding(.horizontal, 16)
    }

    private var officialPortalCard: some View {
        AndroidCard(radius: 16) {
            VStack(alignment: .leading, spacing: 12) {
                Label("手动检查官方页面", systemImage: "safari")
                    .font(.headline)
                Text(
                    "如需继续检查登录或业务列表，请由你主动打开。"
                        + "真实输入和最终确认均留在校方页面。"
                )
                .font(.subheadline)
                .foregroundStyle(.secondary)
                Button("打开学校官方页面") {
                    showsOpenConfirmation = true
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier(
                    "operations.payment-probe.open-official"
                )
                .accessibilityHint(
                    "打开前会再次确认；打开页面本身不会被记为支付成功"
                )
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
        }
        .padding(.horizontal, 16)
    }

    private func passedResult(
        _ report: OfficialPaymentPortalProbeReport
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("无凭据入口可达", systemImage: "checkmark.circle.fill")
                .font(.headline)
                .foregroundStyle(AndroidParityPalette.success)
            statusRow(label: "响应", value: "HTTP \(report.statusCode)")
            statusRow(
                label: "跳转",
                value: "\(report.redirectHost)\(report.redirectPath)"
            )
            statusRow(
                label: "耗时",
                value: "\(report.elapsedMilliseconds) ms"
            )
            statusRow(
                label: "请求边界",
                value: "未发起扣款请求"
            )
            Text(
                "检查时间："
                    + report.checkedAt.formatted(
                        date: .abbreviated,
                        time: .standard
                    )
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("operations.payment-probe.result")
        .accessibilityValue(report.accessibilitySummary)
    }

    private func failedResult(
        _ failure: OfficialPaymentPortalProbeFailure
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("无凭据入口探测异常", systemImage: "exclamationmark.triangle")
                .font(.headline)
                .foregroundStyle(.orange)
            Text(failure.message)
                .foregroundStyle(.secondary)
            Text("未发起扣款请求")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("operations.payment-probe.result")
        .accessibilityValue(
            "失败，\(failure.message)，未发起扣款请求"
        )
    }

    private func runButton(title: String) -> some View {
        Button(title) {
            Task { await model.runOfficialPaymentPortalProbe() }
        }
        .buttonStyle(.borderedProminent)
        .disabled(model.paymentPortalProbePhase == .running)
        .accessibilityIdentifier("operations.payment-probe.run")
        .accessibilityHint(
            "仅发送无账号凭据的 HEAD 请求，不会登录或扣款"
        )
    }

    private func statusRow(label: String, value: String) -> some View {
        HStack(alignment: .top, spacing: 16) {
            Text(label)
            Spacer(minLength: 12)
            Text(value)
                .multilineTextAlignment(.trailing)
                .foregroundStyle(.secondary)
        }
        .font(.subheadline)
    }
}

private struct OperationsOfficialPaymentPortalView:
    UIViewControllerRepresentable
{
    let url: URL

    func makeUIViewController(
        context: Context
    ) -> SFSafariViewController {
        let configuration = SFSafariViewController.Configuration()
        configuration.entersReaderIfAvailable = false
        configuration.barCollapsingEnabled = true
        return SFSafariViewController(
            url: url,
            configuration: configuration
        )
    }

    func updateUIViewController(
        _ controller: SFSafariViewController,
        context: Context
    ) {}
}
