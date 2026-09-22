import Foundation
import SwiftUI
import UIKit
import WebKit

enum CampusSessionScope: String, Codable, Hashable, Sendable {
    case academic
    case campusCard
}

struct CampusWebAuthenticationResult: Sendable {
    let credentials: LoginCredentials?
    let cookies: [CampusCookie]
}

@MainActor
protocol CampusWebAuthenticating: AnyObject {
    func refreshAcademic(credentials: LoginCredentials) async throws -> CampusWebAuthenticationResult
}

enum CampusCookieMerger {
    static func merge(existing: [CampusCookie], incoming: [CampusCookie]) -> [CampusCookie] {
        var result = existing
        for cookie in incoming {
            result.removeAll {
                $0.name == cookie.name
                    && normalizedDomain($0.domain) == normalizedDomain(cookie.domain)
                    && CampusCookie.normalizedPath($0.path) == CampusCookie.normalizedPath(cookie.path)
            }
            result.append(cookie)
        }
        return result
    }

    private static func normalizedDomain(_ value: String) -> String {
        value.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
    }
}

actor CampusInteractiveAuthenticationCoordinator {
    static let shared = CampusInteractiveAuthenticationCoordinator()

    private var continuation: CheckedContinuation<Void, Error>?

    func requestCampusCardLogin() async throws {
        if continuation != nil {
            throw CampusWebAuthenticationError.interactionRequired
        }
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            Task { @MainActor in
                NotificationCenter.default.post(name: .campusCardAuthenticationRequired, object: nil)
            }
        }
    }

    func succeed() {
        continuation?.resume()
        continuation = nil
    }

    func fail(_ error: CampusWebAuthenticationError) {
        continuation?.resume(throwing: error)
        continuation = nil
    }
}

enum CampusWebAuthenticationError: LocalizedError, Equatable, Sendable {
    case cancelled
    case inactive
    case timedOut
    case blockedNavigation
    case credentialsUnavailable
    case credentialsRejected
    case interactionRequired
    case invalidResponse
    case navigationFailed

    var errorDescription: String? {
        switch self {
        case .cancelled: "已取消登录"
        case .inactive: "请回到 App 前台后重试登录"
        case .timedOut: "校方登录超时，请重试"
        case .blockedNavigation: "已阻止打开非校方登录页面"
        case .credentialsUnavailable: "本机没有可用的登录信息"
        case .credentialsRejected: "账号或密码已失效，请重新登录"
        case .interactionRequired: "校方登录需要您继续操作"
        case .invalidResponse: "校方登录页返回了无法识别的结果"
        case .navigationFailed: "校方登录页加载失败，请检查网络"
        }
    }
}

enum CampusWebNavigationPolicy {
    static let academicEntryURL = URL(string: "https://jw.ahu.edu.cn/student/sso/login")!
    static let campusCardEntryURL = URL(string: "https://adwmh.ahu.edu.cn/index/tologin")!

    static func isAllowed(_ url: URL, scope: CampusSessionScope) -> Bool {
        guard url.scheme?.lowercased() == "https",
              url.user == nil,
              url.password == nil,
              let host = url.host?.lowercased() else {
            return false
        }
        switch scope {
        case .academic:
            return host == "one.ahu.edu.cn" || host == "jw.ahu.edu.cn"
        case .campusCard:
            return host == "adwmh.ahu.edu.cn"
        }
    }

    static func isAcademicLoginPage(_ url: URL?) -> Bool {
        guard let url else { return false }
        return url.scheme == "https"
            && url.host?.lowercased() == "one.ahu.edu.cn"
            && (url.path == "/cas/login" || url.path.hasPrefix("/cas/login/"))
    }

    static func isSuccess(_ url: URL?, scope: CampusSessionScope) -> Bool {
        guard let url, isAllowed(url, scope: scope) else { return false }
        switch scope {
        case .academic:
            return url.host?.lowercased() == "jw.ahu.edu.cn"
                && (url.path == "/student/home" || url.path.hasPrefix("/student/home/"))
        case .campusCard:
            return url.host?.lowercased() == "adwmh.ahu.edu.cn"
                && (url.path == "/index/user/success" || url.path.hasPrefix("/index/user/success/"))
        }
    }
}

