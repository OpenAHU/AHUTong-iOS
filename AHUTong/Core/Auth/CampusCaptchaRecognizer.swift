import Foundation

protocol CampusCaptchaRecognizing: Sendable {
    func recognize(_ image: Data) async throws -> String
}

enum CampusCaptchaRecognitionError: Error, Equatable {
    case invalidImage
    case invalidResponse
    case invalidCode
}

struct RemoteCampusCaptchaRecognizer: CampusCaptchaRecognizing {
    static let endpoint = URL(string: "https://openahu.org/ocr/captcha")!

    private let session: URLSession

    init(session: URLSession = Self.makeSession()) {
        self.session = session
    }

    func recognize(_ image: Data) async throws -> String {
        guard !image.isEmpty, image.count <= 256_000 else {
            throw CampusCaptchaRecognitionError.invalidImage
        }
        let boundary = "AHUTong-\(UUID().uuidString)"
        var body = Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"captcha\"; filename=\"img.jpg\"\r\nContent-Type: image/jpeg\r\n\r\n".utf8)
        body.append(image)
        body.append(Data("\r\n--\(boundary)--\r\n".utf8))

        var request = URLRequest(url: Self.endpoint)
        request.httpMethod = "POST"
        request.httpBody = body
        request.httpShouldHandleCookies = false
        request.timeoutInterval = 10
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        let (responseData, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse,
              response.url?.scheme == "https",
              response.url?.host?.lowercased() == "openahu.org",
              response.statusCode == 200,
              responseData.count <= 4_096 else {
            throw CampusCaptchaRecognitionError.invalidResponse
        }
        let decoded = try JSONDecoder().decode(Response.self, from: responseData)
        let code = decoded.result.trimmingCharacters(in: .whitespacesAndNewlines)
        guard code.range(of: "^[A-Za-z0-9]{4}$", options: .regularExpression) != nil else {
            throw CampusCaptchaRecognitionError.invalidCode
        }
        return code
    }

    private struct Response: Decodable {
        let result: String
    }

    private static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpShouldSetCookies = false
        configuration.httpCookieAcceptPolicy = .never
        configuration.urlCache = nil
        return URLSession(configuration: configuration, delegate: CampusOCRRedirectBlocker(), delegateQueue: nil)
    }
}

private final class CampusOCRRedirectBlocker: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping @Sendable (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }
}
