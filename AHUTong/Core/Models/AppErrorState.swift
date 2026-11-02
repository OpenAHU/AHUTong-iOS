import Foundation

struct AppErrorState: Error, Equatable, Sendable {
    let title: String
    let message: String

    init(error: Error, route: String) {
        self.init(message: error.localizedDescription)
        AppDiagnostics.shared.reportUnexpected(error, route: route)
    }

    init(title: String = "加载失败", message: String) {
        self.title = title
        self.message = message
    }
}
