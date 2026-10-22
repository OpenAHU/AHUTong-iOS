import Foundation

struct StudentMailStoredCookie: Codable, Sendable {
    let cookie: CampusCookie
    let expiresAt: Date?
}

struct StudentMailStoredSession: Codable, Sendable {
    let owner: String
    let sid: String
    let address: String
    let cookies: [StudentMailStoredCookie]
}

struct StudentMailWebContext: Sendable {
    let url: URL
    let cookies: [StudentMailStoredCookie]
}

enum StudentMailRoutes {
    private static let logger = RedactingLogger(category: "student-mail")
    static let host = "mail.stu.ahu.edu.cn"
    static let entryHost = "entryhz.qiye.163.com"
    static let portal = URL(string: "https://one.ahu.edu.cn/tp_up/view?m=up")!
    static let secureAccount = "student-mail.session"

    static func destination(_ url: URL) -> String {
        switch url.host {
        case "one.ahu.edu.cn": "portal"
        case "wvpn.ahu.edu.cn": "vpn"
        case host: "mail"
        case entryHost: "entry"
        default: "other"
        }
    }

    static func domainMatches(_ cookie: CampusCookie, host: String) -> Bool {
        let domain = cookie.domain.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
        return !domain.isEmpty && (host == domain || host.hasSuffix("." + domain))
    }

    static func validate(_ url: URL, campus: Bool) throws -> URL {
        var parts = URLComponents(url: url, resolvingAgainstBaseURL: true)
        let allowed = campus ? ["one.ahu.edu.cn", "wvpn.ahu.edu.cn"] : [host, entryHost]
        guard let components = parts, components.user == nil, components.password == nil,
              let hostname = components.host, allowed.contains(hostname) else {
            let reason = parts?.user != nil || parts?.password != nil ? "credentials" : "host"
            logger.notice("route.rejected destination=\(destination(url)) reason=\(reason)")
            throw StudentMailError.untrustedRoute
        }
        // Official WebVPN redirects include client-side routes after '#'. They
        // are never part of an HTTP request or its destination authorization.
        parts?.fragment = nil
        // The observed official entry sometimes emits an HTTP mailbox redirect.
        if !campus, hostname == host, components.scheme == "http", components.port == nil || components.port == 80 {
            parts?.scheme = "https"
            parts?.port = nil
        }
        guard parts?.scheme == "https", parts?.port == nil || parts?.port == 443, let result = parts?.url else {
            logger.notice("route.rejected destination=\(destination(url)) reason=transport")
            throw StudentMailError.untrustedRoute
        }
        return result
    }

    static func cas(service: URL) -> URL {
        var value = URLComponents(string: "https://one.ahu.edu.cn/cas/login")!
        value.queryItems = [URLQueryItem(name: "service", value: service.absoluteString)]
        return value.url!
    }

    static func proxyCallback(view: URL, callback: URL) throws -> URL {
        let trustedPath = "/https/77726476706e69737468656265737421fff944d226387d1e7b0c9ce29b5b/tp_up/view"
        _ = try validate(view, campus: true)
        _ = try validate(callback, campus: true)
        guard view.host == "wvpn.ahu.edu.cn", view.path == trustedPath,
              callback.host == "one.ahu.edu.cn", callback.path == "/tp_up/view",
              let parts = URLComponents(url: callback, resolvingAgainstBaseURL: false),
              parts.queryItems?.contains(where: { $0.name == "m" && $0.value == "up" }) == true,
              parts.queryItems?.contains(where: { $0.name == "ticket" && $0.value?.isEmpty == false }) == true else {
            throw StudentMailError.untrustedRoute
        }
        var result = URLComponents(url: view, resolvingAgainstBaseURL: false)!
        result.percentEncodedQuery = parts.percentEncodedQuery
        return result.url!
    }

