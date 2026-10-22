import Foundation
import XCTest
@testable import AHUTong

final class StudentMailTests: XCTestCase {
    func testObservedFolderMessageAndDetailContracts() throws {
        let folders = try StudentMailProtocol.folders(data(#"{"code":"S_OK","var":[{"id":1,"name":"收件箱","stats":{"messageCount":12,"unreadMessageCount":3}}]}"#))
        XCTAssertEqual(folders.first, StudentMailFolder(id: 1, name: "收件箱", total: 12, unread: 3))
        let page = try StudentMailProtocol.page(data(#"{"code":"S_OK","total":1,"var":[{"id":"m1","fid":1,"subject":"通知","from":"A <a@example.test>","to":"b@example.test","summary":"<b>课程</b>","flags":{"read":false},"attachments":[{"id":"2.1","filename":"课件.pdf","contentLength":512}]}]}"#))
        XCTAssertEqual(page.messages.first?.summary, "课程")
        XCTAssertEqual(page.messages.first?.attachments.first?.partID, "2.1")
        XCTAssertEqual(page.messages.first?.isRead, false)
        let detail = try StudentMailProtocol.detail(data(#"{"code":"S_OK","var":{"subject":"通知","from":"a@example.test","to":["b@example.test"],"html":{"content":"<style>hidden</style><script>secret()</script><div>一&lt;二</div><div>&#x1F4DA; &amp; &#65;</div>"},"attachments":[]}}"#), id: "m1")
        XCTAssertEqual(detail.text, "一<二\n📚 & A")
        XCTAssertEqual(detail.from, ["a@example.test"])
    }

    func testResponseErrorsNeverEchoSchoolTextOrCredentials() {
        for json in [#"{"code":"S_INVALID_SID","message":"PRIVATE-TOKEN"}"#, #"{"code":200,"success":false,"message":"PRIVATE-TOKEN"}"#, "<html>PRIVATE-TOKEN</html>"] {
            XCTAssertThrowsError(try StudentMailProtocol.root(data(json))) {
                XCTAssertFalse($0.localizedDescription.contains("PRIVATE-TOKEN"))
            }
        }
    }

    func testRoutesRejectForeignHostsCredentialsPortsAndUnsafeProxyCallbacks() throws {
        for raw in ["https://example.test/", "https://mail.stu.ahu.edu.cn.example.test/",
                    "https://user:pass@mail.stu.ahu.edu.cn/", "https://mail.stu.ahu.edu.cn:444/",
                    "http://entryhz.qiye.163.com/domain/oa/Entry"] {
            XCTAssertThrowsError(try StudentMailRoutes.validate(URL(string: raw)!, campus: false))
        }
        XCTAssertEqual(try StudentMailRoutes.validate(URL(string: "http://mail.stu.ahu.edu.cn/redirect?sid=fixture")!, campus: false).scheme, "https")
        let view = URL(string: "https://wvpn.ahu.edu.cn/https/77726476706e69737468656265737421fff944d226387d1e7b0c9ce29b5b/tp_up/view")!
        let callback = URL(string: "https://one.ahu.edu.cn/tp_up/view?m=up&ticket=fixture")!
        XCTAssertEqual(try StudentMailRoutes.proxyCallback(view: view, callback: callback).host, "wvpn.ahu.edu.cn")
        XCTAssertThrowsError(try StudentMailRoutes.proxyCallback(view: view, callback: URL(string: "https://one.ahu.edu.cn/tp_up/view?m=up")!))
        let redirect = StudentMailRoutes.htmlRedirect(#"<script>window.location.replace('https://mail.stu.ahu.edu.cn/redirect?sid=fixture')</script>"#,
            base: URL(string: "https://entryhz.qiye.163.com/domain/oa/Entry")!)
        XCTAssertEqual(redirect?.host, StudentMailRoutes.host)
    }

    func testComposeEscapesTextAndNeverSilentlyDropsUnsupportedResources() throws {
        var draft = StudentMailDraft(to: "one@example.test；two@example.test;one@example.test", subject: "合成主题", body: "<script>safe text</script>\n下一行")
        XCTAssertTrue(draft.canSend)
        let request = try StudentMailProtocol.composeBody(draft, account: "owner@example.test", action: "deliver")
        let attrs = StudentMailProtocol.object(request["attrs"])
        XCTAssertEqual(attrs["to"] as? [String], ["one@example.test", "two@example.test"])
        XCTAssertEqual(attrs["content"] as? String, "<div>&lt;script&gt;safe text&lt;/script&gt;<br>下一行</div>")
        XCTAssertEqual(StudentMailProtocol.readBody(id: "fixture")["markRead"] as? Bool, false)
        draft.unsupportedResources = true
        XCTAssertFalse(draft.canSend)
        XCTAssertThrowsError(try StudentMailProtocol.composeBody(draft, account: "owner@example.test", action: "continue"))
    }

    func testExpiredReadRenewsOnceUsingPortalSSOAndKeepsCookieJarsSeparate() async throws {
        MailHTTPFixture.state.reset(expireRead: true)
        let (client, _, _, transport) = try await makeClient()
        defer { transport.invalidateAndCancel() }
        let folders = try await client.folders()
        XCTAssertEqual(folders.first?.name, "收件箱")
        let requests = MailHTTPFixture.state.requests
        XCTAssertEqual(requests.filter { function($0) == "mbox:getAllFolders" }.count, 2)
        XCTAssertEqual(requests.filter { $0.url?.path == "/cas/login" }.count, 1)
        XCTAssertEqual(requests.first { $0.url?.path.hasSuffix("generateSsoUrl") == true }?.value(forHTTPHeaderField: "Referer"),
                       "https://one.ahu.edu.cn/tp_up/view?m=up")
        for request in requests {
            let header = request.value(forHTTPHeaderField: "Cookie") ?? ""
            if request.url?.host == "one.ahu.edu.cn" {
                XCTAssertFalse(header.contains("Coremail"))
                if request.url?.path == "/tp_up/up/subgroup/generateSsoUrl" { XCTAssertTrue(header.contains("PORTAL-PATH")) }
            } else if request.url?.host == StudentMailRoutes.host {
                XCTAssertFalse(header.contains("CASTGC"))
                XCTAssertFalse(header.contains("ENTRY-ONLY"))
            } else {
                XCTAssertFalse(header.contains("CASTGC"))
                XCTAssertFalse(header.contains("Coremail"))
            }
        }
    }

    func testStoredMailboxSessionIsReusedWithoutAnotherCampusLogin() async throws {
        MailHTTPFixture.state.reset()
        let (client, _, _, transport) = try await makeClient()
        defer { transport.invalidateAndCancel() }
        _ = try await client.folders()
        XCTAssertEqual(MailHTTPFixture.state.requests.count, 1)
    }

    func testOfficialWebFallbackReceivesOnlyItsIsolatedMailboxContext() async throws {
        MailHTTPFixture.state.reset()
        let (client, _, _, transport) = try await makeClient()
        defer { transport.invalidateAndCancel() }
        let context = try await client.webContext()
        XCTAssertEqual(context.url.host, StudentMailRoutes.host)
        XCTAssertEqual(context.cookies.map(\.cookie.name), ["Coremail"])
        XCTAssertFalse(context.cookies.contains { $0.cookie.name == "CASTGC" })
        XCTAssertEqual(MailHTTPFixture.state.requests.count, 1)
        XCTAssertTrue(MailHTTPFixture.state.requests[0].url!.path.hasSuffix("accountInfo"))
    }

    func testInvalidRecipientsNeverCreateOrDeliverADraft() async throws {
        MailHTTPFixture.state.reset()
        let (client, _, _, transport) = try await makeClient()
        defer { transport.invalidateAndCancel() }
        do {
            try await client.save(StudentMailDraft(to: "invalid-address", body: "fixture"), deliver: true)
            XCTFail("Recipient validation must precede side effects")
        } catch { XCTAssertEqual(error as? StudentMailError, .invalidResponse) }
        XCTAssertTrue(MailHTTPFixture.state.requests.isEmpty)
    }

    func testLogoutClearsStoredMailboxAndOldClientCannotReadAnotherAccount() async throws {
        MailHTTPFixture.state.reset()
        let (client, store, secure, transport) = try await makeClient()
        defer { transport.invalidateAndCancel() }
        _ = try await client.folders()
        try await store.clear()
        let saved = try await secure.data(forAccount: StudentMailRoutes.secureAccount)
        XCTAssertNil(saved)
        try await store.save(CampusSessionSnapshot(user: User(name: "另一个合成用户", studentID: "other-fixture"), cookiesJSON: "[]"))
        do {
            _ = try await client.folders()
            XCTFail("An old mailbox must not follow the new account")
        } catch { XCTAssertEqual(error as? StudentMailError, .signInRequired) }
        XCTAssertEqual(MailHTTPFixture.state.requests.count, 1)
    }

    func testLostDeliveryAcknowledgementIsNotRetriedOrReloggedIn() async throws {
        MailHTTPFixture.state.reset(failDelivery: true)
        let (client, _, _, transport) = try await makeClient()
        defer { transport.invalidateAndCancel() }
        do {
            try await client.save(StudentMailDraft(to: "reader@example.test", subject: "合成邮件", body: "合成内容"), deliver: true)
            XCTFail("A lost acknowledgement is uncertain")
        } catch { XCTAssertEqual(error as? StudentMailError, .deliveryUncertain) }
        let requests = MailHTTPFixture.state.requests
        XCTAssertEqual(requests.filter { query($0, "action") == "deliver" }.count, 1)
        XCTAssertFalse(requests.contains { $0.url?.path == "/cas/login" })
    }

    func testAttachmentRequestCannotInjectAnArbitraryRoute() async throws {
        MailHTTPFixture.state.reset()
        let (client, _, _, transport) = try await makeClient()
        defer { transport.invalidateAndCancel() }
        let attachment = StudentMailAttachment(messageID: "m1", partID: "../anything?sid=other", name: "../x", size: 1)
        do {
            _ = try await client.download(attachment)
            XCTFail("An arbitrary route must not be requested")
        } catch { XCTAssertEqual(error as? StudentMailError, .invalidResponse) }
        XCTAssertTrue(MailHTTPFixture.state.requests.isEmpty)
    }

    private func makeClient() async throws -> (StudentMailClient, CampusSessionStore, InMemorySecureStore, URLSession) {
        let secure = InMemorySecureStore()
        let store = CampusSessionStore(secureStore: secure)
        try await store.save(CampusSessionSnapshot(user: User(name: "合成用户", studentID: "mail-fixture"), cookiesJSON: "[]"))
        let stored = StudentMailStoredSession(owner: "mail-fixture", sid: "old-fixture", address: "owner@example.test",
            cookies: [StudentMailStoredCookie(cookie: CampusCookie(name: "Coremail", value: "MAIL-ONLY",
                domain: StudentMailRoutes.host, path: "/", secure: true, httpOnly: true), expiresAt: nil)])
        try await secure.set(JSONEncoder().encode(stored), forAccount: StudentMailRoutes.secureAccount)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MailHTTPFixture.self]
        let transport = URLSession(configuration: configuration)
        return (StudentMailClient(owner: "mail-fixture", campus: MailFixtureCampusAPI(), campusStore: store,
            secureStore: secure, transport: transport), store, secure, transport)
    }
    private func data(_ string: String) -> Data { Data(string.utf8) }
    private func query(_ request: URLRequest, _ name: String) -> String? {
        request.url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false) }?.queryItems?.first { $0.name == name }?.value
    }
    private func function(_ request: URLRequest) -> String? { query(request, "func") }
}

private actor MailFixtureCampusAPI: CampusCoreAPI {
    func initialize(cookiesJSON: String) {}
    func dumpCookies() -> String { "[]" }
    func cookiesFlat() -> String { #"[{"name":"CASTGC","value":"CAMPUS-ONLY","domain":"one.ahu.edu.cn","path":"/","secure":true}]"# }
    func schedule() -> [Course] { [] }
    func currentWeek() -> Int { 7 }
    func exams() -> [CampusExam] { [] }
    func grades() -> CampusGradeReport { CampusGradeReport(grades: [], gradePointAverage: nil, rank: nil, studentProfiles: []) }
    func cardBalance() -> Double { 0 }
    func cardQRCode() -> String { "fixture" }
}

private final class MailHTTPState: @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [URLRequest] = []
    private var expireRead = false
    private var failDelivery = false
    private var expired = false
    var requests: [URLRequest] { lock.withLock { recorded } }
    func reset(expireRead: Bool = false, failDelivery: Bool = false) {
        lock.withLock { recorded = []; self.expireRead = expireRead; self.failDelivery = failDelivery; expired = false }
    }
    func response(_ request: URLRequest) -> (Int, [String: String], String, Bool) {
        lock.withLock {
            recorded.append(request)
            let url = request.url!
            let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
            let function = items.first { $0.name == "func" }?.value ?? ""
            if items.first(where: { $0.name == "action" })?.value == "deliver", failDelivery { return (0, [:], "", true) }
            if function == "mbox:getAllFolders" {
                if expireRead && !expired { expired = true; return (200, [:], #"{"code":"S_INVALID_SID"}"#, false) }
                return (200, [:], #"{"code":"S_OK","var":[{"id":1,"name":"收件箱","stats":{"messageCount":0,"unreadMessageCount":0}}]}"#, false)
            }
            if function == "mbox:compose" { return (200, [:], #"{"code":"S_OK","var":{"id":"compose-fixture","attachments":[]}}"#, false) }
            if url.path == "/cas/login" {
                return (302, ["Location": "https://one.ahu.edu.cn/tp_up/view?m=up",
                    "Set-Cookie": "PORTAL-PATH=synthetic; Path=/tp_up; Secure"], "", false)
            }
            if url.path == "/tp_up/view" { return (200, [:], "portal", false) }
            if url.path.hasSuffix("generateSsoUrl") { return (200, [:], #"{"ssourl":"https://entryhz.qiye.163.com/domain/oa/Entry?token=synthetic"}"#, false) }
            if url.host == StudentMailRoutes.entryHost {
                return (200, ["Set-Cookie": "ENTRY-ONLY=synthetic; Path=/; Secure"],
                    #"<script>window.location.replace('https://mail.stu.ahu.edu.cn/redirect?sid=new-fixture')</script>"#, false)
            }
            if url.path == "/redirect" {
                return (302, ["Location": "https://mail.stu.ahu.edu.cn/static/sirius-web/?sid=new-fixture",
                    "Set-Cookie": "Coremail=NEW-MAIL-ONLY; Path=/; Secure"], "", false)
            }
            if url.path.hasSuffix("accountInfo") { return (200, [:], #"{"code":0,"success":true,"data":{"defaultSender":{"email":"owner@example.test"}}}"#, false) }
            return (200, [:], "mail", false)
        }
    }
}

private final class MailHTTPFixture: URLProtocol, @unchecked Sendable {
    static let state = MailHTTPState()
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let (status, headers, body, failure) = Self.state.response(request)
        if failure { client?.urlProtocol(self, didFailWithError: URLError(.timedOut)); return }
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
