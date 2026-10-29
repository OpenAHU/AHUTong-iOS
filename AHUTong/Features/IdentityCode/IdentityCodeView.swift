import SwiftUI

struct IdentityCodeView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var attempted = false
    @State private var failed = false

    private static let page = URL(string: "https://pages-fast.m.taobao.com/wow/z/uniapp/1011717/last-mile-fe/end-collect-platform/identity-code")!
    private static var taobao: URL {
        var url = URLComponents(string: "tbopen://m.taobao.com/tbopen/index.html")!
        url.queryItems = [.init(name: "action", value: "ali.open.nav"), .init(name: "module", value: "h5"),
                          .init(name: "bootImage", value: "0"), .init(name: "h5Url", value: page.absoluteString)]
        return url.url!
    }

    var body: some View {
        Group {
            if failed {
                ContentUnavailableView {
                    Label("无法打开身份码", systemImage: "qrcode")
                } description: { Text("请稍后重试，或在淘宝中打开菜鸟驿站身份码。") }
                actions: { Button("重试") { Task { await open() } }.buttonStyle(.borderedProminent) }
            } else { ProgressView("正在打开身份码…") }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task {
            guard !attempted else { return }
            attempted = true
            await open()
        }
    }

    private func open() async {
        failed = false
        let opened = await UIApplication.shared.open(Self.taobao)
        if opened { dismiss(); return }
        if await UIApplication.shared.open(Self.page) { dismiss() }
        else { failed = true }
    }
}
