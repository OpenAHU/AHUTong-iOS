import Foundation

protocol CampusCaptchaRecognizing: Sendable {
    func recognize(_ image: Data) async throws -> String
}

enum CampusCaptchaRecognitionError: LocalizedError, Equatable, Sendable {
    case invalidImage
    case network
    case timedOut
    case redirected
    case status(Int)
    case invalidResponse
    case invalidCode

    var errorDescription: String? {
        switch self {
        case .invalidImage: "验证码图片为空或过大"
        case .network: "远端 OCR 网络请求失败"
        case .timedOut: "远端 OCR 请求超时（20 秒）"
        case .redirected: "远端 OCR 请求被重定向"
        case let .status(code): "远端 OCR 返回 HTTP \(code)"
        case .invalidResponse: "远端 OCR 响应格式不符"
        case .invalidCode: "远端 OCR 未返回四位字母数字结果"
        }
    }
}

enum CampusCaptchaUploadFormat {
    static func detect(_ image: Data) -> (filename: String, contentType: String) {
        let bytes = [UInt8](image.prefix(12))
        if bytes.starts(with: [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]) {
            return ("img.png", "image/png")
        }
        if bytes.starts(with: Array("GIF87a".utf8)) || bytes.starts(with: Array("GIF89a".utf8)) {
            return ("img.gif", "image/gif")
        }
        if bytes.count >= 12, bytes.starts(with: Array("RIFF".utf8)),
           Array(bytes[8..<12]) == Array("WEBP".utf8) {
            return ("img.webp", "image/webp")
        }
        // The Android request uses image/jpg for the school's JPEG captcha.
        return ("img.jpg", "image/jpg")
    }
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
        let format = CampusCaptchaUploadFormat.detect(image)
        let boundary = "AHUTong-\(UUID().uuidString)"
        var body = Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"captcha\"; filename=\"\(format.filename)\"\r\nContent-Type: \(format.contentType)\r\n\r\n".utf8)
        body.append(image)
        body.append(Data("\r\n--\(boundary)--\r\n".utf8))

        var request = URLRequest(url: Self.endpoint)
        request.httpMethod = "POST"
        request.httpBody = body
        request.httpShouldHandleCookies = false
        request.timeoutInterval = 20
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.setValue("AHUTong/1.0 (iOS)", forHTTPHeaderField: "User-Agent")
        request.setValue("*/*", forHTTPHeaderField: "Accept")

        let responseData: Data
        let response: URLResponse
        do {
            (responseData, response) = try await session.data(for: request)
        } catch let error as URLError where error.code == .timedOut {
            throw CampusCaptchaRecognitionError.timedOut
        } catch {
            throw CampusCaptchaRecognitionError.network
        }
        guard let response = response as? HTTPURLResponse,
              response.url?.scheme == "https",
              response.url?.host?.lowercased() == "openahu.org",
              response.url?.path == "/ocr/captcha" else {
            throw CampusCaptchaRecognitionError.redirected
        }
        guard response.statusCode == 200 else {
            if (300..<400).contains(response.statusCode) {
                throw CampusCaptchaRecognitionError.redirected
            }
            throw CampusCaptchaRecognitionError.status(response.statusCode)
        }
        guard responseData.count <= 4_096 else {
            throw CampusCaptchaRecognitionError.invalidResponse
        }
        guard let decoded = try? JSONDecoder().decode(Response.self, from: responseData) else {
            throw CampusCaptchaRecognitionError.invalidResponse
        }
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
