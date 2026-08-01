import Foundation
import XCTest
@testable import AHUTong

final class OfficialPaymentPortalProbeTests: XCTestCase {
    func testSuccessfulProbeUsesCredentialFreeHeadAndReturnsSanitizedReport() async throws {
        let transport = OfficialPaymentPortalProbeTransportStub(
            behavior: .response(
                statusCode: 302,
                location: expectedLoginRedirect
            )
        )
        let service = OfficialPaymentPortalProbeService(
            transport: transport
        )

        let outcome = await service.probe()

        guard case let .passed(report) = outcome else {
            return XCTFail("Expected a passed probe, got \(outcome)")
        }
        XCTAssertEqual(report.statusCode, 302)
        XCTAssertEqual(report.redirectHost, "ycard.ahu.edu.cn")
        XCTAssertEqual(
            report.redirectPath,
            "/berserker-auth/cas/login/neusoftCas"
        )
        XCTAssertFalse(report.accessibilitySummary.contains("service="))

        let capturedRequest = await transport.capturedRequest()
        let request = try XCTUnwrap(capturedRequest)
        XCTAssertEqual(request.method, "HEAD")
        XCTAssertNil(request.body)
        XCTAssertFalse(request.handlesCookies)
        XCTAssertNil(request.cookie)
        XCTAssertNil(request.authorization)
        XCTAssertNil(request.campusAuthorization)
        XCTAssertEqual(
            request.url,
            OfficialSchoolPaymentPortal.loginURL
        )
        XCTAssertFalse(request.url.absoluteString.contains("synjones-auth"))
        XCTAssertFalse(request.url.absoluteString.contains("amount"))
        XCTAssertFalse(request.url.absoluteString.contains("order"))
        XCTAssertFalse(request.url.absoluteString.contains("account"))
    }

    func testProbeRequiresExact302SchoolLoginRedirect() async {
        let wrongStatus = OfficialPaymentPortalProbeService(
            transport: OfficialPaymentPortalProbeTransportStub(
                behavior: .response(
                    statusCode: 200,
                    location: nil
                )
            )
        )
        let wrongStatusOutcome = await wrongStatus.probe()
        XCTAssertEqual(
            wrongStatusOutcome,
            .failed(.unexpectedStatus(200))
        )

        let missingLocation = OfficialPaymentPortalProbeService(
            transport: OfficialPaymentPortalProbeTransportStub(
                behavior: .response(
                    statusCode: 302,
                    location: nil
                )
            )
        )
        let missingLocationOutcome = await missingLocation.probe()
        XCTAssertEqual(missingLocationOutcome, .failed(.missingRedirect))

        let unsafeRedirect = OfficialPaymentPortalProbeService(
            transport: OfficialPaymentPortalProbeTransportStub(
                behavior: .response(
                    statusCode: 302,
                    location: "https://ycard.ahu.edu.cn.attacker.example/berserker-auth/cas/login/neusoftCas"
                )
            )
        )
        let unsafeRedirectOutcome = await unsafeRedirect.probe()
        XCTAssertEqual(unsafeRedirectOutcome, .failed(.unsafeRedirect))

        let insecureRedirect = OfficialPaymentPortalProbeService(
            transport: OfficialPaymentPortalProbeTransportStub(
                behavior: .response(
                    statusCode: 302,
                    location: "http://ycard.ahu.edu.cn/berserker-auth/cas/login/neusoftCas"
                )
            )
        )
        let insecureRedirectOutcome = await insecureRedirect.probe()
        XCTAssertEqual(insecureRedirectOutcome, .failed(.unsafeRedirect))

        let unexpectedQuery = OfficialPaymentPortalProbeService(
            transport: OfficialPaymentPortalProbeTransportStub(
                behavior: .response(
                    statusCode: 302,
                    location: "https://ycard.ahu.edu.cn/berserker-auth/cas/login/neusoftCas?service=unapproved"
                )
            )
        )
        let unexpectedQueryOutcome = await unexpectedQuery.probe()
        XCTAssertEqual(unexpectedQueryOutcome, .failed(.unsafeRedirect))

        let wrongResponseURL = HTTPURLResponse(
            url: URL(string: "https://ycard.ahu.edu.cn/another-entry")!,
            statusCode: 302,
            httpVersion: "HTTP/1.1",
            headerFields: ["Location": expectedLoginRedirect]
        )!
        XCTAssertEqual(
            OfficialPaymentPortalProbeService.evaluate(
                response: wrongResponseURL,
                elapsedMilliseconds: 1,
                checkedAt: Date(timeIntervalSince1970: 1)
            ),
            .failed(.unsafeRedirect)
        )
    }

