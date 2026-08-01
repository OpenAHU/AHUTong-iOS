import Foundation
import SwiftUI
import UIKit
import WebKit

enum CMBRechargeCredentialPersistence: Equatable, Sendable {
    case memoryOnly
}

enum CMBRechargeMode: Equatable, Sendable {
    case live
    case noDebitAcceptance
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

enum CMBRechargeBootstrapError: LocalizedError, Equatable {
    case invalidCookies

    var errorDescription: String? {
        "校园卡 Cookie 读取失败，请刷新登录状态后重试"
    }
}

enum CMBRechargeNavigationDecision: Equatable {
    case allow
    case openExternal(URL)
    case block
}

enum CMBRechargeSecurityPolicy {
    static let credentialPersistence: CMBRechargeCredentialPersistence = .memoryOnly

    private static let allowedInternalHTTPSHosts: Set<String> = [
        "ycard.ahu.edu.cn",
        "epay92.ahu.edu.cn"
    ]
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
              let host = url.host?.lowercased(),
              url.user == nil,
              url.password == nil,
              url.port == nil || url.port == 443 else {
            return false
        }
        return allowedInternalHTTPSHosts.contains(host)
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
            return (url.port == nil || url.port == 443)
                && allowedExternalHTTPSHosts.contains(host)
        }
        guard let hosts = allowedExternalAppDestinations[scheme] else {
            return false
        }
        return hosts.contains(host)
    }

    private static func containsCampusCredential(_ url: URL) -> Bool {
        if containsEncodedCampusCredential(url.absoluteString) {
            return true
        }
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return true
        }
        if components.user != nil || components.password != nil {
            return true
        }
        for item in components.queryItems ?? [] {
            let normalizedName = item.name.lowercased()
            if normalizedName == "synjones-auth"
                || normalizedName == "synjones_auth"
                || normalizedName == "ticket" {
                return true
            }
            if containsEncodedCampusCredential(item.value ?? "") {
                return true
            }
        }
        return containsEncodedCampusCredential(components.percentEncodedFragment ?? "")
    }

    private static func containsEncodedCampusCredential(_ rawValue: String) -> Bool {
        guard rawValue.utf8.count <= 8_192 else { return true }
        var candidate = rawValue
        for _ in 0..<16 {
            let normalized = candidate.lowercased()
            if normalized.contains("synjones-auth")
                || normalized.contains("synjones_auth")
                || normalized.contains("ticket=") {
                return true
            }
            guard let decoded = candidate.removingPercentEncoding,
                  decoded != candidate else {
                return false
            }
            candidate = decoded
        }
        // Deeply nested escaping is not required by the approved bank
        // handoff. If it still changes after the bounded scan, fail closed
        // instead of letting another application decode hidden credentials.
        return true
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
        return url.path == "/cashier-mobile/charge"
            || url.path.hasPrefix("/cashier-mobile/charge/")
            || url.path == "/charge-app"
            || url.path.hasPrefix("/charge-app/")
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
        } catch let error as CMBRechargeBootstrapError {
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
    @StateObject private var acceptance: CMBRechargeAcceptanceModel
    @State private var showsAcceptanceReport = false

    private let mode: CMBRechargeMode

    init(
        appModel: AppModel,
        mode: CMBRechargeMode = .live
    ) {
        self.mode = mode
        _acceptance = StateObject(
            wrappedValue: CMBRechargeAcceptanceModel(
                service: CMBRechargeAcceptanceServiceFactory.make()
            )
        )
        let campusAPI = appModel.campusAPI
        _session = StateObject(wrappedValue: CMBRechargeSessionModel {
            let accessToken = try await campusAPI.cardAccessToken()
            let rawCookies: String
            do {
                rawCookies = try await campusAPI.cookiesFlat()
            } catch {
                throw CMBRechargeBootstrapError.invalidCookies
            }
            guard let cookies = try? JSONDecoder().decode(
                [CampusCookie].self,
                from: Data(rawCookies.utf8)
            ) else {
                throw CMBRechargeBootstrapError.invalidCookies
            }
            return CMBRechargeSessionModel.Bootstrap(
                accessToken: accessToken,
                cookies: cookies
            )
        })
    }

    var body: some View {
        AndroidScreen {
            VStack(spacing: 0) {
                AndroidHeader(
                    title: mode == .noDebitAcceptance
                        ? "PAY-04 无扣款探测"
                        : "招商银行充值",
                    large: true
                )
                    .accessibilityIdentifier("payment.cmb.screen")

                if mode == .noDebitAcceptance {
                    acceptanceBanner
                }

                if mode == .live,
                   webState.progress > 0,
                   webState.progress < 1 {
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
            if mode == .noDebitAcceptance {
                acceptance.reset()
            }
            await session.prepare()
        }
        .onChange(of: session.phase) { _, phase in
            guard mode == .noDebitAcceptance else { return }
            switch phase {
            case .ready, .preparing:
                break
            case .failed:
                acceptance.recordBootstrapFailure()
            }
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
        .sheet(isPresented: $showsAcceptanceReport) {
            CMBRechargeAcceptanceReportView(snapshot: acceptance.snapshot)
                .presentationDetents([.medium, .large])
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
            if mode == .noDebitAcceptance {
                acceptanceProbeCard(
                    entryURL: entryURL,
                    cookies: cookies,
                    requestID: requestID
                )
            } else {
                ZStack {
                    CMBRechargeWebViewRepresentable(
                        entryURL: entryURL,
                        cookies: cookies,
                        requestID: requestID,
                        state: webState,
                        onSessionExpired: {
                            Task { await session.prepare() }
                        }
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
    }

    private func acceptanceProbeCard(
        entryURL: URL,
        cookies: [CampusCookie],
        requestID: Int
    ) -> some View {
        statusCard {
            Image(systemName: "network.badge.shield.half.filled")
                .font(.system(size: 34))
                .foregroundStyle(acceptanceTint)
            Text("原生 HEAD 扣款前探测")
                .font(.headline)
            Text(
                "不创建 WebView，不执行 JavaScript，不加载图片或脚本，"
                    + "不发送请求体，也不自动跟随跳转。"
            )
            .font(.subheadline)
            .multilineTextAlignment(.center)
            .foregroundStyle(.secondary)
            if acceptance.snapshot.completion == .running {
                ProgressView()
                    .accessibilityLabel("正在执行扣款前 HEAD 探测")
            } else if acceptance.snapshot.completion == .failed {
                Button("重新探测") {
                    Task {
                        await acceptance.run(
                            entryURL: entryURL,
                            cookies: cookies
                        )
                    }
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("operations.cmb-acceptance.retry")
            }
        }
        .accessibilityIdentifier("operations.cmb-acceptance.probe")
        .task(id: requestID) {
            await acceptance.run(entryURL: entryURL, cookies: cookies)
        }
    }

    private var acceptanceBanner: some View {
        AndroidCard(radius: 16) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Image(systemName: acceptanceIcon)
                        .foregroundStyle(acceptanceTint)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(acceptance.snapshot.completion.title)
                            .font(.headline)
                            .accessibilityIdentifier("operations.cmb-acceptance.status")
                        Text("原生 HEAD 探测；不创建 WebView、不执行网页脚本、不发送请求体")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 8)
                }
                Button("查看并分享脱敏验收明细") {
                    showsAcceptanceReport = true
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("operations.cmb-acceptance.report")
            }
            .padding(14)
        }
        .padding(.horizontal, 16)
    }

    private var acceptanceIcon: String {
        switch acceptance.snapshot.completion {
        case .running: "hourglass"
        case .physicalDevicePassed, .simulatorPreviewPassed: "checkmark.shield.fill"
        case .failed: "xmark.shield.fill"
        }
    }

    private var acceptanceTint: Color {
        switch acceptance.snapshot.completion {
        case .running: .orange
        case .physicalDevicePassed, .simulatorPreviewPassed: .green
        case .failed: .red
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
                Label(
                    mode == .noDebitAcceptance ? "探测准备失败" : "页面加载失败",
                    systemImage: "exclamationmark.triangle"
                )
                    .font(.headline)
                Text(message)
                    .foregroundStyle(.secondary)
                Button("重试") {
                    webState.resetForLoad()
                    if mode == .noDebitAcceptance {
                        acceptance.reset()
                    }
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

private struct CMBRechargeAcceptanceReportView: View {
    let snapshot: CMBRechargeAcceptanceSnapshot

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text(snapshot.completion.title)
                        .font(.headline)
                    Text("此验收只用原生 HEAD 请求检查登录凭证、内存 Cookie 与校方扣款前路由；不会创建 WebView、执行网页脚本、发送请求体或打开招商银行。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("检查项") {
                    ForEach(snapshot.checks) { check in
                        HStack(alignment: .top, spacing: 12) {
                            Text(check.outcome.symbol)
                                .font(.headline)
                                .foregroundStyle(color(for: check.outcome))
                                .accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(check.id.title)
                                Text(check.detail)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityIdentifier(
                            "operations.cmb-acceptance.check.\(check.id.rawValue)"
                        )
                    }
                }

                Section {
                    ShareLink(item: snapshot.exportText) {
                        Label("分享脱敏验收结果", systemImage: "square.and.arrow.up")
                    }
                    .accessibilityIdentifier("operations.cmb-acceptance.share")
                } footer: {
                    Text("报告不会包含账号、Token、Cookie 值、金额、订单号或完整查询参数。")
                }
            }
            .navigationTitle("验收明细")
            .navigationBarTitleDisplayMode(.inline)
            .accessibilityIdentifier("operations.cmb-acceptance.report-screen")
        }
    }

    private func color(for outcome: CMBRechargeAcceptanceOutcome) -> Color {
        switch outcome {
        case .pending: .secondary
        case .passed: .green
        case .warning: .orange
        case .failed: .red
        }
    }
}

@MainActor
private struct CMBRechargeWebViewRepresentable: UIViewRepresentable {
    let entryURL: URL
    let cookies: [CampusCookie]
    let requestID: Int
    @ObservedObject var state: CMBRechargeWebState
    let onSessionExpired: @MainActor () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(state: state, onSessionExpired: onSessionExpired)
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
        private var automaticSessionRefreshes = 0
        private let onSessionExpired: @MainActor () -> Void

        init(
            state: CMBRechargeWebState,
            onSessionExpired: @escaping @MainActor () -> Void
        ) {
            self.state = state
            self.onSessionExpired = onSessionExpired
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

            if CampusSessionExpiryDetector.isExpiredURL(url) {
                handleSessionExpiration(in: webView)
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
            guard let url = navigationResponse.response.url else {
                return .cancel
            }

            if let response = navigationResponse.response as? HTTPURLResponse,
               CampusSessionExpiryDetector.isExpired(
                   response: response,
                   data: Data()
               ) {
                handleSessionExpiration(in: webView)
                return .cancel
            }

            guard CMBRechargeSecurityPolicy.isAllowedSchoolURL(url) else {
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
            if let url = webView.url {
                guard CMBRechargeWebStyle.shouldInject(for: url) else { return }
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

        private func handleSessionExpiration(in webView: WKWebView) {
            webView.stopLoading()
            guard automaticSessionRefreshes == 0 else {
                state?.isLoading = false
                state?.errorMessage = "校园卡登录状态仍然无效，请手动重试"
                return
            }
            automaticSessionRefreshes += 1
            state?.isLoading = true
            onSessionExpired()
        }
    }
}
