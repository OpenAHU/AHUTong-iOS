import SwiftUI

struct LoadableContentView<Value: Sendable, Content: View>: View {
    let state: LoadableState<Value>
    let retry: (() -> Void)?
    let content: (Value) -> Content

    init(
        state: LoadableState<Value>,
        retry: (() -> Void)? = nil,
        @ViewBuilder content: @escaping (Value) -> Content
    ) {
        self.state = state
        self.retry = retry
        self.content = content
    }

    var body: some View {
        switch state {
        case .idle:
            Color.clear
                .accessibilityHidden(true)
        case .loading:
            ProgressView("正在加载")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityIdentifier("state.loading")
        case let .loaded(value):
            content(value)
        case .empty:
            ContentUnavailableView(
                "暂无内容",
                systemImage: "tray",
                description: Text("这里还没有可以显示的数据。")
            )
            .accessibilityIdentifier("state.empty")
        case let .failed(error):
            ContentUnavailableView {
                Label(error.title, systemImage: "exclamationmark.triangle")
            } description: {
                Text(error.message)
            } actions: {
                if let retry {
                    Button("重试", action: retry)
                }
            }
            .accessibilityIdentifier("state.failed")
        }
    }
}
