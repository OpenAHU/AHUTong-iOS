import AVFoundation
import SwiftUI

struct ScanView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var cameraAllowed = false
    @State private var isChecking = true
    @State private var isHandling = false
    @State private var message: String?
    @State private var showsWechat = false
    @State private var torchAvailable = false
    @State private var torchOn = false
    @State private var isVisible = false

    private var canScan: Bool {
        isVisible && !isHandling && message == nil && !showsWechat && scenePhase == .active
    }

    private var supportsCamera: Bool {
        #if targetEnvironment(simulator)
        false
        #else
        true
        #endif
    }

    var body: some View {
        NavigationStack {
            Group {
                if cameraAllowed && supportsCamera {
                    ScannerCamera(isRunning: canScan, torchOn: torchOn, onCode: handle,
                                  onTorchState: { available, enabled in torchAvailable = available; torchOn = enabled },
                                  onFailure: { message = $0 })
                        .ignoresSafeArea()
                        .overlay {
                            Image(systemName: "viewfinder")
                                .font(.system(size: 220, weight: .ultraLight))
                                .foregroundStyle(.white.opacity(0.75))
                                .accessibilityHidden(true)
                                .allowsHitTesting(false)
                        }
                } else if isChecking {
                    ProgressView()
                } else {
                    ContentUnavailableView {
                        Label("暂时无法扫码", systemImage: "qrcode.viewfinder")
                    } description: {
                        Text(cameraAllowed ? "请在支持相机扫描的 iPhone 上使用。" : "允许安大通使用相机后即可扫码。")
                    } actions: {
                        if !cameraAllowed {
                            Link("打开系统设置", destination: URL(string: UIApplication.openSettingsURLString)!)
                        }
                    }
                }
            }
            .navigationTitle("扫一扫")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭", systemImage: "xmark") {
                        isVisible = false
                        torchOn = false
                        dismiss()
                    }
                        .labelStyle(.iconOnly)
                        .accessibilityIdentifier("scan.close")
                }
                ToolbarItem(placement: .bottomBar) {
                    Button(torchOn ? "关闭手电筒" : "打开手电筒", systemImage: torchOn ? "flashlight.on.fill" : "flashlight.off.fill") {
                        torchOn.toggle()
                    }
                    .labelStyle(.iconOnly)
                    .font(.title2)
                    .tint(torchOn ? .yellow : .white)
                    .disabled(!torchAvailable || !canScan)
                    .accessibilityIdentifier("scan.torch")
                }
            }
            .toolbarBackground(.hidden, for: .navigationBar, .bottomBar)
            .safeAreaInset(edge: .bottom) {
                Text("美团单车 · 学习通 · 雨课堂")
                    .font(.footnote).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity).padding()
            }
            .background(.black)
            .alert("扫一扫", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
                Button("继续扫描", role: .cancel) { isHandling = false }
            } message: { Text(message ?? "") }
            .alert("雨课堂", isPresented: $showsWechat) {
                Button("打开微信") {
                    Task { await open(URL(string: "weixin://")!, app: "微信") }
                }
                Button("继续扫描", role: .cancel) { isHandling = false }
            } message: { Text("请在微信中使用“扫一扫”重新扫描，完成签到。") }
            .task { await checkCamera() }
            .onAppear { isVisible = true }
            .onChange(of: scenePhase) { _, phase in
                if phase != .active { torchOn = false }
                if phase == .active { Task { await checkCamera() } }
            }
            .onDisappear { isVisible = false; torchOn = false }
        }
        .preferredColorScheme(.dark)
        .tint(.white)
        .accessibilityIdentifier("scan.screen")
    }

    private func checkCamera() async {
        #if targetEnvironment(simulator)
        cameraAllowed = true
        #else
        cameraAllowed = switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: true
        case .notDetermined: await AVCaptureDevice.requestAccess(for: .video)
        default: false
        }
        #endif
        isChecking = false
    }

    private func handle(_ raw: String) {
        guard canScan else { return }
        isHandling = true
        UISelectionFeedbackGenerator().selectionChanged()
        switch ScanRoute(raw) {
        case let .meituan(url): Task { await open(url, app: "美团") }
        case let .chaoxing(url): Task { await open(url, app: "学习通") }
        case .wechat: showsWechat = true
        case .unsupported: message = "暂不支持这类二维码。"
        }
    }

    private func open(_ url: URL, app: String) async {
        if await UIApplication.shared.open(url) { dismiss() }
        else { message = "无法打开\(app)，请确认已安装并更新到最新版本。" }
    }
}
