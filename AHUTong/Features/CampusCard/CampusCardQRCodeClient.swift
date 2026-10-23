import Foundation

/// The same first-party endpoint used by Android, independent of the loopback transport.
struct CampusCardQRCodeClient: Sendable {
    static let endpoint = URL(string: "https://adwmh.ahu.edu.cn/xzxcard/qrcode")!
    private let session: URLSession

    init(session: URLSession = Self.makeSession()) { self.session = session }

    func payload(cookiesJSON: String) async throws -> String {
        let cookies = try JSONDecoder().decode([CampusCookie].self, from: Data(cookiesJSON.utf8))
        var request = URLRequest(url: Self.endpoint)
        request.timeoutInterval = 12
        request.httpShouldHandleCookies = false
        request.setValue("XMLHttpRequest", forHTTPHeaderField: "X-Requested-With")
        let header = cookies.filter { $0.matches(Self.endpoint) }
            .map { "\($0.name)=\($0.value)" }.joined(separator: "; ")
        if !header.isEmpty { request.setValue(header, forHTTPHeaderField: "Cookie") }
        // A login redirect must never forward a manually attached Cookie header.
        let (data, response) = try await session.data(for: request, delegate: QRRedirectBlocker())
        try Task.checkCancellation()
        guard let response = response as? HTTPURLResponse else { throw CampusCoreError.invalidResponse }
        if CampusSessionExpiryDetector.isExpired(response: response, data: data)
            || (300..<400).contains(response.statusCode) {
            throw CampusCoreError.unauthorized
        }
        guard (200..<300).contains(response.statusCode) else {
            throw CampusCoreError.campus("校园码服务暂不可用，请重试")
        }
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let code = (root["code"] as? NSNumber)?.intValue
                ?? (root["code"] as? String).flatMap(Int.init) else {
            throw CampusCoreError.invalidResponse
        }
        // This service can report an expired session inside an HTTP 200 response.
        guard code == 10_000 else { throw CampusCoreError.unauthorized }
        return try CampusCardResponseParser().qrPayload(from: data)
    }

    private static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCache = nil
        configuration.timeoutIntervalForRequest = 12
        configuration.timeoutIntervalForResource = 12
        return URLSession(configuration: configuration)
    }
}

private final class QRRedirectBlocker: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(
        _ session: URLSession, task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
        completionHandler: @escaping @Sendable (URLRequest?) -> Void
    ) { completionHandler(nil) }
}

enum CampusCardQRRecovery {
    private static let logger = RedactingLogger(category: "campus-card-qr")
    /// Each transport is bounded by its own URLSession timeout. Cancellation never falls through.
    static func payload(
        firstParty: @Sendable () async throws -> String,
        fallback: @Sendable () async throws -> String,
        refresh: @Sendable () async throws -> Void = {}
    ) async throws -> String {
        var needsRefresh = false
        do { return try await firstParty() }
        catch {
            try checkCancellation(error)
            report(error, stage: "first-party")
            needsRefresh = error as? CampusCoreError == .unauthorized
        }
        do { return try await fallback() }
        catch {
            try checkCancellation(error)
            report(error, stage: "rust-http")
            needsRefresh = needsRefresh || error as? CampusCoreError == .unauthorized
        }
        // One display attempt can renew at most once, after trying both sessions.
        if needsRefresh {
            do { try await refresh() }
            catch {
                AppDiagnostics.shared.report(.campusCodeFailed, stage: .refresh, error: error)
                throw error
            }
            try Task.checkCancellation()
            do { return try await firstParty() }
            catch {
                try checkCancellation(error)
                report(error, stage: "first-party-renewed")
            }
            // The renewed Rust session may work even if the direct transport
            // is still unavailable. Do not start another renewal here.
            return try await finalRead(stage: .rust, operation: fallback)
        }
        return try await finalRead(stage: .firstParty, operation: firstParty)
    }

    private static func finalRead(
        stage: DiagnosticStage, operation: @Sendable () async throws -> String
    ) async throws -> String {
        do { return try await operation() }
        catch {
            AppDiagnostics.shared.report(.campusCodeFailed, stage: stage, error: error)
            throw error
        }
    }

    private static func checkCancellation(_ error: Error) throws {
        if error is CancellationError || (error as? URLError)?.code == .cancelled { throw error }
        try Task.checkCancellation()
    }

    private static func report(_ error: Error, stage: String) {
        if let error = error as? URLError {
            logger.notice("QR stage=\(stage) network-code=\(error.code.rawValue)")
        } else {
            let category = error as? CampusCoreError == .unauthorized ? "session-expired" : "service-response"
            logger.notice("QR stage=\(stage) category=\(category)")
        }
    }
}