    static func htmlRedirect(_ html: String, base: URL) -> URL? {
        let patterns = [
            #"(?i)window\.location\.replace\(\s*['"]([^'"]+)['"]\s*\)"#,
            #"(?i)<meta\b[^>]*content\s*=\s*["'][^"']*?url\s*=\s*([^"'>]+)"#
        ]
        for pattern in patterns {
            guard let expression = try? NSRegularExpression(pattern: pattern),
                  let match = expression.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
                  let range = Range(match.range(at: 1), in: html) else { continue }
            return URL(string: String(html[range]).trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: "&amp;", with: "&"), relativeTo: base)?.absoluteURL
        }
        return nil
    }
}

private final class StudentMailRedirectBlocker: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
        completionHandler: @escaping @Sendable (URLRequest?) -> Void) { completionHandler(nil) }
}

private final class StudentMailDownloadLimiter: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    static let maximumBytes: Int64 = 30 * 1024 * 1024
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,
                    totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        if totalBytesWritten > Self.maximumBytes || totalBytesExpectedToWrite > Self.maximumBytes { downloadTask.cancel() }
    }
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {}
    func urlSession(_ session: URLSession, task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
        completionHandler: @escaping @Sendable (URLRequest?) -> Void) { completionHandler(nil) }
}

