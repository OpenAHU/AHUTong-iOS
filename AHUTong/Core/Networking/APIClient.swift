import Foundation

struct APIClient: Sendable {
    private let baseURL: URL
    private let transport: any NetworkTransport

    init(baseURL: URL, transport: any NetworkTransport = URLSessionTransport()) {
        self.baseURL = baseURL
        self.transport = transport
    }

    func send<Response>(_ endpoint: APIRequest<Response>) async throws -> Response {
        let request = try makeURLRequest(for: endpoint)
        let (data, response) = try await transport.data(for: request)

        guard (200..<300).contains(response.statusCode) else {
            throw NetworkError.unacceptableStatusCode(response.statusCode)
        }

        do {
            return try JSONDecoder().decode(Response.self, from: data)
        } catch is DecodingError {
            throw NetworkError.decodingFailed
        }
    }

    func makeURLRequest<Response>(for endpoint: APIRequest<Response>) throws -> URLRequest {
        let normalizedPath = endpoint.path.hasPrefix("/")
            ? String(endpoint.path.dropFirst())
            : endpoint.path
        let endpointURL = baseURL.appendingPathComponent(normalizedPath)
        guard var components = URLComponents(url: endpointURL, resolvingAgainstBaseURL: false) else {
            throw NetworkError.invalidURL
        }

        if !endpoint.query.isEmpty {
            components.queryItems = endpoint.query
                .sorted { $0.key < $1.key }
                .map { URLQueryItem(name: $0.key, value: $0.value) }
        }

        guard let url = components.url else {
            throw NetworkError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = endpoint.method.rawValue
        request.httpBody = endpoint.body
        endpoint.headers.forEach { request.setValue($0.value, forHTTPHeaderField: $0.key) }
        if endpoint.body != nil, request.value(forHTTPHeaderField: "Content-Type") == nil {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        return request
    }
}
