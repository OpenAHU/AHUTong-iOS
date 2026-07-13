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
