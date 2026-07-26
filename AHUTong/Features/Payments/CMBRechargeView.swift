import Foundation
import SwiftUI
import UIKit
import WebKit

enum CMBRechargeCredentialPersistence: Equatable, Sendable {
    case memoryOnly
}

enum CMBRechargeURLBuilderError: LocalizedError, Equatable {
    case missingAccessToken
    case invalidEntryURL

    var errorDescription: String? {
        switch self {
        case .missingAccessToken:
            "校园卡登录凭证暂未就绪，请稍后重试"
        case .invalidEntryURL:
            "招商银行充值入口暂不可用"
        }
    }
}

enum CMBRechargeNavigationDecision: Equatable {
    case allow
    case openExternal(URL)
    case block
}

enum CMBRechargeSecurityPolicy {
    static let credentialPersistence: CMBRechargeCredentialPersistence = .memoryOnly

    private static let allowedExternalHTTPSHosts: Set<String> = ["pay.cmbchina.com"]
    private static let allowedExternalAppDestinations: [String: Set<String>] = [
        "cmbmobilebank": ["pay"]
    ]

    static func makeEntryURL(accessToken: String) throws -> URL {
        let token = accessToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else {
            throw CMBRechargeURLBuilderError.missingAccessToken
        }

        var components = URLComponents()
        components.scheme = "https"
        components.host = "ycard.ahu.edu.cn"
        components.path = "/berserker-base/redirect"
        components.queryItems = [
            URLQueryItem(name: "appId", value: "253"),
            URLQueryItem(name: "loginFrom", value: "h5"),
            URLQueryItem(name: "synAccessSource", value: "h5"),
            URLQueryItem(name: "synjones-auth", value: token),
            URLQueryItem(name: "type", value: "app")
        ]
        guard let url = components.url else {
            throw CMBRechargeURLBuilderError.invalidEntryURL
        }
        return url
    }

    static func isAllowedSchoolURL(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "https",
              let host = url.host?.lowercased() else {
            return false
        }
        return host == "ahu.edu.cn" || host.hasSuffix(".ahu.edu.cn")
    }

    static func navigationDecision(for url: URL) -> CMBRechargeNavigationDecision {
        if isAllowedSchoolURL(url) { return .allow }
        guard isApprovedExternalDestination(url),
              !containsCampusCredential(url) else { return .block }
        return .openExternal(url)
    }

    private static func isApprovedExternalDestination(_ url: URL) -> Bool {
        let scheme = url.scheme?.lowercased() ?? ""
        let host = url.host?.lowercased() ?? ""
        if scheme == "https" {
            return allowedExternalHTTPSHosts.contains(host)
        }
        guard let hosts = allowedExternalAppDestinations[scheme] else {
            return false
        }
        return hosts.contains(host)
    }

    private static func containsCampusCredential(_ url: URL) -> Bool {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return true
        }
        if components.user != nil || components.password != nil {
            return true
        }
        if components.queryItems?.contains(where: {
            $0.name.caseInsensitiveCompare("synjones-auth") == .orderedSame
        }) == true {
            return true
        }
        let encodedFragment = components.percentEncodedFragment ?? ""
        let decodedFragment = (encodedFragment.removingPercentEncoding ?? encodedFragment)
            .lowercased()
        return decodedFragment.contains("synjones-auth")
    }
}

