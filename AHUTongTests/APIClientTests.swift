import Foundation
import XCTest
@testable import AHUTong

final class APIClientTests: XCTestCase {
    @MainActor
    func testClientBuildsRequestAndDecodesResponse() async throws {
        let responseData = Data(#"{"name":"张三","xh":"AB220001"}"#.utf8)
        let transport = RecordingTransport(data: responseData, statusCode: 200)
        let client = APIClient(
            baseURL: try XCTUnwrap(URL(string: "https://example.edu/api/")),
            transport: transport
        )

        let user = try await client.send(
            APIRequest<User>(
                path: "/profile",
                query: ["term": "1", "year": "2025-2026"]
            )
        )

        XCTAssertEqual(user, User(name: "张三", studentID: "AB220001"))
        let request = await transport.lastRequest()
        XCTAssertEqual(request?.httpMethod, "GET")
        XCTAssertEqual(request?.url?.absoluteString, "https://example.edu/api/profile?term=1&year=2025-2026")
    }

    @MainActor
    func testClientRejectsNonSuccessStatus() async throws {
        let transport = RecordingTransport(data: Data(), statusCode: 401)
        let client = APIClient(
            baseURL: try XCTUnwrap(URL(string: "https://example.edu/")),
            transport: transport
        )

        do {
            let _: User = try await client.send(APIRequest<User>(path: "profile"))
            XCTFail("Expected status code failure")
        } catch let error as NetworkError {
            XCTAssertEqual(error, .unacceptableStatusCode(401))
        }
    }
}

private actor RecordingTransport: NetworkTransport {
    private let responseData: Data
    private let statusCode: Int
    private var request: URLRequest?

    init(data: Data, statusCode: Int) {
        responseData = data
        self.statusCode = statusCode
    }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        self.request = request
        let response = HTTPURLResponse(
            url: request.url ?? URL(string: "https://example.edu/")!,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: nil
        )!
        return (responseData, response)
    }

    func lastRequest() -> URLRequest? {
        request
    }
}