    func testEntryContractAcceptsEquivalentEncodingAndRejectsMaliciousVariants() throws {
        let equivalentEntryURL = try XCTUnwrap(URL(
            string: "https://ycard.ahu.edu.cn/berserker-auth/cas/redirect/neusoftCas"
                + "?targetUrl=https%3A%2F%2Fycard.ahu.edu.cn%2Fplat%2F"
                + "%3Fname%3DloginTransit"
        ))
        let equivalentResponse = try XCTUnwrap(HTTPURLResponse(
            url: equivalentEntryURL,
            statusCode: 302,
            httpVersion: "HTTP/1.1",
            headerFields: ["Location": expectedLoginRedirect]
        ))
        guard case .passed = OfficialPaymentPortalProbeService.evaluate(
            response: equivalentResponse,
            elapsedMilliseconds: 1,
            checkedAt: Date(timeIntervalSince1970: 1)
        ) else {
            return XCTFail("Equivalent percent encoding must satisfy the entry contract")
        }

        let maliciousEntries = [
            makeOfficialPaymentEntryURL(
                scheme: "http",
                target: expectedPortalTarget
            ),
            makeOfficialPaymentEntryURL(
                host: "ycard.ahu.edu.cn.attacker.example",
                target: expectedPortalTarget
            ),
            makeOfficialPaymentEntryURL(
                port: 444,
                target: expectedPortalTarget
            ),
            makeOfficialPaymentEntryURL(
                user: "attacker",
                target: expectedPortalTarget
            ),
            makeOfficialPaymentEntryURL(
                path: "/berserker-auth/cas/redirect/other",
                target: expectedPortalTarget
            ),
            makeOfficialPaymentEntryURL(
                queryName: "redirectUrl",
                target: expectedPortalTarget
            ),
            makeOfficialPaymentEntryURL(
                target: expectedPortalTarget,
                extraItems: [
                    URLQueryItem(name: "targetUrl", value: expectedPortalTarget)
                ]
            ),
            makeOfficialPaymentEntryURL(
                target: "https://attacker.example/plat/?name=loginTransit"
            ),
            makeOfficialPaymentEntryURL(
                target: "https://attacker@ycard.ahu.edu.cn/plat/?name=loginTransit"
            ),
            makeOfficialPaymentEntryURL(
                target: "https://ycard.ahu.edu.cn:444/plat/?name=loginTransit"
            ),
            makeOfficialPaymentEntryURL(
                target: "https://ycard.ahu.edu.cn/not-plat/?name=loginTransit"
            ),
            makeOfficialPaymentEntryURL(
                target: "https://ycard.ahu.edu.cn/plat?name=loginTransit"
            ),
            makeOfficialPaymentEntryURL(
                target: "https://ycard.ahu.edu.cn/plat//?name=loginTransit"
            ),
            makeOfficialPaymentEntryURL(
                target: "https://ycard.ahu.edu.cn/plat/%2e%2e/other/"
                    + "?name=loginTransit"
            ),
            makeOfficialPaymentEntryURL(
                target: "https://ycard.ahu.edu.cn/plat/?name=loginTransit&next=evil"
            ),
            makeOfficialPaymentEntryURL(
                target: "https://ycard.ahu.edu.cn/plat/?name=loginTransit#evil"
            ),
            makeOfficialPaymentEntryURL(
                target: expectedPortalTarget,
                fragment: "evil"
            )
        ]

        for entryURL in maliciousEntries {
            let response = try XCTUnwrap(HTTPURLResponse(
                url: entryURL,
                statusCode: 302,
                httpVersion: "HTTP/1.1",
                headerFields: ["Location": expectedLoginRedirect]
            ))
            XCTAssertEqual(
                OfficialPaymentPortalProbeService.evaluate(
                    response: response,
                    elapsedMilliseconds: 1,
                    checkedAt: Date(timeIntervalSince1970: 1)
                ),
                .failed(.unsafeRedirect),
                "Unexpectedly accepted entry URL: \(entryURL)"
            )
        }
    }

