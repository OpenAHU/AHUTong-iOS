import XCTest
@testable import AHUTong

@MainActor
final class CampusForegroundReadinessTests: XCTestCase {
    func testShortcutWaitsForSceneAndWindowInsteadOfFailingDuringActivation() async throws {
        var checks = 0
        let ready = try await CampusForegroundReadiness.wait(attempts: 4, isReady: {
            checks += 1
            return checks == 3
        }, pause: {})
        XCTAssertTrue(ready)
        XCTAssertEqual(checks, 3)
    }

    func testUnavailableForegroundHasABoundedWait() async throws {
        var pauses = 0
        let ready = try await CampusForegroundReadiness.wait(attempts: 3, isReady: { false }, pause: {
            pauses += 1
        })
        XCTAssertFalse(ready)
        XCTAssertEqual(pauses, 3)
    }

    func testCancellationDoesNotContinueIntoLogin() async {
        do {
            _ = try await CampusForegroundReadiness.wait(isReady: { false }, pause: { throw CancellationError() })
            XCTFail("Cancellation must propagate")
        } catch { XCTAssertTrue(error is CancellationError) }
    }
}
