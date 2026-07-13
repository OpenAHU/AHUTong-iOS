import Foundation

protocol NetworkTransport: Sendable {
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

struct URLSessionTransport: NetworkTransport {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else {
            throw NetworkError.nonHTTPResponse
        }
        return (data, response)
    }
}
