import AVFoundation
import SwiftUI

struct ScannerCamera: UIViewControllerRepresentable {
    let isRunning: Bool
    let torchOn: Bool
    let onCode: @MainActor @Sendable (String) -> Void
    let onTorchState: @MainActor @Sendable (Bool, Bool) -> Void
    let onFailure: @MainActor @Sendable (String) -> Void

    func makeUIViewController(context: Context) -> ScannerCameraController {
        ScannerCameraController(onCode: onCode, onTorchState: onTorchState, onFailure: onFailure)
    }

    func updateUIViewController(_ controller: ScannerCameraController, context: Context) {
        controller.update(running: isRunning, torch: torchOn)
    }

    static func dismantleUIViewController(_ controller: ScannerCameraController, coordinator: ()) {
        controller.update(running: false, torch: false)
    }
}

@MainActor
final class ScannerCameraController: UIViewController {
    private let camera: ScannerCapture
    private let preview = AVCaptureVideoPreviewLayer()
    private let onTorchState: @MainActor @Sendable (Bool, Bool) -> Void
    private let onFailure: @MainActor @Sendable (String) -> Void
    private var command: (running: Bool, torch: Bool)?
    private var revision = 0
    private var torchObservation: NSKeyValueObservation?

    init(onCode: @escaping @MainActor @Sendable (String) -> Void,
         onTorchState: @escaping @MainActor @Sendable (Bool, Bool) -> Void,
         onFailure: @escaping @MainActor @Sendable (String) -> Void) {
        camera = ScannerCapture(onCode: onCode)
        self.onTorchState = onTorchState
        self.onFailure = onFailure
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        preview.videoGravity = .resizeAspectFill
        view.layer.addSublayer(preview)
        view.addGestureRecognizer(UIPinchGestureRecognizer(target: self, action: #selector(zoom(_:))))
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        preview.frame = view.bounds
        CATransaction.commit()
        let angle: CGFloat = switch view.window?.windowScene?.interfaceOrientation {
        case .landscapeLeft: 180
        case .landscapeRight: 0
        case .portraitUpsideDown: 270
        default: 90
        }
        if let connection = preview.connection, connection.isVideoRotationAngleSupported(angle) {
            connection.videoRotationAngle = angle
        }
    }

    func update(running: Bool, torch: Bool) {
        guard command?.running != running || command?.torch != torch else { return }
        command = (running, torch)
        revision += 1
        let revision = revision
        Task { [weak self, camera] in
            do {
                let source = try await camera.update(running: running, torch: torch, revision: revision)
                guard let self, self.revision == revision else { return }
                guard let source else { onTorchState(false, false); return }
                if preview.session !== source.session {
                    preview.session = source.session
                    let supportsTorch = source.device.hasTorch && source.device.isTorchModeSupported(.on)
                    torchObservation = source.device.observe(\.isTorchAvailable, options: [.new]) { [weak self] _, change in
                        let available = supportsTorch && change.newValue == true
                        Task { @MainActor in
                            guard let self, self.command?.running == true else { return }
                            self.onTorchState(available, available && self.command?.torch == true)
                        }
                    }
                    NotificationCenter.default.addObserver(self, selector: #selector(captureFailed(_:)),
                        name: AVCaptureSession.runtimeErrorNotification, object: source.session)
                    NotificationCenter.default.addObserver(self, selector: #selector(captureFailed(_:)),
                        name: AVCaptureSession.wasInterruptedNotification, object: source.session)
                    view.setNeedsLayout()
                }
                onTorchState(source.torchAvailable, source.torchOn)
            } catch {
                guard let self, self.revision == revision else { return }
                onTorchState(false, false)
                onFailure(torch ? "手电筒暂时不可用，请稍后重试。" : "相机暂时不可用，请关闭后重试。")
            }
        }
    }

    @objc private func zoom(_ gesture: UIPinchGestureRecognizer) {
        let scale = gesture.scale
        gesture.scale = 1
        Task {
            do { try await camera.zoom(by: scale) }
            catch { onFailure("相机暂时无法缩放，请稍后重试。") }
        }
    }

    @objc nonisolated private func captureFailed(_ notification: Notification) {
        Task { @MainActor [weak self] in
            guard let self, command?.running == true else { return }
            onFailure("相机暂时不可用，请关闭后重试。")
        }
    }
}

// The capture actor owns all session/device mutations. The main actor only
// attaches the session to AVFoundation's preview layer through this bridge.
private struct ScannerPreviewSource: @unchecked Sendable {
    let session: AVCaptureSession
    let device: AVCaptureDevice
    let torchAvailable: Bool
    let torchOn: Bool
}

private actor ScannerCapture {
    private var session: AVCaptureSession?
    private var device: AVCaptureDevice?
    private var revision = -1
    private let receiver: ScannerCodeReceiver

    init(onCode: @escaping @MainActor @Sendable (String) -> Void) {
        receiver = ScannerCodeReceiver(onCode: onCode)
    }

    func update(running: Bool, torch: Bool, revision: Int) throws -> ScannerPreviewSource? {
        // Ignore commands superseded while camera startup was blocking.
        guard revision > self.revision else { return nil }
        self.revision = revision
        if !running {
            try? setTorch(false)
            session?.stopRunning()
            return nil
        }
        if session == nil { try configure() }
        guard let session, let device else { throw CameraError.unavailable }
        if !session.isRunning { session.startRunning() }
        guard session.isRunning else { throw CameraError.unavailable }
        try setTorch(torch)
        return ScannerPreviewSource(session: session, device: device,
            torchAvailable: device.hasTorch && device.isTorchAvailable && device.isTorchModeSupported(.on),
            torchOn: device.torchMode == .on)
    }

    private func configure() throws {
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
            throw CameraError.unavailable
        }
        let session = AVCaptureSession()
        let input = try AVCaptureDeviceInput(device: device)
        let output = AVCaptureMetadataOutput()
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        guard session.canAddInput(input), session.canAddOutput(output) else { throw CameraError.unavailable }
        session.sessionPreset = .hd1280x720
        session.addInput(input)
        session.addOutput(output)
        guard output.availableMetadataObjectTypes.contains(.qr) else { throw CameraError.unavailable }
        output.metadataObjectTypes = [.qr]
        output.setMetadataObjectsDelegate(receiver, queue: .main)
        try device.lockForConfiguration()
        if device.isFocusModeSupported(.continuousAutoFocus) { device.focusMode = .continuousAutoFocus }
        if device.isExposureModeSupported(.continuousAutoExposure) { device.exposureMode = .continuousAutoExposure }
        device.unlockForConfiguration()
        self.device = device
        self.session = session
    }

    private func setTorch(_ enabled: Bool) throws {
        guard let device, device.hasTorch else {
            if enabled { throw CameraError.unavailable }
            return
        }
        let mode: AVCaptureDevice.TorchMode = enabled ? .on : .off
        guard device.torchMode != mode else { return }
        guard device.isTorchModeSupported(mode), !enabled || device.isTorchAvailable else { throw CameraError.unavailable }
        try device.lockForConfiguration()
        defer { device.unlockForConfiguration() }
        device.torchMode = mode
    }

    func zoom(by scale: CGFloat) throws {
        guard let device, let session, session.isRunning else { return }
        try device.lockForConfiguration()
        defer { device.unlockForConfiguration() }
        device.videoZoomFactor = min(max(device.videoZoomFactor * scale, 1), min(5, device.activeFormat.videoMaxZoomFactor))
    }

    private enum CameraError: Error { case unavailable }
}

private final class ScannerCodeReceiver: NSObject, AVCaptureMetadataOutputObjectsDelegate {
    let onCode: @MainActor @Sendable (String) -> Void
    init(onCode: @escaping @MainActor @Sendable (String) -> Void) { self.onCode = onCode }
    func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput objects: [AVMetadataObject], from connection: AVCaptureConnection) {
        guard let code = objects.first as? AVMetadataMachineReadableCodeObject, let value = code.stringValue else { return }
        Task { @MainActor [onCode] in onCode(value) }
    }
}
