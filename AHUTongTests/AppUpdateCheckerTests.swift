import XCTest
@testable import AHUTong

final class AppUpdateCheckerTests: XCTestCase {
    func testSemanticVersionComparison() {
        XCTAssertEqual(AppUpdateChecker.compare("3.2.0", "3.1.9"), .orderedDescending)
        XCTAssertEqual(AppUpdateChecker.compare("3.1.9", "3.1.9"), .orderedSame)
        XCTAssertEqual(AppUpdateChecker.compare("3.1", "3.1.1"), .orderedAscending)
    }

    func testReportsNewGitHubRelease() async throws {
        let transport = UpdateTransportStub(responses: [
            (Data(#"{"tag_name":"v3.2.0","name":"新版","body":"说明","html_url":"https://github.com/OpenAHU/AHUTong-iOS/releases/tag/v3.2.0"}"#.utf8), 200)
        ])
        let result = try await AppUpdateChecker(transport: transport).check(currentVersion: "3.1.9")
        XCTAssertTrue(result.message.contains("v3.2.0"))
        XCTAssertEqual(result.destination?.host, "github.com")
    }

    func testFallsBackToLatestUnsignedBuildWhenNoReleaseExists() async throws {
        let transport = UpdateTransportStub(responses: [
            (Data(#"{"message":"Not Found"}"#.utf8), 404),
            (Data(#"{"workflow_runs":[{"run_number":55,"html_url":"https://github.com/OpenAHU/AHUTong-iOS/actions/runs/55"}]}"#.utf8), 200)
        ])
        let result = try await AppUpdateChecker(transport: transport).check(currentVersion: "3.1.9")
        XCTAssertTrue(result.message.contains("#55"))
    }
}

private actor UpdateTransportStub: NetworkTransport {
    private var responses: [(Data, Int)]
    init(responses: [(Data, Int)]) { self.responses = responses }

    func data(for request: URLRequest) throws -> (Data, HTTPURLResponse) {
        let value = responses.removeFirst()
        return (value.0, HTTPURLResponse(url: request.url!, statusCode: value.1, httpVersion: nil, headerFields: nil)!)
    }
}
