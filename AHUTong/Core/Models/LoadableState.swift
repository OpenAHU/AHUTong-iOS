import Foundation

enum LoadableState<Value: Sendable>: Sendable {
    case idle
    case loading
    case loaded(Value)
    case empty
    case failed(AppErrorState)

    var isLoading: Bool {
        if case .loading = self {
            true
        } else {
            false
        }
    }

    var value: Value? {
        if case let .loaded(value) = self {
            value
        } else {
            nil
        }
    }
}

extension LoadableState: Equatable where Value: Equatable {}

enum DemoDataState: String {
    case normal
    case loading
    case empty
    case error

    static var current: Self {
        let prefix = "--demo-state="
        let value = ProcessInfo.processInfo.arguments
            .first(where: { $0.hasPrefix(prefix) })
            .map { String($0.dropFirst(prefix.count)) }
        return value.flatMap(Self.init(rawValue:)) ?? .normal
    }

    static let referenceDate = Date(timeIntervalSince1970: 1_784_023_200) // 2026-07-14 10:00:00 UTC
}
