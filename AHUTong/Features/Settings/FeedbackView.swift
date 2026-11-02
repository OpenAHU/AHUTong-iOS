import SwiftUI

struct FeedbackView: View {
    @Environment(\.openURL) private var openURL
    var body: some View {
        List {
            NavigationLink { FeedbackComposeView() } label: { Label("问题反馈", systemImage: "bubble.left.and.text.bubble.right") }
                .accessibilityIdentifier("feedback.compose")
            NavigationLink { FeedbackComposeView(exportOnly: true) } label: { Label("日志导出", systemImage: "square.and.arrow.up") }
            Button { openURL(AgreementDocument.communityQQGroupURL) } label: { Label("QQ 反馈群", systemImage: "person.2") }
        }
        .navigationTitle("意见反馈")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct FeedbackComposeView: View {
    var exportOnly = false
    @State private var message = ""
    @State private var categories: Set<DiagnosticLogCategory> = [.runtime, .error]
    @State private var preview: DiagnosticFeedbackPreview?
    @State private var exportedURL: URL?
    @State private var failure: String?
    @State private var isExporting = false
    var body: some View {
        Form {
            if !exportOnly {
                Section("问题描述") {
                    TextField("发生了什么？", text: $message, axis: .vertical)
                        .lineLimit(5...10)
                        .accessibilityIdentifier("feedback.message")
                        .onChange(of: message) { _, value in if value.count > 4_096 { message = String(value.prefix(4_096)) } }
                }
            }
            Section {
                ForEach(DiagnosticLogCategory.allCases) { category in
                    Toggle(category.title, isOn: Binding(get: { categories.contains(category) }, set: { enabled in
                        if enabled { categories.insert(category) } else { categories.remove(category) }
                        exportedURL = nil
                    }))
                    .accessibilityIdentifier("feedback.category.\(category.rawValue)")
                }
            } footer: {
                Text("网络详情可能含学号、Cookie、Token 和查询结果，仅在本次选择后提交。密码、支付及邮箱正文不采集。")
            }
            if exportOnly {
                Section {
                    Button(isExporting ? "正在加密…" : "生成加密日志") { export() }
                        .disabled(isExporting || categories.isEmpty)
                    if let exportedURL { ShareLink("分享日志", item: exportedURL) }
                } footer: { Text("仅维护者可以解密。") }
            }
            if let failure { Text(failure).foregroundStyle(.secondary) }
        }
        .navigationTitle(exportOnly ? "日志导出" : "问题反馈")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !exportOnly {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("预览", systemImage: "arrow.up.doc") { preview = DiagnosticFeedbackPreview(message: message, categories: categories) }
                        .labelStyle(.iconOnly)
                        .disabled(message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .accessibilityIdentifier("feedback.preview")
                }
            }
        }
        .sheet(item: $preview) { FeedbackPreviewSheet(preview: $0) }
    }

    private func export() {
        let snapshot = DiagnosticFeedbackPreview(message: "", categories: categories)
        isExporting = true; failure = nil
        Task {
            defer { isExporting = false }
            do { exportedURL = try await Task.detached(priority: .userInitiated) { try DiagnosticLogExport.write(snapshot) }.value }
            catch { failure = error.localizedDescription }
        }
    }
}

private struct FeedbackPreviewSheet: View {
    @Environment(\.dismiss) private var dismiss
    let preview: DiagnosticFeedbackPreview
    @State private var submitted = false
    @State private var failure: String?
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(String(preview.displayText.prefix(32_000))).font(.footnote).textSelection(.enabled)
                } footer: {
                    Text(preview.displayText.count > 32_000 ? "预览已截断，提交包含所选完整记录。" : "仅提交以上所选内容至 Sentry。")
                }
                if submitted { Text("反馈已交给发送队列。网络和服务状态可能影响送达。") }
                if let failure { Text(failure).foregroundStyle(.secondary) }
                if AppRuntime.usesIsolatedUITestStorage { Text("演示模式不发送反馈。") }
            }
            .navigationTitle("确认反馈").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("关闭") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("发送", systemImage: "paperplane") {
                        do { try AppDiagnostics.shared.submitFeedback(preview); submitted = true }
                        catch { failure = error.localizedDescription }
                    }
                    .labelStyle(.iconOnly)
                    .disabled(submitted || AppRuntime.usesIsolatedUITestStorage)
                    .accessibilityIdentifier("feedback.send")
                }
            }
        }
    }
}
