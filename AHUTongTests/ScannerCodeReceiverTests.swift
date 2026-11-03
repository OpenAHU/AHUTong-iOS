import XCTest
@testable import AHUTong

@MainActor
final class ScannerCodeReceiverTests: XCTestCase {
    func testForegroundUpdateReplacesHandlerCapturedWhileInactive() {
        let results = ScanResultProbe()
        let receiver = ScannerCodeReceiver(onCode: handler(active: false, results: results))
        let controller = ScannerCameraController(receiver: receiver, onTorchState: { _, _ in }, onFailure: { _ in })
        receiver.isRunning = true
        controller.updateCallbacks(onCode: handler(active: true, results: results),
                                   onTorchState: { _, _ in }, onFailure: { _ in })

        receiver.receive("https://www.yuketang.cn/checkin/test")

        XCTAssertEqual(results.routes, [.wechat])
    }

    func testStoppingCameraRejectsAnAlreadyQueuedRecognition() async {
        let results = ScanResultProbe()
        let receiver = ScannerCodeReceiver(onCode: handler(active: true, results: results))
        let controller = ScannerCameraController(receiver: receiver, onTorchState: { _, _ in }, onFailure: { _ in })
        receiver.isRunning = true
        let queued = Task { @MainActor in receiver.receive("https://www.yuketang.cn/checkin/test") }

        controller.update(running: false, torch: false)
        await queued.value

        XCTAssertTrue(results.routes.isEmpty)
    }

    func testResumingCameraUsesTheNewConsumer() {
        let previous = ScanResultProbe()
        let current = ScanResultProbe()
        let receiver = ScannerCodeReceiver(onCode: handler(active: true, results: previous))
        let controller = ScannerCameraController(receiver: receiver, onTorchState: { _, _ in }, onFailure: { _ in })
        controller.update(running: false, torch: false)
        controller.updateCallbacks(onCode: handler(active: true, results: current),
                                   onTorchState: { _, _ in }, onFailure: { _ in })
        receiver.isRunning = true

        receiver.receive("http://t8.pub/test-bike")

        XCTAssertTrue(previous.routes.isEmpty)
        guard case .meituan? = current.routes.first else { return XCTFail("Expected bike handoff") }
    }

    private func handler(active: Bool, results: ScanResultProbe) -> @MainActor @Sendable (String) -> Void {
        { code in
            guard active else { return }
            results.routes.append(ScanRoute(code))
        }
    }
}

@MainActor
private final class ScanResultProbe {
    var routes: [ScanRoute] = []
}