enum CMBRechargeWebStyle {
    static let script = #"""
    (function(){
      var styleId = 'ahutong-cmb-style';
      if (document.getElementById(styleId)) return;
      var style = document.createElement('style');
      style.id = styleId;
      style.textContent = [
        'html,body,#app,#app-box{background:#eef2f5 !important;color:#1f2328 !important;font-family:-apple-system,BlinkMacSystemFont,"Segoe UI","PingFang SC","Hiragino Sans GB","Microsoft YaHei",sans-serif !important;}',
        'body{overscroll-behavior:none !important;-webkit-font-smoothing:antialiased !important;}',
        '#app,#app-box,.page,.container,.main,.weui-tab__panel{max-width:720px;margin:0 auto !important;}',
        '.weui-btn_primary,.weui-btn_warn,.weui-btn_default{border-radius:16px !important;box-shadow:none !important;}',
        '.weui-btn_primary{background:#1e88e5 !important;border-color:#1e88e5 !important;}',
        '.weui-btn_warn{background:#d94f4f !important;border-color:#d94f4f !important;}',
        '.weui-btn_default{background:#ffffff !important;color:#1f2328 !important;border-color:#d0d7de !important;}',
        '.weui-cells,.weui-panel,.card,.panel{border-radius:20px !important;overflow:hidden !important;background:#ffffff !important;}',
        '.weui-cell{padding-top:14px !important;padding-bottom:14px !important;}',
        '.van-cell,.van-field,.cell,.form-item,.pay-item{border-radius:16px !important;background:#ffffff !important;}',
        '.van-button,.el-button,button{border-radius:16px !important;box-shadow:none !important;}',
        '.van-button--primary,.el-button--primary,button[type=submit]{background:#1e88e5 !important;border-color:#1e88e5 !important;color:#ffffff !important;}',
        '.van-field__label,.label,.title{color:#1f2328 !important;}',
        '.van-field__control,input,textarea,select{color:#1f2328 !important;}',
        '.van-cell-group,.form,.charge-box,.cashier-box{border-radius:20px !important;overflow:hidden !important;background:#ffffff !important;}',
        'input,textarea,select{font-family:inherit !important;}',
        'a{color:#1e88e5 !important;}'
      ].join('');
      document.head.appendChild(style);
    })();
    """#

    static func shouldInject(for url: URL) -> Bool {
        guard CMBRechargeSecurityPolicy.isAllowedSchoolURL(url) else { return false }
        return url.path.contains("/cashier-mobile/charge")
            || url.path.contains("/charge-app")
    }
}

enum CampusCookieWebBridge {
    static func httpCookies(_ cookies: [CampusCookie]) -> [HTTPCookie] {
        cookies.filter(isTrustedSchoolCookie).compactMap { cookie in
            var properties: [HTTPCookiePropertyKey: Any] = [
                .name: cookie.name,
                .value: cookie.value,
                .domain: cookie.domain,
                .path: cookie.path.flatMap { $0.isEmpty ? nil : $0 } ?? "/"
            ]
            if cookie.secure == true {
                properties[.secure] = "TRUE"
            }
            if cookie.httpOnly == true {
                properties[HTTPCookiePropertyKey(rawValue: "HttpOnly")] = "TRUE"
            }
            return HTTPCookie(properties: properties)
        }
    }

    static func isTrustedSchoolCookie(_ cookie: CampusCookie) -> Bool {
        let domain = cookie.domain
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "."))
            .lowercased()
        return domain == "ahu.edu.cn" || domain.hasSuffix(".ahu.edu.cn")
    }
}

@MainActor
enum CMBRechargeWebConfigurationFactory {
    static let credentialPersistence = CMBRechargeSecurityPolicy.credentialPersistence

    static func make() -> WKWebViewConfiguration {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = true
        configuration.applicationNameForUserAgent = "AHUTong/iOS"
        return configuration
    }
}

@MainActor
private final class CMBRechargeSessionModel: ObservableObject {
    struct Bootstrap: Sendable {
        let accessToken: String
        let cookies: [CampusCookie]
    }

    enum Phase: Equatable {
        case preparing
        case ready(URL, cookies: [CampusCookie], requestID: Int)
        case failed(String)
    }

    @Published private(set) var phase: Phase = .preparing

    private let bootstrapProvider: @Sendable () async throws -> Bootstrap
    private var generation = 0

    init(bootstrapProvider: @escaping @Sendable () async throws -> Bootstrap) {
        self.bootstrapProvider = bootstrapProvider
    }

    func prepare() async {
        generation += 1
        let currentGeneration = generation
        phase = .preparing

        do {
            let bootstrap = try await bootstrapProvider()
            try Task.checkCancellation()
            guard currentGeneration == generation else { return }
            let entryURL = try CMBRechargeSecurityPolicy.makeEntryURL(
                accessToken: bootstrap.accessToken
            )
            phase = .ready(
                entryURL,
                cookies: bootstrap.cookies,
                requestID: currentGeneration
            )
        } catch is CancellationError {
            return
        } catch let error as CMBRechargeURLBuilderError {
            phase = .failed(error.localizedDescription)
        } catch let error as CampusCoreError where error == .unauthorized {
            phase = .failed("校园卡登录状态已失效，请重新登录后重试")
        } catch {
            // Never expose or log the token provider's raw error because an
            // upstream request error can contain a credential-bearing URL.
            phase = .failed("校园卡登录凭证暂未就绪，请稍后重试")
        }
    }

    func clear() {
        generation += 1
        phase = .preparing
    }
}

@MainActor
private final class CMBRechargeWebState: ObservableObject {
    @Published var progress = 0.0
    @Published var isLoading = true
    @Published var errorMessage: String?
    @Published var pendingExternalURL: URL?

    weak var webView: WKWebView?

    func attach(_ webView: WKWebView) {
        self.webView = webView
    }

    func resetForLoad() {
        progress = 0
        isLoading = true
        errorMessage = nil
        pendingExternalURL = nil
    }

    func clear() {
        webView?.stopLoading()
        webView = nil
        resetForLoad()
    }
}

struct CMBRechargeView: View {
    @StateObject private var session: CMBRechargeSessionModel
    @StateObject private var webState = CMBRechargeWebState()

    init(appModel: AppModel) {
        let campusAPI = appModel.campusAPI
        _session = StateObject(wrappedValue: CMBRechargeSessionModel {
            let accessToken = try await campusAPI.cardAccessToken()
            let rawCookies = (try? await campusAPI.cookiesFlat()) ?? "[]"
            let cookies = (try? JSONDecoder().decode(
                [CampusCookie].self,
                from: Data(rawCookies.utf8)
            )) ?? []
            return CMBRechargeSessionModel.Bootstrap(
                accessToken: accessToken,
                cookies: cookies
            )
        })
    }

    var body: some View {
        AndroidScreen {
            VStack(spacing: 0) {
                AndroidHeader(title: "招商银行充值", large: true)
                    .accessibilityIdentifier("payment.cmb.screen")

                if webState.progress > 0, webState.progress < 1 {
                    ProgressView(value: webState.progress)
                        .progressViewStyle(.linear)
                        .padding(.horizontal, 16)
                        .accessibilityLabel("网页加载进度")
                        .accessibilityValue("\(Int(webState.progress * 100))%")
                }

                content
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
            }
        }
        .task {
            await session.prepare()
        }
        .onDisappear {
            // The entry URL contains a short-lived credential. Discard both
            // the model reference and the non-persistent web view on exit.
            session.clear()
            webState.clear()
        }
        .alert(
            "即将离开学校充值页面",
            isPresented: Binding(
                get: { webState.pendingExternalURL != nil },
                set: { if !$0 { webState.pendingExternalURL = nil } }
            )
        ) {
            Button("取消", role: .cancel) {
                webState.pendingExternalURL = nil
            }
            Button("继续") {
                guard let url = webState.pendingExternalURL else { return }
                webState.pendingExternalURL = nil
                UIApplication.shared.open(url)
            }
        } message: {
            Text("将使用系统打开经白名单验证的招商银行页面；学校登录 Token 不会随链接带出。")
        }
    }

    @ViewBuilder
    private var content: some View {
        switch session.phase {
        case .preparing:
            statusCard {
                ProgressView()
                Text("正在获取校园卡登录凭证…")
                    .foregroundStyle(.secondary)
            }

        case let .failed(message):
            errorCard(message)

        case let .ready(entryURL, cookies, requestID):
            ZStack {
                CMBRechargeWebViewRepresentable(
                    entryURL: entryURL,
                    cookies: cookies,
                    requestID: requestID,
                    state: webState
                )

                if webState.isLoading, webState.progress == 0 {
                    ProgressView()
                        .controlSize(.large)
                        .accessibilityLabel("正在加载招商银行充值页面")
                }

                if let errorMessage = webState.errorMessage {
                    errorCard(errorMessage)
                }
            }
            .background(.background)
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .accessibilityIdentifier("payment.cmb.web-view")
        }
    }

    private func statusCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        AndroidCard(radius: 24) {
            VStack(spacing: 16, content: content)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(24)
        }
    }

    private func errorCard(_ message: String) -> some View {
        AndroidCard(radius: 24) {
            VStack(alignment: .leading, spacing: 16) {
                Label("页面加载失败", systemImage: "exclamationmark.triangle")
                    .font(.headline)
                Text(message)
                    .foregroundStyle(.secondary)
                Button("重试") {
                    webState.resetForLoad()
                    Task { await session.prepare() }
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("payment.cmb.retry")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
        }
    }
}

@MainActor
private struct CMBRechargeWebViewRepresentable: UIViewRepresentable {
    let entryURL: URL
    let cookies: [CampusCookie]
    let requestID: Int
    @ObservedObject var state: CMBRechargeWebState

    func makeCoordinator() -> Coordinator {
        Coordinator(state: state)
    }

    func makeUIView(context: Context) -> WKWebView {
        let webView = WKWebView(
            frame: .zero,
            configuration: CMBRechargeWebConfigurationFactory.make()
        )
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        webView.allowsBackForwardNavigationGestures = true
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        context.coordinator.observeProgress(of: webView)
        state.attach(webView)
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        state.attach(webView)
        context.coordinator.load(
            entryURL: entryURL,
            cookies: cookies,
            requestID: requestID,
            in: webView
        )
    }

    static func dismantleUIView(_ webView: WKWebView, coordinator: Coordinator) {
        webView.stopLoading()
        webView.navigationDelegate = nil
        webView.uiDelegate = nil
        webView.configuration.userContentController.removeAllUserScripts()
        coordinator.stopObserving()
        coordinator.detach()
    }

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        private weak var state: CMBRechargeWebState?
        private var progressObservation: NSKeyValueObservation?
        private var loadedRequestID: Int?

        init(state: CMBRechargeWebState) {
            self.state = state
        }

        func observeProgress(of webView: WKWebView) {
            progressObservation = webView.observe(
                \.estimatedProgress,
                options: [.initial, .new]
            ) { [weak self] _, change in
                let progress = change.newValue ?? 0
                Task { @MainActor [weak self] in
                    self?.state?.progress = progress
                }
            }
        }

        func stopObserving() {
            progressObservation?.invalidate()
            progressObservation = nil
        }

        func detach() {
            state?.clear()
            state = nil
        }

        func load(
            entryURL: URL,
            cookies: [CampusCookie],
            requestID: Int,
            in webView: WKWebView
        ) {
            guard loadedRequestID != requestID else { return }
            loadedRequestID = requestID
            state?.resetForLoad()
            var request = URLRequest(
                url: entryURL,
                cachePolicy: .reloadIgnoringLocalAndRemoteCacheData,
                timeoutInterval: 30
            )
            request.setValue("no-store", forHTTPHeaderField: "Cache-Control")
            let loadRequest = request
            let cookieStore = webView.configuration.websiteDataStore.httpCookieStore
            let bridgedCookies = CampusCookieWebBridge.httpCookies(cookies)
            Task { @MainActor [weak self, weak webView] in
                for cookie in bridgedCookies {
                    await withCheckedContinuation { continuation in
                        cookieStore.setCookie(cookie) {
                            continuation.resume()
                        }
                    }
                }
                guard let self,
                      let webView,
                      self.loadedRequestID == requestID else { return }
                webView.load(loadRequest)
            }
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction
        ) async -> WKNavigationActionPolicy {
            guard let url = navigationAction.request.url else {
                return .cancel
            }

            switch CMBRechargeSecurityPolicy.navigationDecision(for: url) {
            case .allow:
                if navigationAction.targetFrame == nil {
                    webView.load(navigationAction.request)
                    return .cancel
                }
                return .allow
            case let .openExternal(externalURL):
                state?.pendingExternalURL = externalURL
                return .cancel
            case .block:
                state?.isLoading = false
                state?.errorMessage = "已阻止打开未经验证的外部支付链接"
                return .cancel
            }
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationResponse: WKNavigationResponse
        ) async -> WKNavigationResponsePolicy {
            guard let url = navigationResponse.response.url,
                  CMBRechargeSecurityPolicy.isAllowedSchoolURL(url) else {
                state?.isLoading = false
                state?.errorMessage = "已阻止非学校页面返回的内容"
                return .cancel
            }

            if let response = navigationResponse.response as? HTTPURLResponse,
               !(200..<400).contains(response.statusCode) {
                state?.isLoading = false
                state?.errorMessage = "学校充值页面暂不可用，请稍后重试"
                return .cancel
            }
            return .allow
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation?) {
            state?.isLoading = true
            state?.errorMessage = nil
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation?) {
            state?.progress = 1
            state?.isLoading = false
            if let url = webView.url,
               CMBRechargeWebStyle.shouldInject(for: url) {
                webView.evaluateJavaScript(
                    CMBRechargeWebStyle.script,
                    completionHandler: nil
                )
            }
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

        private func handleNavigationFailure(_ error: Error) {
            if (error as NSError).code == NSURLErrorCancelled { return }
            state?.isLoading = false
            state?.errorMessage = "学校充值页面加载失败，请检查网络后重试"
        }
    }
}