    func testRedirectTargetRequiresTheOfficialDirectoryURL() throws {
        let responseURL = OfficialSchoolPaymentPortal.loginURL
        let rejectedTargets = [
            "https://ycard.ahu.edu.cn/plat?name=loginTransit",
            "https://ycard.ahu.edu.cn/plat//?name=loginTransit",
            "https://ycard.ahu.edu.cn/plat/%2e%2e/other/"
                + "?name=loginTransit"
        ]

        for target in rejectedTargets {
            var components = URLComponents(
                string: "https://ycard.ahu.edu.cn/berserker-auth/cas/login/neusoftCas"
            )!
            components.queryItems = [
                URLQueryItem(name: "redirectUrl", value: target)
            ]
            let response = try XCTUnwrap(HTTPURLResponse(
                url: responseURL,
                statusCode: 302,
                httpVersion: "HTTP/1.1",
                headerFields: [
                    "Location": try XCTUnwrap(components.url).absoluteString
                ]
            ))

            XCTAssertEqual(
                OfficialPaymentPortalProbeService.evaluate(
                    response: response,
                    elapsedMilliseconds: 1,
                    checkedAt: Date(timeIntervalSince1970: 1)
                ),
                .failed(.unsafeRedirect),
                "Unexpectedly accepted redirect target: \(target)"
            )
        }
    }

    func testTransportErrorsMapToFiniteSafeFailures() async {
        let timedOut = OfficialPaymentPortalProbeService(
            transport: OfficialPaymentPortalProbeTransportStub(
                behavior: .urlError(.timedOut)
            )
        )
        let timedOutOutcome = await timedOut.probe()
        XCTAssertEqual(timedOutOutcome, .failed(.timedOut))

        let offline = OfficialPaymentPortalProbeService(
            transport: OfficialPaymentPortalProbeTransportStub(
                behavior: .urlError(.notConnectedToInternet)
            )
        )
        let offlineOutcome = await offline.probe()
        XCTAssertEqual(offlineOutcome, .failed(.offline))

        let other = OfficialPaymentPortalProbeService(
            transport: OfficialPaymentPortalProbeTransportStub(
                behavior: .urlError(.cannotParseResponse)
            )
        )
        let otherOutcome = await other.probe()
        XCTAssertEqual(otherOutcome, .failed(.transportUnavailable))
    }

    func testEphemeralTransportDisablesCookiesCredentialsAndCache() {
        let configuration =
            URLSessionOfficialPaymentPortalProbeTransport.makeConfiguration()

        XCTAssertFalse(configuration.httpShouldSetCookies)
        XCTAssertNil(configuration.httpCookieStorage)
        XCTAssertEqual(configuration.httpCookieAcceptPolicy, .never)
        XCTAssertNil(configuration.urlCredentialStorage)
        XCTAssertNil(configuration.urlCache)
        XCTAssertEqual(
            configuration.requestCachePolicy,
            .reloadIgnoringLocalAndRemoteCacheData
        )
    }

    func testNoRedirectDelegateRejectsProposedRedirect() throws {
        let sourceURL = OfficialSchoolPaymentPortal.loginURL
        let destinationURL = try XCTUnwrap(URL(
            string: "https://ycard.ahu.edu.cn/should-not-follow"
        ))
        let response = try XCTUnwrap(HTTPURLResponse(
            url: sourceURL,
            statusCode: 302,
            httpVersion: "HTTP/1.1",
            headerFields: ["Location": destinationURL.absoluteString]
        ))
        let session = URLSession(configuration: .ephemeral)
        defer { session.invalidateAndCancel() }
        let task = session.dataTask(with: sourceURL)
        let selectedRequest = OfficialPaymentProbeLockedBox<URLRequest?>(
            URLRequest(url: destinationURL)
        )
        let completionCount = OfficialPaymentProbeLockedBox(0)

        OfficialPaymentPortalNoRedirectDelegate().urlSession(
            session,
            task: task,
            willPerformHTTPRedirection: response,
            newRequest: URLRequest(url: destinationURL)
        ) { request in
            selectedRequest.withValue { $0 = request }
            completionCount.withValue { $0 += 1 }
        }

        XCTAssertNil(selectedRequest.value)
        XCTAssertEqual(completionCount.value, 1)
    }

