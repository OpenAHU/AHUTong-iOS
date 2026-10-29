import XCTest
@testable import AHUTong

final class AppUpdateCheckerTests: XCTestCase {
    private let installed = InstalledBuild(actionsRun: 147, builtAt: nil)
    private let now = Date(timeIntervalSince1970: 1_793_318_400)

    func testSemanticVersionComparison() {
        XCTAssertEqual(AppUpdateChecker.compare("3.2.0", "3.1.9"), .orderedDescending)
        XCTAssertEqual(AppUpdateChecker.compare("3.1.9", "3.1.9"), .orderedSame)
        XCTAssertEqual(AppUpdateChecker.compare("3.1", "3.1.1"), .orderedAscending)
    }

    func testReportsNewGitHubRelease() async throws {
        let transport = UpdateTransportStub(responses: [
            (Data(#"{"tag_name":"v3.2.0","name":"新版","html_url":"https://github.com/OpenAHU/AHUTong-iOS/releases/tag/v3.2.0"}"#.utf8), 200)
        ])
        let result = try await AppUpdateChecker(transport: transport).check(currentVersion: "3.1.9")
        XCTAssertTrue(result.message.contains("v3.2.0"))
        XCTAssertEqual(result.destination?.host, "github.com")
    }

    func testFallsBackToNewerDownloadableActionsBuild() async throws {
        let transport = UpdateTransportStub(responses: [(Data(), 404), runs(), artifacts()])
        let result = try await AppUpdateChecker(transport: transport).check(currentVersion: "1.0.7", installed: installed)
        XCTAssertTrue(result.message.contains("#148"))
        XCTAssertEqual(result.destination?.lastPathComponent, "1480")
    }

    func testSameInstalledBuildDoesNotFetchArtifacts() async throws {
        let transport = UpdateTransportStub(responses: [runs(number: 147)])
        let result = try await AppUpdateChecker(transport: transport).availableActionsUpdate(installed: installed, now: now)
        XCTAssertNil(result)
    }

    func testLocalBuildRejectsEarlierActionsIncludingReruns() async throws {
        let local = InstalledBuild(actionsRun: 0, builtAt: Date(timeIntervalSince1970: 1_800_000_000))
        let result = try await AppUpdateChecker(transport: UpdateTransportStub(responses: [runs()]))
            .availableActionsUpdate(installed: local, now: now)
        XCTAssertNil(result)
    }

    func testFailedWorkflowIsNeverOffered() async throws {
        let result = try await AppUpdateChecker(transport: UpdateTransportStub(responses: [runs(conclusion: "failure")]))
            .availableActionsUpdate(installed: installed, now: now)
        XCTAssertNil(result)
    }

    func testExpiredIPAIsNotOffered() async throws {
        let result = try await AppUpdateChecker(transport: UpdateTransportStub(responses: [runs(), artifacts(expired: true)]))
            .availableActionsUpdate(installed: installed, now: now)
        XCTAssertNil(result)
    }

    func testDebugSymbolsAloneAreNotAnIPAUpdate() async throws {
        let result = try await AppUpdateChecker(transport: UpdateTransportStub(responses: [runs(), artifacts(name: "AHUTong-dSYMs-148")]))
            .availableActionsUpdate(installed: installed, now: now)
        XCTAssertNil(result)
    }

    @MainActor
    func testPromptMarkerPersistsAndOnlyANewerRunPromptsAgain() async {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let first = AppUpdateMonitor(checker: AppUpdateChecker(transport: UpdateTransportStub(responses: [runs(), artifacts()])), defaults: defaults)
        await first.check(installed: installed, now: now)
        guard let candidate = first.available else { return XCTFail("Missing first update") }
        first.markPresented(candidate)
        let relaunched = AppUpdateMonitor(checker: AppUpdateChecker(transport: UpdateTransportStub(responses: [runs(), artifacts(), runs(number: 149), artifacts(name: "AHUTong-unsigned-ipa-149")])), defaults: defaults)
        await relaunched.check(installed: installed, now: now)
        XCTAssertNil(relaunched.available)
        await relaunched.check(installed: installed, now: now.addingTimeInterval(3_600))
        XCTAssertEqual(relaunched.available?.runNumber, 149)
    }

    @MainActor
    func testAutomaticFailureDoesNotConsumePromptAndChecksAreThrottled() async {
        let monitor = AppUpdateMonitor(checker: AppUpdateChecker(transport: UpdateTransportStub(responses: [(Data(), 503), runs(), artifacts()])), defaults: UserDefaults(suiteName: UUID().uuidString)!)
        await monitor.check(installed: installed, now: now)
        await monitor.check(installed: installed, now: now.addingTimeInterval(60))
        XCTAssertNil(monitor.available)
        await monitor.check(installed: installed, now: now.addingTimeInterval(3_600))
        XCTAssertEqual(monitor.available?.runNumber, 148)
    }

    @MainActor
    func testDeferredPresentationDoesNotConsumePrompt() async {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let first = AppUpdateMonitor(checker: AppUpdateChecker(transport: UpdateTransportStub(responses: [runs(), artifacts()])), defaults: defaults)
        await first.check(installed: installed, now: now)
        let second = AppUpdateMonitor(checker: AppUpdateChecker(transport: UpdateTransportStub(responses: [runs(), artifacts()])), defaults: defaults)
        await second.check(installed: installed, now: now)
        XCTAssertEqual(second.available?.runNumber, first.available?.runNumber)
        XCTAssertNotNil(second.available)
    }

    private func runs(number: Int = 148, conclusion: String = "success") -> (Data, Int) {
        (Data("""
        {"workflow_runs":[{"id":1480,"run_number":\(number),"conclusion":"\(conclusion)","created_at":"2026-10-30T01:00:00Z"}]}
        """.utf8), 200)
    }
    private func artifacts(name: String = "AHUTong-unsigned-ipa-148", expired: Bool = false) -> (Data, Int) {
        (Data("""
        {"artifacts":[{"name":"\(name)","expired":\(expired),"size_in_bytes":6000000,"expires_at":"2099-01-01T00:00:00Z"}]}
        """.utf8), 200)
    }
}

private actor UpdateTransportStub: NetworkTransport {
    private var responses: [(Data, Int)]
    init(responses: [(Data, Int)]) { self.responses = responses }
    func data(for request: URLRequest) throws -> (Data, HTTPURLResponse) {
        guard !responses.isEmpty else { throw URLError(.badServerResponse) }
        let value = responses.removeFirst()
        return (value.0, HTTPURLResponse(url: request.url!, statusCode: value.1, httpVersion: nil, headerFields: nil)!)
    }
}
