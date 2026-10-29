import AVFoundation
import SwiftUI
import VisionKit

struct ScanView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var cameraAllowed = false
    @State private var isChecking = true
    @State private var isHandling = false
    @State private var message: String?
    @State private var showsWechat = false

    var body: some View {
        NavigationStack {
            Group {
                if cameraAllowed && DataScannerViewController.isSupported && DataScannerViewController.isAvailable {
                    CameraScanner(isRunning: !isHandling && message == nil && !showsWechat && scenePhase == .active,
                                  onCode: handle, onFailure: { message = "相机暂时不可用，请关闭后重试。" })
                        .ignoresSafeArea(edges: .bottom)
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
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("关闭") { dismiss() } } }
            .safeAreaInset(edge: .bottom) {
                Text("美团单车 · 学习通 · 雨课堂")
                    .font(.footnote).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity).padding()
                    .background(.regularMaterial)
            }
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
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { Task { await checkCamera() } }
            }
        }
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
        guard !isHandling else { return }
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

private struct CameraScanner: UIViewControllerRepresentable {
    let isRunning: Bool
    let onCode: (String) -> Void
    let onFailure: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onCode: onCode, onFailure: onFailure) }
    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(recognizedDataTypes: [.barcode(symbologies: [.qr])],
            qualityLevel: .balanced, recognizesMultipleItems: false,
            isHighFrameRateTrackingEnabled: false, isPinchToZoomEnabled: true,
            isGuidanceEnabled: true, isHighlightingEnabled: true)
        scanner.delegate = context.coordinator
        return scanner
    }
    func updateUIViewController(_ scanner: DataScannerViewController, context: Context) {
        if isRunning && !scanner.isScanning {
            do { try scanner.startScanning() } catch { Task { @MainActor in onFailure() } }
        } else if !isRunning { scanner.stopScanning() }
    }
    static func dismantleUIViewController(_ scanner: DataScannerViewController, coordinator: Coordinator) {
        scanner.stopScanning()
    }
    @MainActor final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let onCode: (String) -> Void
        let onFailure: () -> Void
        init(onCode: @escaping (String) -> Void, onFailure: @escaping () -> Void) {
            self.onCode = onCode; self.onFailure = onFailure
        }
        func dataScanner(_ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            for case let .barcode(code) in addedItems {
                if let payload = code.payloadStringValue { onCode(payload); break }
            }
        }
        func dataScanner(_ dataScanner: DataScannerViewController, becameUnavailableWithError error: DataScannerViewController.ScanningUnavailable) {
            onFailure()
        }
    }
}