    func testURLSessionTransportReturnsOriginal302Response() async throws {
        let requestCount = OfficialPaymentProbeLockedBox(0)
        OfficialPaymentProbeURLProtocol.handler = { request in
            requestCount.withValue { $0 += 1 }
            return HTTPURLResponse(
                url: try XCTUnwrap(request.url),
                statusCode: 302,
                httpVersion: "HTTP/1.1",
                headerFields: [
                    "Location": "https://ycard.ahu.edu.cn/should-not-follow"
                ]
            )!
        }
        defer { OfficialPaymentProbeURLProtocol.handler = nil }
        let configuration =
            URLSessionOfficialPaymentPortalProbeTransport.makeConfiguration()
        configuration.protocolClasses = [OfficialPaymentProbeURLProtocol.self]
        let transport = URLSessionOfficialPaymentPortalProbeTransport(
            configuration: configuration
        )

        let response = try await transport.response(
            for: OfficialPaymentPortalProbeService.makeRequest()
        )

        XCTAssertEqual(response.statusCode, 302)
        XCTAssertEqual(requestCount.value, 1)
    }

    func testDemoProbeInjectionIsDeterministicAndNoNetwork() async {
        let success = OfficialPaymentPortalProbeFactory.make(
            arguments: ["--demo-payment-probe=success"],
            isDemoSession: true
        )
        guard case let .passed(report) = await success.probe() else {
            return XCTFail("Expected deterministic demo success")
        }
        XCTAssertEqual(report.statusCode, 302)
        XCTAssertEqual(report.elapsedMilliseconds, 180)

        let unsafe = OfficialPaymentPortalProbeFactory.make(
            arguments: ["--demo-payment-probe=unsafe-redirect"],
            isDemoSession: true
        )
        let unsafeOutcome = await unsafe.probe()
        XCTAssertEqual(unsafeOutcome, .failed(.unsafeRedirect))

        let invalid = OfficialPaymentPortalProbeFactory.make(
            arguments: ["--demo-payment-probe=sucess"],
            isDemoSession: true
        )
        let invalidOutcome = await invalid.probe()
        XCTAssertEqual(
            invalidOutcome,
            .failed(.invalidDemoConfiguration)
        )

        let missingArgument = OfficialPaymentPortalProbeFactory.make(
            arguments: ["--demo-session"],
            isDemoSession: true
        )
        let missingArgumentOutcome = await missingArgument.probe()
        XCTAssertEqual(
            missingArgumentOutcome,
            .failed(.invalidDemoConfiguration)
        )
    }

    @MainActor
    func testOperationsModelPublishesProbeSuccessAndFailure() async {
        let report = OfficialPaymentPortalProbeReport(
            statusCode: 302,
            redirectHost: "ycard.ahu.edu.cn",
            redirectPath: "/berserker-auth/cas/login/neusoftCas",
            elapsedMilliseconds: 12,
            checkedAt: Date(timeIntervalSince1970: 1)
        )
        let successfulModel = OperationsDiagnosticsModel(
            userID: nil,
            demo: true,
            paymentPortalProbe: FixedOfficialPaymentPortalProbe(
                outcome: .passed(report)
            )
        )

        XCTAssertEqual(successfulModel.paymentPortalProbePhase, .idle)
        await successfulModel.runOfficialPaymentPortalProbe()
        XCTAssertEqual(
            successfulModel.paymentPortalProbePhase,
            .passed(report)
        )

        let failedModel = OperationsDiagnosticsModel(
            userID: nil,
            demo: true,
            paymentPortalProbe: FixedOfficialPaymentPortalProbe(
                outcome: .failed(.offline)
            )
        )
        await failedModel.runOfficialPaymentPortalProbe()
        XCTAssertEqual(
            failedModel.paymentPortalProbePhase,
            .failed(.offline)
        )
    }
}

private let expectedLoginRedirect =
    "https://ycard.ahu.edu.cn/berserker-auth/cas/login/neusoftCas"
    + "?redirectUrl=https%3A%2F%2Fycard.ahu.edu.cn%2Fplat%2F"
    + "%3Fname%3DloginTransit"

private let expectedPortalTarget =
    "https://ycard.ahu.edu.cn/plat/?name=loginTransit"

