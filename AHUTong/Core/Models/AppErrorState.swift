import Foundation

struct AppErrorState: Error, Equatable, Sendable {
    let title: String
    let message: String

    init(title: String = "加载失败", message: String) {
        self.title = title
        self.message = message
    }
}
