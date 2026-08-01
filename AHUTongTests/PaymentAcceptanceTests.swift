import Foundation
import WebKit
import XCTest
@testable import AHUTong

final class CMBRechargeAcceptanceTests: XCTestCase {
    func testProbeUsesOnlyManualHEADAndExportsNoCredentials() async throws {
        let accessToken = "never-export-token"
        let initialCookie = "never-export-cookie"
        let redirectTicket = "ST-never-export-ticket"
        let responseCookie = "never-export-response-cookie"
        let entryURL = try CMBRechargeSecurityPolicy.makeEntryURL(
            accessToken: accessToken
        )
        let transport = CMBRechargeAcceptanceTransportStub(steps: [
            .init(
                statusCode: 302,
                location: "https://epay92.ahu.edu.cn/member/login/redirect"
                    + "?redirectUrl=charge&ticket=\(redirectTicket)",
                setCookie: "EPAY=\(responseCookie); Domain=.ahu.edu.cn; Path=/; Secure; HttpOnly"
            ),
            .init(
                statusCode: 302,
                location: "/charge-app/index?account=private",
                setCookie: nil
            ),
            .init(statusCode: 200, location: nil, setCookie: nil)
        ])
        let service = CMBRechargeAcceptanceService(
            transport: transport,
            now: { Date(timeIntervalSince1970: 1_700_000_000) }
        )
        let cookies = [
            CampusCookie(
                name: "YCardSession",
                value: initialCookie,
                domain: ".ahu.edu.cn",
                path: "/",
                secure: true,
                httpOnly: true
            ),
            CampusCookie(
                name: "Untrusted",
                value: "attacker-cookie",
                domain: "ahu.edu.cn.attacker.example",
                path: "/",
                secure: true,
                httpOnly: true
            )
        ]

        let snapshot = await service.probe(
            entryURL: entryURL,
            cookies: cookies,
            isPhysicalDevice: false
        )

        XCTAssertEqual(snapshot.completion, .simulatorPreviewPassed)
        let report = snapshot.exportText
        for secret in [
            accessToken,
            initialCookie,
            redirectTicket,
            responseCookie,
            "account=private",
            "attacker-cookie"
        ] {
            XCTAssertFalse(report.contains(secret))
        }
        XCTAssertTrue(report.contains("仅发送 HEAD"))
        XCTAssertTrue(report.contains("https://epay92.ahu.edu.cn/charge-app/index"))

        let requests = await transport.capturedRequests()
        XCTAssertEqual(requests.count, 3)
        XCTAssertTrue(requests.allSatisfy { $0.method == "HEAD" })
        XCTAssertTrue(requests.allSatisfy { $0.body == nil })
        XCTAssertTrue(requests.allSatisfy { !$0.handlesCookies })
        XCTAssertTrue(requests.allSatisfy {
            $0.url.scheme == "https"
                && ["ycard.ahu.edu.cn", "epay92.ahu.edu.cn"]
                    .contains($0.url.host ?? "")
        })
        XCTAssertTrue(requests[0].cookie?.contains(initialCookie) == true)
        XCTAssertTrue(requests[1].cookie?.contains(responseCookie) == true)
        XCTAssertFalse(requests[1].cookie?.contains("attacker-cookie") == true)
    }

    func testUnsafeRedirectFailsClosedWithoutFollowingOrExportingQuery() async throws {
        let accessToken = "temporary-secret"
        let transport = CMBRechargeAcceptanceTransportStub(steps: [
            .init(
                statusCode: 302,
                location: "https://attacker.example/collect?token=leak-me",
                setCookie: nil
            )
        ])
        let service = CMBRechargeAcceptanceService(transport: transport)

        let snapshot = await service.probe(
            entryURL: try CMBRechargeSecurityPolicy.makeEntryURL(
                accessToken: accessToken
            ),
            cookies: [],
            isPhysicalDevice: true
        )

        XCTAssertEqual(snapshot.completion, .failed)
        XCTAssertTrue(snapshot.exportText.contains("未获准的目标"))
        XCTAssertFalse(snapshot.exportText.contains(accessToken))
        XCTAssertFalse(snapshot.exportText.contains("leak-me"))
        let requestCount = await transport.requestCount()
        XCTAssertEqual(requestCount, 1)
    }