actor StudentMailClient {
    private let logger = RedactingLogger(category: "student-mail")
    private let owner: String
    private let campus: any CampusCoreAPI
    private let campusStore: CampusSessionStore
    private let secureStore: any SecureStore
    private let transport: URLSession
    private var jars: [String: [StudentMailStoredCookie]] = [:]
    private var sid: String?
    private var address = ""
    private var sessionKey = UUID()
    private var connecting: Task<String, Error>?
    private let deviceID = UUID().uuidString

    init(owner: String, campus: any CampusCoreAPI, campusStore: CampusSessionStore = CampusSessionStore(),
         secureStore: any SecureStore = KeychainSecureStore(), transport: URLSession? = nil) {
        self.owner = owner
        self.campus = campus
        self.campusStore = campusStore
        self.secureStore = secureStore
        let config = URLSessionConfiguration.ephemeral
        config.httpCookieStorage = nil
        config.httpShouldSetCookies = false
        config.urlCache = nil
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 180
        self.transport = transport ?? URLSession(configuration: config)
    }

    private func assertCurrent() async throws {
        try Task.checkCancellation()
        guard try await campusStore.load()?.user.studentID == owner else { throw StudentMailError.signInRequired }
    }

    func connect() async throws -> String {
        try await assertCurrent()
        if sid != nil { return address }
        if let connecting { return try await connecting.value }
        let task = Task { try await establish() }
        connecting = task
        defer { connecting = nil }
        return try await task.value
    }

    private func establish() async throws -> String {
        logger.notice("connect.begin")
        if let data = try await secureStore.data(forAccount: StudentMailRoutes.secureAccount),
           let stored = try? JSONDecoder().decode(StudentMailStoredSession.self, from: data),
           stored.owner == owner, !stored.sid.isEmpty, StudentMailProtocol.validAddress(stored.address) {
            let cookies = stored.cookies.filter { $0.expiresAt == nil || $0.expiresAt! > Date() }
                .filter { StudentMailRoutes.domainMatches($0.cookie, host: StudentMailRoutes.host) }
            if !cookies.isEmpty {
                jars["mail.\(StudentMailRoutes.host)"] = cookies
                sid = stored.sid
                address = stored.address
                return address
            }
        }
        let initial = try await campus.cookiesFlat()
        try seedPortal(initial)
        let loginURL = StudentMailRoutes.cas(service: StudentMailRoutes.portal)
        var page = try await follow(loginURL, scope: "portal", campus: true)
        if page.0.path.hasPrefix("/cas/login") {
            try await campus.refreshSession(scope: .academic)
            try seedPortal(try await campus.cookiesFlat())
            page = try await follow(loginURL, scope: "portal", campus: true)
        }
        guard !page.0.path.hasPrefix("/cas/login") else { throw StudentMailError.signInRequired }
        let endpoint = URL(string: "https://one.ahu.edu.cn/tp_up/up/subgroup/generateSsoUrl")!
        var entry = try await sso(endpoint, scope: "portal")
        if let vpnView = entry.vpn {
            logger.notice("connect.vpn.begin")
            let portalKey = "portal.one.ahu.edu.cn"
            jars["vpn.one.ahu.edu.cn"] = (jars[portalKey] ?? []).filter { ["CASTGC", "TGC"].contains($0.cookie.name) }
            _ = try await send(URLRequest(url: URL(string: "https://wvpn.ahu.edu.cn/login")!), scope: "vpn", campus: true)
            let vpnLogin = StudentMailRoutes.cas(service: URL(string: "https://wvpn.ahu.edu.cn/login?cas_login=true")!)
            let vpnPage = try await follow(vpnLogin, scope: "vpn", campus: true)
            guard vpnPage.0.host == "wvpn.ahu.edu.cn" else { throw StudentMailError.signInRequired }
            let callbackResponse = try await send(URLRequest(url: loginURL), scope: "vpn", campus: true)
            guard callbackResponse.1.statusCode == 302,
                  let location = callbackResponse.1.value(forHTTPHeaderField: "Location"),
                  let callback = URL(string: location, relativeTo: loginURL)?.absoluteURL else { throw StudentMailError.invalidResponse }
            let proxied = try StudentMailRoutes.proxyCallback(view: vpnView, callback: callback)
            let proxyPage = try await follow(proxied, scope: "vpn", campus: true)
            guard proxyPage.0.host == vpnView.host, proxyPage.0.path == vpnView.path else { throw StudentMailError.signInRequired }
            let vpnEndpoint = vpnView.deletingLastPathComponent().appendingPathComponent("up/subgroup/generateSsoUrl")
            entry = try await sso(vpnEndpoint, scope: "vpn")
        }
        guard let entryURL = entry.url else { throw StudentMailError.invalidResponse }
        logger.notice("connect.mail.begin")
        var mailPage = try await follow(entryURL, scope: "mail", campus: false)
        var capturedSID = URLComponents(url: mailPage.0, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "sid" }?.value
        if mailPage.0.host == StudentMailRoutes.entryHost {
            guard let redirect = StudentMailRoutes.htmlRedirect(String(decoding: mailPage.1, as: UTF8.self), base: mailPage.0) else {
                throw StudentMailError.invalidResponse
            }
            let target = try StudentMailRoutes.validate(redirect, campus: false)
            guard target.host == StudentMailRoutes.host, target.path == "/redirect" else { throw StudentMailError.untrustedRoute }
            capturedSID = URLComponents(url: target, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "sid" }?.value
            mailPage = try await follow(target, scope: "mail", campus: false)
        }
        capturedSID = URLComponents(url: mailPage.0, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "sid" }?.value ?? capturedSID
        guard mailPage.0.host == StudentMailRoutes.host, let capturedSID, !capturedSID.isEmpty,
              !(jars["mail.\(StudentMailRoutes.host)"] ?? []).isEmpty else { throw StudentMailError.invalidResponse }
        sid = capturedSID
        sessionKey = UUID()
        do {
            let data = try await rawRPC(path: "cowork/api/biz/enter/accountInfo", query: ["needUnitNamePath": "false"])
            let account = StudentMailProtocol.object(try StudentMailProtocol.root(data)["data"])
            let defaultSender = StudentMailProtocol.object(account["defaultSender"])
            address = StudentMailProtocol.string(defaultSender, "email")
            if address.isEmpty { address = StudentMailProtocol.string(account, "email") }
            guard StudentMailProtocol.validAddress(address) else { throw StudentMailError.invalidResponse }
            try await persist()
            return address
        } catch {
            await invalidate()
            throw error
        }
    }

    private func seedPortal(_ json: String) throws {
        let cookies = try JSONDecoder().decode([CampusCookie].self, from: Data(json.utf8))
        jars["portal.one.ahu.edu.cn"] = cookies.filter { $0.matches(StudentMailRoutes.cas(service: StudentMailRoutes.portal)) }
            .map { StudentMailStoredCookie(cookie: $0, expiresAt: nil) }
    }

    private func sso(_ url: URL, scope: String) async throws -> (url: URL?, vpn: URL?) {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = Data("{}".utf8)
        request.setValue("application/json;charset=UTF-8", forHTTPHeaderField: "Content-Type")
        request.setValue("XMLHttpRequest", forHTTPHeaderField: "X-Requested-With")
        request.setValue("https://\(url.host!)", forHTTPHeaderField: "Origin")
        let portalBase = url.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        var referer = URLComponents(url: portalBase.appendingPathComponent("view"), resolvingAgainstBaseURL: false)!
        referer.queryItems = [URLQueryItem(name: "m", value: "up")]
        request.setValue(referer.url!.absoluteString, forHTTPHeaderField: "Referer")
        request.setValue("application/json, text/javascript, */*; q=0.01", forHTTPHeaderField: "Accept")
        let (data, response) = try await send(request, scope: scope, campus: true)
        if let location = response.value(forHTTPHeaderField: "Location"),
           let redirect = URL(string: location, relativeTo: url)?.absoluteURL,
           redirect.host == "wvpn.ahu.edu.cn", redirect.path.range(of: #"^/https/[a-f0-9]+/tp_up/view$"#, options: .regularExpression) != nil {
            _ = try StudentMailRoutes.validate(redirect, campus: true)
            return (nil, redirect)
        }
        guard (200..<300).contains(response.statusCode),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let raw = root["ssourl"] as? String, let entry = URL(string: raw) else { throw StudentMailError.unavailable }
        let trusted = try StudentMailRoutes.validate(entry, campus: false)
        guard trusted.host == StudentMailRoutes.entryHost, trusted.path == "/domain/oa/Entry" else {
            logger.notice("sso.rejected reason=entry-target")
            throw StudentMailError.untrustedRoute
        }
        return (trusted, nil)
    }

    private func follow(_ initial: URL, scope: String, campus: Bool) async throws -> (URL, Data) {
        var url = try StudentMailRoutes.validate(initial, campus: campus)
        for _ in 0..<12 {
            let (data, response) = try await send(URLRequest(url: url), scope: scope, campus: campus)
            if [301, 302, 303, 307, 308].contains(response.statusCode) {
                guard let location = response.value(forHTTPHeaderField: "Location"),
                      let next = URL(string: location, relativeTo: url)?.absoluteURL else { throw StudentMailError.invalidResponse }
                url = try StudentMailRoutes.validate(next, campus: campus)
            } else {
                guard (200..<300).contains(response.statusCode) else { throw StudentMailError.unavailable }
                return (url, data)
            }
        }
        throw StudentMailError.invalidResponse
    }

    private func send(_ input: URLRequest, scope: String, campus: Bool) async throws -> (Data, HTTPURLResponse) {
        try await assertCurrent()
        guard let inputURL = input.url else { throw StudentMailError.untrustedRoute }
        let url = try StudentMailRoutes.validate(inputURL, campus: campus)
        let key = "\(scope).\(url.host!)"
        var request = input
        request.url = url
        request.httpShouldHandleCookies = false
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/154.0.0.0 Safari/537.36 Edg/154.0.0.0", forHTTPHeaderField: "User-Agent")
        let cookies = (jars[key] ?? []).filter { ($0.expiresAt == nil || $0.expiresAt! > Date()) && $0.cookie.matches(url) }
        request.setValue(cookies.map { "\($0.cookie.name)=\($0.cookie.value)" }.joined(separator: "; "), forHTTPHeaderField: "Cookie")
        let (data, response) = try await transport.data(for: request, delegate: StudentMailRedirectBlocker())
        try await assertCurrent()
        guard let response = response as? HTTPURLResponse else { throw StudentMailError.invalidResponse }
        logger.notice("http.response scope=\(scope) destination=\(StudentMailRoutes.destination(url)) status=\(response.statusCode)")
        let headers = response.allHeaderFields.reduce(into: [String: String]()) { result, item in
            if let name = item.key as? String, let value = item.value as? String { result[name] = value }
        }
        for received in HTTPCookie.cookies(withResponseHeaderFields: headers, for: url) {
            let cookie = CampusCookie(name: received.name, value: received.value, domain: received.domain,
                path: received.path, secure: received.isSecure, httpOnly: nil)
            // Set-Cookie may intentionally target a path reached by the next
            // redirect (for example /tp_up while responding from /cas/login).
            guard StudentMailRoutes.domainMatches(cookie, host: url.host!) else { continue }
            jars[key, default: []].removeAll { $0.cookie.name == cookie.name && $0.cookie.domain == cookie.domain && $0.cookie.path == cookie.path }
            if !CampusCookieResponsePolicy.shouldDelete(received) {
                jars[key, default: []].append(StudentMailStoredCookie(cookie: cookie, expiresAt: received.expiresDate))
            }
        }
        return (data, response)
    }

    private func rpcURL(path: String, query: [String: String]) throws -> URL {
        guard let sid else { throw StudentMailError.expired }
        var parts = URLComponents(string: "https://\(StudentMailRoutes.host)/\(path)")!
        let base = ["sid": sid, "_host": StudentMailRoutes.host, "p": "web", "_appName": "sirius-web",
                    "_version": "1.66.2", "_deviceId": deviceID]
        parts.queryItems = base.merging(query) { _, value in value }.sorted { $0.key < $1.key }
            .map { URLQueryItem(name: $0.key, value: $0.value) }
        return parts.url!
    }

    private func rawRPC(path: String = "js6/s", query: [String: String], body: Data? = nil,
                        contentType: String = "application/json;charset=UTF-8") async throws -> Data {
        var request = URLRequest(url: try rpcURL(path: path, query: query))
        request.httpMethod = body == nil ? "GET" : "POST"
        request.httpBody = body
        if body != nil { request.setValue(contentType, forHTTPHeaderField: "Content-Type") }
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("zh", forHTTPHeaderField: "lingxi-language")
        request.setValue("https://\(StudentMailRoutes.host)", forHTTPHeaderField: "Origin")
        request.setValue("https://\(StudentMailRoutes.host)/static/sirius-web/", forHTTPHeaderField: "Referer")
        if query["action"] == "deliver" {
            request.setValue("QIYE_MAIL", forHTTPHeaderField: "mail-server-type")
            request.setValue("hz", forHTTPHeaderField: "mail-server-location")
        }
        let (data, response) = try await send(request, scope: "mail", campus: false)
        if [301, 302, 303, 307, 308, 401, 403].contains(response.statusCode) { throw StudentMailError.expired }
        guard (200..<300).contains(response.statusCode) else { throw StudentMailError.unavailable }
        _ = try StudentMailProtocol.root(data)
        return data
    }

    private func read(path: String = "js6/s", query: [String: String], body: Data? = nil) async throws -> Data {
        _ = try await connect()
        do {
            let data = try await rawRPC(path: path, query: query, body: body)
            try await persist()
            return data
        } catch StudentMailError.expired {
            await invalidate()
            _ = try await connect()
            let data = try await rawRPC(path: path, query: query, body: body)
            try await persist()
            return data
        }
    }

    private func persist() async throws {
        try await assertCurrent()
        guard let sid, !address.isEmpty else { return }
        let stored = StudentMailStoredSession(owner: owner, sid: sid, address: address,
            cookies: jars["mail.\(StudentMailRoutes.host)"] ?? [])
        try await secureStore.set(try JSONEncoder().encode(stored), forAccount: StudentMailRoutes.secureAccount)
    }

    func invalidate() async {
        sid = nil
        address = ""
        jars.removeAll()
        sessionKey = UUID()
        try? await secureStore.removeValue(forAccount: StudentMailRoutes.secureAccount)
    }

    func folders() async throws -> [StudentMailFolder] {
        try StudentMailProtocol.folders(await read(query: ["func": "mbox:getAllFolders"],
            body: JSONSerialization.data(withJSONObject: ["order": "custom_virtual"])))
    }
    func messages(folder: Int, start: Int = 0, unread: Bool = false) async throws -> StudentMailPage {
        try StudentMailProtocol.page(await read(query: ["func": "mbox:listMessages"],
            body: JSONSerialization.data(withJSONObject: StudentMailProtocol.listBody(folder: folder, start: start, unread: unread))))
    }
    func detail(id: String) async throws -> StudentMailDetail {
        try StudentMailProtocol.detail(await read(query: ["func": "mbox:readMessage", "l": "read", "supportTNEF": "true"],
            body: JSONSerialization.data(withJSONObject: StudentMailProtocol.readBody(id: id))), id: id)
    }
    func contacts() async throws -> [StudentMailContact] {
        _ = try await connect()
        let personal = try StudentMailProtocol.contacts(await read(path: "cowork/api/biz/person/personContactList",
            query: ["email": address, "lastUpdateTime": "0"]), recent: false)
        let recent = try StudentMailProtocol.contacts(await read(path: "recent/api/biz/recent/recentContactList",
            query: ["page": "1", "pageSize": "30", "conditionType": "1", "contactType": "1", "_account": address]), recent: true)
        var seen = Set<String>()
        return (personal + recent).filter { seen.insert($0.id).inserted }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    func restoreDraft(id: String) async throws -> StudentMailDraft {
        let data = try await read(query: ["func": "mbox:restoreDraft"], body: JSONSerialization.data(withJSONObject: ["id": id]))
        return try StudentMailProtocol.restoredDraft(data, sessionKey: sessionKey)
    }

    func beginDraft(_ input: StudentMailDraft) async throws -> StudentMailDraft {
        _ = try await connect()
        if input.composeID != nil {
            guard input.sessionKey == sessionKey else { throw StudentMailError.expired }
            return input
        }
        guard input.attachments.isEmpty else { throw StudentMailError.expired }
        let body = try JSONSerialization.data(withJSONObject: StudentMailProtocol.composeBody(input, account: address, action: "continue"))
        let root = try StudentMailProtocol.root(await rawRPC(query: ["func": "mbox:compose"], body: body))
        let id = StudentMailProtocol.string(StudentMailProtocol.object(root["var"]), "id")
        guard !id.isEmpty else { throw StudentMailError.invalidResponse }
        var draft = input
        draft.composeID = id
        draft.sessionKey = sessionKey
        return draft
    }

    func save(_ input: StudentMailDraft, deliver: Bool) async throws {
        if deliver, !input.canSend { throw StudentMailError.invalidResponse }
        let draft = try await beginDraft(input)
        let body = try JSONSerialization.data(withJSONObject: StudentMailProtocol.composeBody(draft, account: address, action: deliver ? "deliver" : "save"))
        do {
            let data = try await rawRPC(query: ["func": "mbox:compose", "l": "compose", "action": deliver ? "deliver" : "save",
                "xMailerExt": "Sirius_WEB_WIN_1.66.2"], body: body)
            let root = try StudentMailProtocol.root(data)
            if deliver {
                guard !StudentMailProtocol.string(StudentMailProtocol.object(root["savedSent"]), "mid").isEmpty else {
                    throw StudentMailError.deliveryUncertain
                }
            } else {
                guard StudentMailProtocol.string(StudentMailProtocol.object(root["var"]), "id") == draft.composeID,
                      !StudentMailProtocol.string(root, "draftId").isEmpty else { throw StudentMailError.draftUncertain }
            }
        } catch {
            if error is CancellationError { throw error }
            throw deliver ? StudentMailError.deliveryUncertain : StudentMailError.draftUncertain
        }
    }

    func webContext() async throws -> StudentMailWebContext {
        // A long-lived native page may outlive its mailbox session. Validate a
        // read before handing the official client a SID rather than a stale URL.
        _ = try await read(path: "cowork/api/biz/enter/accountInfo", query: ["needUnitNamePath": "false"])
        guard let sid else { throw StudentMailError.expired }
        var components = URLComponents(string: "https://\(StudentMailRoutes.host)/static/sirius-web/")!
        components.queryItems = [URLQueryItem(name: "sid", value: sid)]
        return StudentMailWebContext(url: components.url!, cookies: jars["mail.\(StudentMailRoutes.host)"] ?? [])
    }

    func move(id: String, to folder: Int) async throws {
        guard [1, 4].contains(folder), !id.isEmpty, id.count <= 512, !id.contains(where: \.isWhitespace) else { throw StudentMailError.invalidResponse }
        _ = try await connect()
        let body = try JSONSerialization.data(withJSONObject: ["ids": [id], "attrs": ["fid": folder],
            "needFilter": false, "_account": address, "riskHitIntercept": true])
        do {
            let data = try await rawRPC(query: ["func": "mbox:updateMessageInfos"], body: body)
            guard try StudentMailProtocol.root(data)["code"] as? String == "S_OK" else { throw StudentMailError.moveUncertain }
        } catch {
            if error is CancellationError { throw error }
            throw StudentMailError.moveUncertain
        }
    }

    func download(_ attachment: StudentMailAttachment) async throws -> URL {
        guard !attachment.messageID.isEmpty, attachment.messageID.count <= 512,
              attachment.partID.range(of: #"^[0-9]+(?:\.[0-9]+)*$"#, options: .regularExpression) != nil else {
            throw StudentMailError.invalidResponse
        }
        guard attachment.size <= StudentMailDownloadLimiter.maximumBytes else { throw StudentMailError.attachmentTooLarge }
        _ = try await connect()
        do { return try await downloadCurrent(attachment) }
        catch StudentMailError.expired {
            await invalidate()
            _ = try await connect()
            return try await downloadCurrent(attachment)
        }
    }

    private func downloadCurrent(_ attachment: StudentMailAttachment) async throws -> URL {
        try await assertCurrent()
        let url = try rpcURL(path: "js6/s", query: ["func": "mbox:getMessageData", "mode": "download",
            "part": attachment.partID, "mid": attachment.messageID, "trigger_type": "user_click"])
        var request = URLRequest(url: url)
        request.httpShouldHandleCookies = false
        let cookies = (jars["mail.\(StudentMailRoutes.host)"] ?? [])
            .filter { ($0.expiresAt == nil || $0.expiresAt! > Date()) && $0.cookie.matches(url) }
        request.setValue(cookies.map { "\($0.cookie.name)=\($0.cookie.value)" }.joined(separator: "; "), forHTTPHeaderField: "Cookie")
        request.setValue("*/*", forHTTPHeaderField: "Accept")
        request.setValue("https://\(StudentMailRoutes.host)/static/sirius-web/", forHTTPHeaderField: "Referer")
        let (temporary, rawResponse) = try await transport.download(for: request, delegate: StudentMailDownloadLimiter())
        defer { try? FileManager.default.removeItem(at: temporary) }
        try await assertCurrent()
        guard let response = rawResponse as? HTTPURLResponse else { throw StudentMailError.invalidResponse }
        if [301, 302, 303, 307, 308, 401, 403].contains(response.statusCode) { throw StudentMailError.expired }
        guard (200..<300).contains(response.statusCode) else { throw StudentMailError.unavailable }
        let size = try temporary.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size <= StudentMailDownloadLimiter.maximumBytes else { throw StudentMailError.attachmentTooLarge }
        let disposition = response.value(forHTTPHeaderField: "Content-Disposition") ?? ""
        if response.mimeType == "application/json", size < 65_536 {
            _ = try StudentMailProtocol.root(Data(contentsOf: temporary))
            throw StudentMailError.invalidResponse
        }
        guard response.mimeType != "application/json",
              response.mimeType != "text/html" || disposition.lowercased().contains("attachment") else { throw StudentMailError.invalidResponse }
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("AHUTong-Mail/\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let name = URL(fileURLWithPath: attachment.name).lastPathComponent
        let target = folder.appendingPathComponent(name.isEmpty || name == "." || name == ".." ? "附件" : name)
        try FileManager.default.copyItem(at: temporary, to: target)
        try FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: target.path)
        return target
    }

    func upload(_ input: StudentMailDraft, file: URL, name: String, contentType: String) async throws -> StudentMailDraft {
        let size = try file.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size > 0, size <= 20 * 1024 * 1024 else { throw StudentMailError.attachmentTooLarge }
        var draft = try await beginDraft(input)
        guard let compose = draft.composeID else { throw StudentMailError.invalidResponse }
        let prepare = try JSONSerialization.data(withJSONObject: ["attachmentId": -1, "composeId": compose,
            "contentType": contentType, "fileName": name, "offset": 0, "size": size])
        let prepared = try StudentMailProtocol.object(StudentMailProtocol.root(await rawRPC(
            query: ["func": "upload:prepare"], body: prepare))["var"])
        let attachmentID = StudentMailProtocol.string(prepared, "attachmentId")
        guard let id = Int64(attachmentID), id > 0, StudentMailProtocol.string(prepared, "composeId") == compose,
              StudentMailProtocol.integer(prepared, "size") == size, StudentMailProtocol.integer(prepared, "actualSize") == 0 else {
            throw StudentMailError.invalidResponse
        }
        let uploaded = try StudentMailProtocol.object(StudentMailProtocol.root(await rawRPC(
            query: ["func": "upload:directData", "composeId": compose, "attachmentId": attachmentID, "offset": "0"],
            body: Data(contentsOf: file, options: .mappedIfSafe), contentType: contentType))["var"])
        guard StudentMailProtocol.string(uploaded, "attachmentId") == attachmentID,
              StudentMailProtocol.string(uploaded, "composeId") == compose,
              StudentMailProtocol.integer(uploaded, "size") == size, StudentMailProtocol.integer(uploaded, "actualSize") == size else {
            throw StudentMailError.invalidResponse
        }
        draft.attachments.append(StudentMailDraftAttachment(id: id, name: name, size: Int64(size), contentType: contentType))
        // Explicitly sync the final attachment list, matching the official client.
        let body = try JSONSerialization.data(withJSONObject: StudentMailProtocol.composeBody(draft, account: address, action: "continue"))
        let returned = try StudentMailProtocol.restoredDraft(await rawRPC(query: ["func": "mbox:compose"], body: body), sessionKey: sessionKey)
        guard Set(returned.attachments.map(\.id)) == Set(draft.attachments.map(\.id)) else { throw StudentMailError.invalidResponse }
        return draft
    }

    func removeAttachment(_ input: StudentMailDraft, id: Int64) async throws -> StudentMailDraft {
        let draft = try await beginDraft(input)
        guard draft.attachments.contains(where: { $0.id == id }), let compose = draft.composeID else { throw StudentMailError.invalidResponse }
        let body = try JSONSerialization.data(withJSONObject: ["id": compose, "action": "continue", "delayTime": 0,
            "mailTrace": false, "returnInfo": true, "xMailerExt": "Sirius_WEB_WIN_1.66.2",
            "attrs": ["account": address, "attachments": [["id": id, "deleted": true]]]])
        let returned = try StudentMailProtocol.restoredDraft(await rawRPC(query: ["func": "mbox:compose"], body: body), sessionKey: sessionKey)
        guard Set(returned.attachments.map(\.id)) == Set(draft.attachments.filter { $0.id != id }.map(\.id)) else {
            throw StudentMailError.invalidResponse
        }
        var result = draft
        result.attachments.removeAll { $0.id == id }
        return result
    }
}