enum CampusWebCookiePolicy {
    static func cookies(from values: [HTTPCookie], scope: CampusSessionScope) -> [CampusCookie] {
        values.compactMap { value in
            let domain = value.domain
                .trimmingCharacters(in: CharacterSet(charactersIn: "."))
                .lowercased()
            let allowed: Bool
            switch scope {
            case .academic:
                allowed = domain == "one.ahu.edu.cn" || domain == "jw.ahu.edu.cn"
                    || domain == "ahu.edu.cn"
            case .campusCard:
                allowed = domain == "adwmh.ahu.edu.cn" || domain == "ahu.edu.cn"
            }
            guard allowed else { return nil }
            return CampusCookie(
                name: value.name,
                value: value.value,
                domain: value.domain,
                path: value.path,
                // The school currently emits some session cookies without a
                // Secure attribute even though the login origin is HTTPS.
                // Promote every accepted cookie so native clients never send
                // captured credentials over plaintext transport.
                secure: true,
                httpOnly: value.properties?[HTTPCookiePropertyKey(rawValue: "HttpOnly")] != nil
            )
        }
    }
}

@MainActor
final class CampusWebLoginEngine: NSObject, ObservableObject, WKNavigationDelegate, WKUIDelegate,
    WKScriptMessageHandler {
    enum Mode {
        case visibleAcademic
        case hiddenAcademic(LoginCredentials)
        case visibleCampusCard(LoginCredentials)

        var scope: CampusSessionScope {
            switch self {
            case .visibleAcademic, .hiddenAcademic: .academic
            case .visibleCampusCard: .campusCard
            }
        }

        var isVisible: Bool {
            switch self {
            case .visibleAcademic, .visibleCampusCard: true
            case .hiddenAcademic: false
            }
        }
    }

    @Published private(set) var errorMessage: String?
    @Published private(set) var progress = 0.0
    let webView: WKWebView

    private static let captureHandler = "campusCredentialCapture"
    private let mode: Mode
    private var continuation: CheckedContinuation<CampusWebAuthenticationResult, Error>?
    private var timeoutTask: Task<Void, Never>?
    private var pendingCredentials: LoginCredentials?
    private var attemptedAutomation = false
    private var completed = false

    init(mode: Mode) {
        self.mode = mode
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.limitsNavigationsToAppBoundDomains = true
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
        configuration.applicationNameForUserAgent = "AHUTong/iOS"
        webView = WKWebView(frame: .zero, configuration: configuration)
        super.init()
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.allowsBackForwardNavigationGestures = mode.isVisible
        configureScripts()
    }

    deinit {
        timeoutTask?.cancel()
    }

    func start() async throws -> CampusWebAuthenticationResult {
        guard continuation == nil, !completed else {
            throw CampusWebAuthenticationError.invalidResponse
        }
        if !mode.isVisible, UIApplication.shared.applicationState != .active {
            throw CampusWebAuthenticationError.inactive
        }
        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            let entryURL = mode.scope == .academic
                ? CampusWebNavigationPolicy.academicEntryURL
                : CampusWebNavigationPolicy.campusCardEntryURL
            var request = URLRequest(
                url: entryURL,
                cachePolicy: .reloadIgnoringLocalAndRemoteCacheData,
                timeoutInterval: 30
            )
            request.setValue("no-store", forHTTPHeaderField: "Cache-Control")
            webView.load(request)
            if !mode.isVisible {
                timeoutTask = Task { [weak self] in
                    try? await Task.sleep(for: .seconds(30))
                    guard !Task.isCancelled else { return }
                    self?.finish(throwing: CampusWebAuthenticationError.timedOut)
                }
            }
        }
    }

    func cancel() {
        finish(throwing: CampusWebAuthenticationError.cancelled)
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction
    ) async -> WKNavigationActionPolicy {
        guard let url = navigationAction.request.url,
              CampusWebNavigationPolicy.isAllowed(url, scope: mode.scope) else {
            errorMessage = CampusWebAuthenticationError.blockedNavigation.localizedDescription
            return .cancel
        }
        if navigationAction.targetFrame == nil {
            webView.load(navigationAction.request)
            return .cancel
        }
        return .allow
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationResponse: WKNavigationResponse
    ) async -> WKNavigationResponsePolicy {
        guard let url = navigationResponse.response.url,
              CampusWebNavigationPolicy.isAllowed(url, scope: mode.scope) else {
            errorMessage = CampusWebAuthenticationError.blockedNavigation.localizedDescription
            return .cancel
        }
        if let response = navigationResponse.response as? HTTPURLResponse,
           !(200..<400).contains(response.statusCode) {
            errorMessage = CampusWebAuthenticationError.navigationFailed.localizedDescription
            return .cancel
        }
        return .allow
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation?) {
        progress = 1
        guard !completed else { return }
        if CampusWebNavigationPolicy.isSuccess(webView.url, scope: mode.scope) {
            Task { await finishSuccessfully() }
            return
        }
        switch mode {
        case let .hiddenAcademic(credentials):
            guard CampusWebNavigationPolicy.isAcademicLoginPage(webView.url) else { return }
            if attemptedAutomation {
                detectRejectedCredentials()
            } else {
                attemptedAutomation = true
                automateAcademicLogin(credentials)
            }
        case let .visibleCampusCard(credentials):
            prefillCampusCardLogin(credentials)
        case .visibleAcademic:
            break
        }
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation?) {
        progress = 0
        errorMessage = nil
    }

    func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation?,
        withError error: Error
    ) {
        handleNavigationFailure(error)
    }

    func webView(
        _ webView: WKWebView,
        didFail navigation: WKNavigation?,
        withError error: Error
    ) {
        handleNavigationFailure(error)
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == Self.captureHandler,
              message.frameInfo.request.url?.scheme?.lowercased() == "https",
              message.frameInfo.request.url?.host?.lowercased() == "one.ahu.edu.cn",
              let body = message.body as? [String: Any],
              let username = body["username"] as? String,
              let password = body["password"] as? String else {
            return
        }
        let canonicalID = StudentIDCanonicalizer.canonical(username)
        guard !canonicalID.isEmpty, !password.isEmpty else { return }
        pendingCredentials = LoginCredentials(studentID: canonicalID, password: password)
    }

    private func configureScripts() {
        guard case .visibleAcademic = mode else { return }
        let script = #"""
        (() => {
          const capture = () => {
            const username = document.querySelector('#un')?.value || '';
            const password = document.querySelector('#pd')?.value || '';
            if (username && password) {
              window.webkit.messageHandlers.campusCredentialCapture.postMessage({username, password});
            }
          };
          document.addEventListener('click', event => {
            if (event.target && (event.target.id === 'index_login_btn' || event.target.closest('#index_login_btn'))) capture();
          }, true);
          document.addEventListener('submit', capture, true);
          const style = document.createElement('style');
          style.textContent = '#qrcode_login,#mobile_login,#saveDevice,.new-login-way{display:none!important;}';
          document.documentElement.appendChild(style);
        })();
        """#
        let controller = webView.configuration.userContentController
        controller.add(self, name: Self.captureHandler)
        controller.addUserScript(
            WKUserScript(source: script, injectionTime: .atDocumentEnd, forMainFrameOnly: true)
        )
    }

    private func automateAcademicLogin(_ credentials: LoginCredentials) {
        let script = #"""
        const usernameField = document.querySelector('#un');
        const passwordField = document.querySelector('#pd');
        const loginButton = document.querySelector('#index_login_btn');
        if (!usernameField || !passwordField || !loginButton) return false;
        usernameField.value = username;
        passwordField.value = password;
        usernameField.dispatchEvent(new Event('input', {bubbles: true}));
        passwordField.dispatchEvent(new Event('input', {bubbles: true}));
        loginButton.click();
        return true;
        """#
        webView.callAsyncJavaScript(
            script,
            arguments: [
                "username": credentials.studentID,
                "password": credentials.password
            ],
            in: nil,
            in: .page,
            completionHandler: { [weak self] result in
            let succeeded: Bool
            if case let .success(value) = result {
                succeeded = value as? Bool == true
            } else {
                succeeded = false
            }
            Task { @MainActor [weak self] in
                guard let self else { return }
                guard succeeded else {
                    self.finish(throwing: CampusWebAuthenticationError.interactionRequired)
                    return
                }
                self.pendingCredentials = credentials
            }
        })
    }

    private func detectRejectedCredentials() {
        let script = #"""
        const error = document.querySelector('#errormsg');
        if (!error) return false;
        const style = window.getComputedStyle(error);
        return style.display !== 'none' && (error.textContent || '').trim().length > 0;
        """#
        webView.callAsyncJavaScript(
            script,
            arguments: [:],
            in: nil,
            in: .page,
            completionHandler: { [weak self] result in
            let rejected: Bool
            if case let .success(value) = result {
                rejected = value as? Bool == true
            } else {
                rejected = false
            }
            Task { @MainActor [weak self] in
                guard let self else { return }
                if rejected {
                    self.finish(throwing: CampusWebAuthenticationError.credentialsRejected)
                } else {
                    self.finish(throwing: CampusWebAuthenticationError.interactionRequired)
                }
            }
        })
    }

    private func prefillCampusCardLogin(_ credentials: LoginCredentials) {
        guard !attemptedAutomation else { return }
        attemptedAutomation = true
        let script = #"""
        const usernameField = document.querySelector('#username');
        const passwordField = document.querySelector('#pwd');
        if (!usernameField || !passwordField) return false;
        usernameField.value = username;
        passwordField.value = password;
        usernameField.dispatchEvent(new Event('input', {bubbles: true}));
        passwordField.dispatchEvent(new Event('input', {bubbles: true}));
        return true;
        """#
        webView.callAsyncJavaScript(
            script,
            arguments: [
                "username": credentials.studentID,
                "password": credentials.password
            ],
            in: nil,
            in: .page,
            completionHandler: nil
        )
        pendingCredentials = credentials
    }

    private func finishSuccessfully() async {
        let values = await withCheckedContinuation { continuation in
            webView.configuration.websiteDataStore.httpCookieStore.getAllCookies {
                continuation.resume(returning: $0)
            }
        }
        let cookies = CampusWebCookiePolicy.cookies(from: values, scope: mode.scope)
        guard !cookies.isEmpty else {
            finish(throwing: CampusWebAuthenticationError.invalidResponse)
            return
        }
        if mode.scope == .academic, pendingCredentials == nil {
            finish(throwing: CampusWebAuthenticationError.credentialsUnavailable)
            return
        }
        finish(returning: CampusWebAuthenticationResult(
            credentials: pendingCredentials,
            cookies: cookies
        ))
    }

    private func handleNavigationFailure(_ error: Error) {
        if (error as NSError).code == NSURLErrorCancelled { return }
        finish(throwing: CampusWebAuthenticationError.navigationFailed)
    }

    private func finish(returning result: CampusWebAuthenticationResult) {
        guard !completed else { return }
        completed = true
        timeoutTask?.cancel()
        timeoutTask = nil
        webView.stopLoading()
        continuation?.resume(returning: result)
        continuation = nil
        tearDown()
    }

    private func finish(throwing error: Error) {
        guard !completed else { return }
        completed = true
        timeoutTask?.cancel()
        timeoutTask = nil
        webView.stopLoading()
        errorMessage = error.localizedDescription
        continuation?.resume(throwing: error)
        continuation = nil
        tearDown()
    }

    private func tearDown() {
        webView.navigationDelegate = nil
        webView.uiDelegate = nil
        webView.configuration.userContentController.removeScriptMessageHandler(forName: Self.captureHandler)
        webView.configuration.userContentController.removeAllUserScripts()
    }
}

@MainActor
final class CampusWebAuthenticationService: CampusWebAuthenticating {
    static let shared = CampusWebAuthenticationService()

    func refreshAcademic(credentials: LoginCredentials) async throws -> CampusWebAuthenticationResult {
        guard UIApplication.shared.applicationState == .active else {
            throw CampusWebAuthenticationError.inactive
        }
        let engine = CampusWebLoginEngine(mode: .hiddenAcademic(credentials))
        guard let window = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .flatMap(\.windows)
            .first(where: \.isKeyWindow) else {
            throw CampusWebAuthenticationError.inactive
        }
        let host = UIView(frame: CGRect(x: -2, y: -2, width: 1, height: 1))
        host.alpha = 0.01
        host.isUserInteractionEnabled = false
        host.accessibilityElementsHidden = true
        engine.webView.accessibilityElementsHidden = true
        engine.webView.frame = host.bounds
        host.addSubview(engine.webView)
        window.addSubview(host)
        defer { host.removeFromSuperview() }
        return try await engine.start()
    }
}

struct CampusWebViewContainer: UIViewRepresentable {
    @ObservedObject var engine: CampusWebLoginEngine

    func makeUIView(context: Context) -> WKWebView {
        engine.webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {}
}

struct CampusWebLoginScreen: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var engine: CampusWebLoginEngine
    let title: String
    let onCompletion: @MainActor (Result<CampusWebAuthenticationResult, Error>) -> Void

    init(
        mode: CampusWebLoginEngine.Mode,
        title: String,
        onCompletion: @escaping @MainActor (Result<CampusWebAuthenticationResult, Error>) -> Void
    ) {
        _engine = StateObject(wrappedValue: CampusWebLoginEngine(mode: mode))
        self.title = title
        self.onCompletion = onCompletion
    }

    var body: some View {
        NavigationStack {
            ZStack {
                CampusWebViewContainer(engine: engine)
                if engine.progress < 1 {
                    ProgressView(value: engine.progress)
                        .frame(maxWidth: 180)
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        engine.cancel()
                        dismiss()
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                if let message = engine.errorMessage {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(AndroidParityPalette.error)
                        .padding(12)
                        .frame(maxWidth: .infinity)
                        .background(.regularMaterial)
                }
            }
        }
        .task {
            do {
                let result = try await engine.start()
                onCompletion(.success(result))
                dismiss()
            } catch {
                if error as? CampusWebAuthenticationError == .cancelled {
                    onCompletion(.failure(error))
                    dismiss()
                } else {
                    onCompletion(.failure(error))
                }
            }
        }
        .accessibilityIdentifier("login.webview")
    }
}