    func testFakeChargeSubstringCannotPassExactRouteContract() async throws {
        let transport = CMBRechargeAcceptanceTransportStub(steps: [
            .init(
                statusCode: 302,
                location: "https://epay92.ahu.edu.cn/fake/charge-app-result",
                setCookie: nil
            ),
            .init(statusCode: 200, location: nil, setCookie: nil)
        ])
        let service = CMBRechargeAcceptanceService(transport: transport)

        let snapshot = await service.probe(
            entryURL: try CMBRechargeSecurityPolicy.makeEntryURL(
                accessToken: "temporary"
            ),
            cookies: [],
            isPhysicalDevice: true
        )

        XCTAssertEqual(snapshot.completion, .failed)
        XCTAssertTrue(snapshot.exportText.contains("未到达已知扣款前页面"))
    }

    func testTransportResponseURLMismatchFailsClosed() async throws {
        let transport = CMBRechargeAcceptanceTransportStub(steps: [
            .init(
                statusCode: 302,
                location: "https://epay92.ahu.edu.cn/charge-app",
                setCookie: nil,
                responseURL: URL(string: "https://epay92.ahu.edu.cn/unrequested")
            )
        ])
        let service = CMBRechargeAcceptanceService(transport: transport)

        let snapshot = await service.probe(
            entryURL: try CMBRechargeSecurityPolicy.makeEntryURL(
                accessToken: "temporary"
            ),
            cookies: [],
            isPhysicalDevice: true
        )

        XCTAssertEqual(snapshot.completion, .failed)
        XCTAssertTrue(snapshot.exportText.contains("未获准的目标"))
        let requestCount = await transport.requestCount()
        XCTAssertEqual(requestCount, 1)
    }

    func testFailureIsStickyAndCannotBeOverwrittenByLaterSuccess() throws {
        var snapshot = CMBRechargeAcceptanceSnapshot(isPhysicalDevice: true)
        snapshot.recordFailure(.unsafeRedirect)
        snapshot.recordChargeRoute(
            try XCTUnwrap(URL(string: "https://epay92.ahu.edu.cn/charge-app")),
            statusCode: 200,
            hopCount: 1
        )

        XCTAssertEqual(snapshot.completion, .failed)
        XCTAssertTrue(snapshot.exportText.contains("未获准的目标"))
    }

    func testPhysicalDeviceConclusionIsDistinctFromSimulator() async throws {
        let makeTransport = {
            CMBRechargeAcceptanceTransportStub(steps: [
                .init(
                    statusCode: 302,
                    location: "https://epay92.ahu.edu.cn/charge-app",
                    setCookie: nil
                ),
                .init(statusCode: 200, location: nil, setCookie: nil)
            ])
        }
        let entryURL = try CMBRechargeSecurityPolicy.makeEntryURL(
            accessToken: "temporary"
        )
        let physicalService = CMBRechargeAcceptanceService(
            transport: makeTransport()
        )
        let simulatorService = CMBRechargeAcceptanceService(
            transport: makeTransport()
        )

        let physical = await physicalService.probe(
            entryURL: entryURL,
            cookies: [],
            isPhysicalDevice: true
        )
        let simulator = await simulatorService.probe(
            entryURL: entryURL,
            cookies: [],
            isPhysicalDevice: false
        )

        XCTAssertEqual(physical.completion, .physicalDevicePassed)
        XCTAssertEqual(simulator.completion, .simulatorPreviewPassed)
    }

