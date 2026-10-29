import PhotosUI
import SwiftUI

struct BackgroundSettingsView: View {
    @ObservedObject private var store = AppBackgroundStore.shared
    @AppStorage("theme.color") private var themeColor = AndroidThemeColor.defaultValue
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var isImporting = false
    @State private var errorMessage: String?

    var body: some View {
        let photoTitle = store.image == nil ? "选择照片" : "更换照片"
        Form {
            Section {
                PhotosPicker(selection: $selectedPhoto, matching: .images) {
                    Label(photoTitle, systemImage: "photo")
                }
                .buttonStyle(PressFeedbackStyle())
                .disabled(isImporting)
                .accessibilityIdentifier("background.select")
                if isImporting { ProgressView("正在导入…") }
            } footer: { Text("照片仅保存在本机。") }

            if store.image != nil {
                Section {
                    VStack(alignment: .leading) {
                        HStack {
                            Text("遮罩不透明度")
                            Spacer()
                            Text(store.maskOpacity, format: .percent.precision(.fractionLength(0)))
                                .foregroundStyle(.secondary).monospacedDigit()
                        }
                        Slider(value: $store.maskOpacity, in: 0...1, step: 0.01)
                            .accessibilityLabel("遮罩不透明度")
                            .accessibilityIdentifier("background.opacity")
                    }
                    Toggle("动态视差", isOn: $store.motionEnabled)
                        .accessibilityIdentifier("background.motion")
                } footer: { Text("浅色模式叠加白色遮罩，深色模式叠加黑色遮罩。动态视差随手机倾斜轻移，减弱动态效果时停用。") }
                Section {
                    Button("从背景图取主题色", systemImage: "eyedropper") {
                        if let color = store.themeColor { themeColor = color }
                    }
                    .buttonStyle(PressFeedbackStyle())
                    .disabled(store.themeColor == nil)
                    .accessibilityIdentifier("background.theme")
                    Button("清除背景", systemImage: "trash", role: .destructive) {
                        do { try store.clear() } catch { errorMessage = "未能清除背景，请重试。" }
                    }
                    .buttonStyle(PressFeedbackStyle())
                    .accessibilityIdentifier("background.clear")
                }
            }
        }
        .appBackground()
        .navigationTitle("背景")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: selectedPhoto) {
            guard let selectedPhoto else { return }
            isImporting = true
            defer { isImporting = false }
            do {
                guard let data = try await selectedPhoto.loadTransferable(type: Data.self) else {
                    throw CocoaError(.fileReadCorruptFile)
                }
                try await store.importPhoto(data)
            } catch { errorMessage = "无法导入这张照片，请重试。" }
            self.selectedPhoto = nil
        }
        .alert("背景", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("好", role: .cancel) { errorMessage = nil }
        } message: { Text(errorMessage ?? "") }
    }
}