private func makeOfficialPaymentEntryURL(
    scheme: String = "https",
    host: String = "ycard.ahu.edu.cn",
    port: Int? = nil,
    user: String? = nil,
    path: String = "/berserker-auth/cas/redirect/neusoftCas",
    queryName: String = "targetUrl",
    target: String,
    extraItems: [URLQueryItem] = [],
    fragment: String? = nil
) -> URL {
    var components = URLComponents()
    components.scheme = scheme
    components.host = host
    components.port = port
    components.user = user
    components.path = path
    components.queryItems = [
        URLQueryItem(name: queryName, value: target)
    ] + extraItems
    components.fragment = fragment
    return components.url!
}

private struct OfficialPaymentPortalProbeRequestSnapshot: Sendable {
    let method: String?
    let url: URL
    let body: Data?
    let handlesCookies: Bool
    let cookie: String?
    let authorization: String?
    let campusAuthorization: String?
}

private actor OfficialPaymentPortalProbeTransportStub:
    OfficialPaymentPortalProbeTransport
{
    enum Behavior: Sendable {
        case response(statusCode: Int, location: String?)
        case urlError(URLError.Code)
    }

    private let behavior: Behavior
    private var requestSnapshot: OfficialPaymentPortalProbeRequestSnapshot?

    init(behavior: Behavior) {
        self.behavior = behavior
    }

    func response(
        for request: URLRequest
    ) async throws -> HTTPURLResponse {
        requestSnapshot = OfficialPaymentPortalProbeRequestSnapshot(
            method: request.httpMethod,
            url: request.url ?? URL(string: "about:blank")!,
            body: request.httpBody,
            handlesCookies: request.httpShouldHandleCookies,
            cookie: request.value(forHTTPHeaderField: "Cookie"),
            authorization: request.value(
                forHTTPHeaderField: "Authorization"
            ),
            campusAuthorization: request.value(
                forHTTPHeaderField: "Synjones-Auth"
            )
        )

        switch behavior {
        case let .response(statusCode, location):
            var headers: [String: String] = [:]
            if let location {
                headers["Location"] = location
            }
            return HTTPURLResponse(
                url: request.url ?? URL(string: "about:blank")!,
                statusCode: statusCode,
                httpVersion: "HTTP/1.1",
                headerFields: headers
            )!
        case let .urlError(code):
            throw URLError(code)
        }
    }

    func capturedRequest()
        -> OfficialPaymentPortalProbeRequestSnapshot?
    {
        requestSnapshot
    }
}

private struct FixedOfficialPaymentPortalProbe:
    OfficialPaymentPortalProbing
{
    let outcome: OfficialPaymentPortalProbeOutcome

    func probe() async -> OfficialPaymentPortalProbeOutcome {
        outcome
    }
}

private final class OfficialPaymentProbeURLProtocol:
    URLProtocol,
    @unchecked Sendable
{
    typealias Handler = @Sendable (URLRequest) throws -> HTTPURLResponse
    private static let registry = OfficialPaymentProbeURLProtocolRegistry()

    static var handler: Handler? {
        get { registry.handler }
        set { registry.handler = newValue }
    }

    override class func canInit(with request: URLRequest) -> Bool { true }

    override class func canonicalRequest(
        for request: URLRequest
    ) -> URLRequest {
        request
    }

    override func startLoading() {
        do {
            guard let handler = Self.handler else {
                throw URLError(.cannotLoadFromNetwork)
            }
            let response = try handler(request)
            client?.urlProtocol(
                self,
                didReceive: response,
                cacheStoragePolicy: .notAllowed
            )
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

private final class OfficialPaymentProbeURLProtocolRegistry:
    @unchecked Sendable
{
    private let lock = NSLock()
    private var storedHandler: OfficialPaymentProbeURLProtocol.Handler?

    var handler: OfficialPaymentProbeURLProtocol.Handler? {
        get {
            lock.lock()
            defer { lock.unlock() }
            return storedHandler
        }
        set {
            lock.lock()
            storedHandler = newValue
            lock.unlock()
        }
    }
}

private final class OfficialPaymentProbeLockedBox<Value>:
    @unchecked Sendable
{
    private let lock = NSLock()
    private var storedValue: Value

    init(_ value: Value) {
        storedValue = value
    }

    var value: Value {
        lock.lock()
        defer { lock.unlock() }
        return storedValue
    }

    func withValue(_ body: (inout Value) -> Void) {
        lock.lock()
        body(&storedValue)
        lock.unlock()
    }
}
