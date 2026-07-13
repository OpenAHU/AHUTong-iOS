import Foundation

enum HTTPMethod: String, Sendable {
    case get = "GET"
    case post = "POST"
    case put = "PUT"
    case patch = "PATCH"
    case delete = "DELETE"
}

struct APIRequest<Response: Decodable & Sendable>: Sendable {
    let path: String
    let method: HTTPMethod
    let query: [String: String]
    let headers: [String: String]
    let body: Data?

    init(
        path: String,
        method: HTTPMethod = .get,
        query: [String: String] = [:],
        headers: [String: String] = [:],
        body: Data? = nil
    ) {
        self.path = path
        self.method = method
        self.query = query
        self.headers = headers
        self.body = body
    }
}

enum NetworkError: Error, Equatable, Sendable {
    case invalidURL
    case nonHTTPResponse
    case unacceptableStatusCode(Int)
    case decodingFailed
}