    func testTransportConfigurationIsEphemeralAndCookieFree() {
        let configuration =
            URLSessionCMBRechargeAcceptanceTransport.makeConfiguration()

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

    func testEntryURLContractRejectsWhitespaceTokenAndFragment() throws {
        let validURL = try CMBRechargeSecurityPolicy.makeEntryURL(
            accessToken: "temporary"
        )
        var whitespaceToken = try XCTUnwrap(URLComponents(
            url: validURL,
            resolvingAgainstBaseURL: false
        ))
        whitespaceToken.queryItems = whitespaceToken.queryItems?.map { item in
            item.name == "synjones-auth"
                ? URLQueryItem(name: item.name, value: " \n\t ")
                : item
        }
        XCTAssertFalse(CMBRechargeAcceptancePolicy.isValidEntryURL(
            try XCTUnwrap(whitespaceToken.url)
        ))

        var fragmented = try XCTUnwrap(URLComponents(
            url: validURL,
            resolvingAgainstBaseURL: false
        ))
        fragmented.fragment = "must-not-be-accepted"
        XCTAssertFalse(CMBRechargeAcceptancePolicy.isValidEntryURL(
            try XCTUnwrap(fragmented.url)
        ))
    }

    func testCookieHeaderRejectsControlAndSeparatorCharacters() throws {
        let url = try CMBRechargeSecurityPolicy.makeEntryURL(
            accessToken: "temporary"
        )
        let cookies = [
            CampusCookie(
                name: "SAFE",
                value: "abc_123-xyz",
                domain: ".ahu.edu.cn",
                path: "/",
                secure: true,
                httpOnly: true
            ),
            CampusCookie(
                name: "LINEBREAK",
                value: "first\r\nInjected: value",
                domain: ".ahu.edu.cn",
                path: "/",
                secure: true,
                httpOnly: true
            ),
            CampusCookie(
                name: "SEPARATOR",
                value: "first;SECOND=leak",
                domain: ".ahu.edu.cn",
                path: "/",
                secure: true,
                httpOnly: true
            )
        ]

        let request = try CMBRechargeAcceptancePolicy.makeHEADRequest(
            url: url,
            cookies: cookies
        )
        let header = try XCTUnwrap(
            request.value(forHTTPHeaderField: "Cookie")
        )
        XCTAssertEqual(header, "SAFE=abc_123-xyz")
        XCTAssertFalse(header.contains("Injected"))
        XCTAssertFalse(header.contains("SECOND"))
    }

    func testResponseCookieDeletionNeverKeepsEmptyOrExpiredValues() throws {
        let requestURL = try XCTUnwrap(URL(
            string: "https://epay92.ahu.edu.cn/charge-app/index"
        ))
        var cookies = [
            CampusCookie(
                name: "EMPTY",
                value: "old",
                domain: ".ahu.edu.cn",
                path: "/charge-app",
                secure: true,
                httpOnly: true
            ),
            CampusCookie(
                name: "MAXAGE",
                value: "old",
                domain: ".ahu.edu.cn",
                path: "/charge-app",
                secure: true,
                httpOnly: true
            ),
            CampusCookie(
                name: "EXPIRES",
                value: "old",
                domain: ".ahu.edu.cn",
                path: "/charge-app",
                secure: true,
                httpOnly: true
            )
        ]
        for setCookie in [
            "EMPTY=; Domain=.ahu.edu.cn; Path=/charge-app; Secure",
            "MAXAGE=ignored; Domain=.ahu.edu.cn; Path=/charge-app; "
                + "Max-Age=0; Secure",
            "EXPIRES=ignored; Domain=.ahu.edu.cn; Path=/charge-app; "
                + "Expires=Thu, 01 Jan 1970 00:00:00 GMT; Secure"
        ] {
            let response = try XCTUnwrap(HTTPURLResponse(
                url: requestURL,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: ["Set-Cookie": setCookie]
            ))
            CMBRechargeAcceptancePolicy.mergeResponseCookies(
                response,
                requestURL: requestURL,
                into: &cookies
            )
        }

        XCTAssertTrue(cookies.isEmpty)
    }

    func testNoRedirectDelegateRejectsProposedRedirect() throws {
        let sourceURL = try CMBRechargeSecurityPolicy.makeEntryURL(
            accessToken: "temporary"
        )
        let destinationURL = try XCTUnwrap(URL(
            string: "https://epay92.ahu.edu.cn/charge-app"
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
        let selectedRequest = CMBPaymentProbeLockedBox<URLRequest?>(
            URLRequest(url: destinationURL)
        )
        let completionCount = CMBPaymentProbeLockedBox(0)

        CMBRechargeNoRedirectDelegate().urlSession(
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
        let requestCount = CMBPaymentProbeLockedBox(0)
        CMBPaymentProbeURLProtocol.handler = { request in
            requestCount.withValue { $0 += 1 }
            return HTTPURLResponse(
                url: request.url ?? URL(string: "about:blank")!,
                statusCode: 302,
                httpVersion: "HTTP/1.1",
                headerFields: [
                    "Location": "https://epay92.ahu.edu.cn/charge-app"
                ]
            )!
        }
        defer { CMBPaymentProbeURLProtocol.handler = nil }
        let configuration =
            URLSessionCMBRechargeAcceptanceTransport.makeConfiguration()
        configuration.protocolClasses = [CMBPaymentProbeURLProtocol.self]
        let transport = URLSessionCMBRechargeAcceptanceTransport(
            configuration: configuration
        )
        let request = try CMBRechargeAcceptancePolicy.makeHEADRequest(
            url: CMBRechargeSecurityPolicy.makeEntryURL(
                accessToken: "temporary"
            ),
            cookies: []
        )

        let response = try await transport.response(for: request)

        XCTAssertEqual(response.statusCode, 302)
        XCTAssertEqual(requestCount.value, 1)
    }

    func testDemoFactoryUsesDeterministicInProcessTransport() async throws {
        let service = CMBRechargeAcceptanceServiceFactory.make(
            isDemoSession: true
        )

        let snapshot = await service.probe(
            entryURL: try CMBRechargeSecurityPolicy.makeEntryURL(
                accessToken: "demo-only"
            ),
            cookies: [],
            isPhysicalDevice: false
        )

        XCTAssertEqual(snapshot.completion, .simulatorPreviewPassed)
        XCTAssertEqual(
            snapshot.generatedAt,
            Date(timeIntervalSince1970: 1_785_552_000)
        )
    }
}

final class CMBRechargeCredentialLeakTests: XCTestCase {
    @MainActor
    func testLiveWebConfigurationIsNonPersistentAndHasNoAcceptanceScript() {
        let configuration = CMBRechargeWebConfigurationFactory.make()

        XCTAssertFalse(
            configuration.websiteDataStore === WKWebsiteDataStore.default()
        )
        XCTAssertTrue(configuration.userContentController.userScripts.isEmpty)
    }

    func testDoubleEncodedCampusTokenInApprovedBankURLIsBlocked() throws {
        let leaking = try XCTUnwrap(URL(
            string: "https://pay.cmbchina.com/checkout"
                + "?return=https%253A%252F%252Fycard.ahu.edu.cn%252Fdone"
                + "%253Fsynjones-auth%253Dcampus-secret"
        ))

        XCTAssertEqual(
            CMBRechargeSecurityPolicy.navigationDecision(for: leaking),
            .block
        )
    }

    func testCredentialInApprovedBankPathIsBlocked() throws {
        let leaking = try XCTUnwrap(URL(
            string: "https://pay.cmbchina.com/checkout/synjones-auth=campus-secret"
        ))

        XCTAssertEqual(
            CMBRechargeSecurityPolicy.navigationDecision(for: leaking),
            .block
        )
    }

    func testNestedCASTicketInApprovedBankURLIsBlocked() throws {
        let leaking = try XCTUnwrap(URL(
            string: "cmbmobilebank://pay"
                + "?return=https%3A%2F%2Fycard.ahu.edu.cn%2Fdone%3Fticket%3DST-secret"
        ))

        XCTAssertEqual(
            CMBRechargeSecurityPolicy.navigationDecision(for: leaking),
            .block
        )
    }

    func testCampusTicketInBankPathAndDeepEncodingAreBlocked() throws {
        let pathLeak = try XCTUnwrap(URL(
            string: "https://pay.cmbchina.com/checkout/ticket=ST-secret"
        ))
        XCTAssertEqual(
            CMBRechargeSecurityPolicy.navigationDecision(for: pathLeak),
            .block
        )
        let fragmentLeak = try XCTUnwrap(URL(
            string: "https://pay.cmbchina.com/checkout#ticket=ST-secret"
        ))
        XCTAssertEqual(
            CMBRechargeSecurityPolicy.navigationDecision(for: fragmentLeak),
            .block
        )

        var nested = "ticket=ST-secret"
        for _ in 0..<12 {
            nested = try XCTUnwrap(
                nested.addingPercentEncoding(
                    withAllowedCharacters: .alphanumerics
                )
            )
        }
        let deeplyEncoded = try XCTUnwrap(URL(
            string: "https://pay.cmbchina.com/checkout?return=\(nested)"
        ))
        XCTAssertEqual(
            CMBRechargeSecurityPolicy.navigationDecision(
                for: deeplyEncoded
            ),
            .block
        )
    }

    func testBankOwnedTokenRemainsAllowed() throws {
        let safe = try XCTUnwrap(URL(
            string: "https://pay.cmbchina.com/checkout?token=bank-session"
        ))

        XCTAssertEqual(
            CMBRechargeSecurityPolicy.navigationDecision(for: safe),
            .openExternal(safe)
        )
    }

    func testOnlyKnownInternalHostsAndDefaultHTTPSPortAreAllowed() throws {
        XCTAssertTrue(CMBRechargeSecurityPolicy.isAllowedSchoolURL(
            try XCTUnwrap(URL(string: "https://ycard.ahu.edu.cn/charge-app"))
        ))
        XCTAssertTrue(CMBRechargeSecurityPolicy.isAllowedSchoolURL(
            try XCTUnwrap(URL(string: "https://epay92.ahu.edu.cn/charge-app"))
        ))
        XCTAssertFalse(CMBRechargeSecurityPolicy.isAllowedSchoolURL(
            try XCTUnwrap(URL(string: "https://pay.ahu.edu.cn/charge-app"))
        ))
        XCTAssertFalse(CMBRechargeSecurityPolicy.isAllowedSchoolURL(
            try XCTUnwrap(URL(string: "https://student@ycard.ahu.edu.cn/charge-app"))
        ))
        XCTAssertFalse(CMBRechargeSecurityPolicy.isAllowedSchoolURL(
            try XCTUnwrap(URL(string: "https://ycard.ahu.edu.cn:8443/charge-app"))
        ))
        XCTAssertTrue(CMBRechargeSecurityPolicy.isAllowedSchoolURL(
            try XCTUnwrap(URL(string: "https://ycard.ahu.edu.cn:443/charge-app"))
        ))

        let externalPort = try XCTUnwrap(URL(
            string: "https://pay.cmbchina.com:8443/checkout?token=bank-session"
        ))
        XCTAssertEqual(
            CMBRechargeSecurityPolicy.navigationDecision(for: externalPort),
            .block
        )
    }

    func testInvalidCookiePayloadHasDedicatedNonSensitiveError() {
        XCTAssertEqual(
            CMBRechargeBootstrapError.invalidCookies.localizedDescription,
            "校园卡 Cookie 读取失败，请刷新登录状态后重试"
        )
    }
}

private struct CMBRechargeAcceptanceRequestSnapshot: Sendable {
    let method: String?
    let url: URL
    let body: Data?
    let handlesCookies: Bool
    let cookie: String?
}

private actor CMBRechargeAcceptanceTransportStub:
    CMBRechargeAcceptanceTransport
{
    struct Step: Sendable {
        let statusCode: Int
        let location: String?
        let setCookie: String?
        let responseURL: URL?

        init(
            statusCode: Int,
            location: String?,
            setCookie: String?,
            responseURL: URL? = nil
        ) {
            self.statusCode = statusCode
            self.location = location
            self.setCookie = setCookie
            self.responseURL = responseURL
        }
    }

    private var steps: [Step]
    private var requests: [CMBRechargeAcceptanceRequestSnapshot] = []

    init(steps: [Step]) {
        self.steps = steps
    }

    func response(for request: URLRequest) async throws -> HTTPURLResponse {
        requests.append(CMBRechargeAcceptanceRequestSnapshot(
            method: request.httpMethod,
            url: request.url ?? URL(string: "about:blank")!,
            body: request.httpBody,
            handlesCookies: request.httpShouldHandleCookies,
            cookie: request.value(forHTTPHeaderField: "Cookie")
        ))
        guard !steps.isEmpty else {
            throw URLError(.cannotParseResponse)
        }
        let step = steps.removeFirst()
        var headers: [String: String] = [:]
        if let location = step.location {
            headers["Location"] = location
        }
        if let setCookie = step.setCookie {
            headers["Set-Cookie"] = setCookie
        }
        return HTTPURLResponse(
            url: step.responseURL
                ?? request.url
                ?? URL(string: "about:blank")!,
            statusCode: step.statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: headers
        )!
    }

    func capturedRequests() -> [CMBRechargeAcceptanceRequestSnapshot] {
        requests
    }

    func requestCount() -> Int {
        requests.count
    }
}

private final class CMBPaymentProbeURLProtocol:
    URLProtocol,
    @unchecked Sendable
{
    typealias Handler = @Sendable (URLRequest) throws -> HTTPURLResponse
    private static let registry = CMBPaymentProbeURLProtocolRegistry()

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

    override func stopLoading() { }
}

private final class CMBPaymentProbeURLProtocolRegistry:
    @unchecked Sendable
{
    private let lock = NSLock()
    private var storedHandler: CMBPaymentProbeURLProtocol.Handler?

    var handler: CMBPaymentProbeURLProtocol.Handler? {
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

private final class CMBPaymentProbeLockedBox<Value>:
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
