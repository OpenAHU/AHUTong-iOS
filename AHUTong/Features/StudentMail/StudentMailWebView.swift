import SwiftUI
import WebKit

/// Optional official-client fallback for rich HTML, inline/cloud attachments and
/// operations outside the observed native contract. Never shares the campus jar.
struct StudentMailWebView: View {
    let client: StudentMailClient
    @State private var context: StudentMailWebContext?
    @State private var error: String?

    var body: some View {
        Group {
            if let context {
                StudentMailWebContainer(context: context, error: $error)
            } else if let error {
                ContentUnavailableView("暂时无法打开邮箱", systemImage: "envelope.badge",
                    description: Text(error))
            } else { ProgressView("正在打开邮箱…") }
        }
        .navigationTitle("邮箱网页版")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .overlay(alignment: .bottom) {
            if context != nil, let error {
                Text(error).font(.footnote).padding().background(.regularMaterial)
            }
        }
        .task {
            do { context = try await client.webContext() }
            catch { self.error = StudentMailViewModel.message(for: error) }
        }
    }
}

private struct StudentMailWebContainer: UIViewRepresentable {
    let context: StudentMailWebContext
    @Binding var error: String?

    func makeCoordinator() -> Coordinator { Coordinator(error: $error) }

    func makeUIView(context wrapper: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.limitsNavigationsToAppBoundDomains = true
        configuration.ignoresViewportScaleLimits = true
        configuration.defaultWebpagePreferences.preferredContentMode = .mobile
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.navigationDelegate = wrapper.coordinator
        view.allowsBackForwardNavigationGestures = true
        view.accessibilityIdentifier = "mail.web"
        let initial = context
        wrapper.coordinator.loading = Task { @MainActor [weak view] in
            guard let view else { return }
            for stored in initial.cookies {
                let item = stored.cookie
                var properties: [HTTPCookiePropertyKey: Any] = [.name: item.name, .value: item.value,
                    .domain: item.domain, .path: item.path ?? "/", .secure: "TRUE"]
                if let expires = stored.expiresAt { properties[.expires] = expires }
                if let cookie = HTTPCookie(properties: properties) {
                    await view.configuration.websiteDataStore.httpCookieStore.setCookie(cookie)
                }
            }
            guard !Task.isCancelled else { return }
            view.load(URLRequest(url: initial.url, cachePolicy: .reloadIgnoringLocalCacheData))
        }
        return view
    }

    func updateUIView(_ view: WKWebView, context: Context) {}

    static func dismantleUIView(_ view: WKWebView, coordinator: Coordinator) {
        coordinator.loading?.cancel()
        view.stopLoading()
        view.navigationDelegate = nil
    }

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate {
        var loading: Task<Void, Never>?
        private let error: Binding<String?>
        init(error: Binding<String?>) { self.error = error }
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
            guard let url = navigationAction.request.url else { return .cancel }
            if url.absoluteString == "about:blank" { return .allow }
            guard (try? StudentMailRoutes.validate(url, campus: false)) != nil else {
                error.wrappedValue = "此链接不能在邮箱内打开，请返回原生页面重新连接。"
                return .cancel
            }
            return .allow
        }
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError failure: Error) {
            if (failure as? URLError)?.code != .cancelled { error.wrappedValue = "邮箱页面暂时无法加载，请返回后重试。" }
        }
    }
}
