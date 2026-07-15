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
        if let value, let state = Self(rawValue: value) { return state }
        return Self(rawValue: UserDefaults.standard.string(forKey: DebugRuntimeSettings.scenarioKey) ?? "") ?? .normal
    }

    static var referenceDate: Date {
        let stored = UserDefaults.standard.double(forKey: DebugRuntimeSettings.timeKey)
        return stored > 0 ? Date(timeIntervalSince1970: stored) : Date(timeIntervalSince1970: 1_784_023_200)
    }
}

enum AppRuntime {
    static var isDemoSession: Bool {
        ProcessInfo.processInfo.arguments.contains("--demo-session")
            || UserDefaults.standard.bool(forKey: DebugRuntimeSettings.mockEnabledKey)
    }
}

enum DebugRuntimeSettings {
    static let mockEnabledKey = "debug.mock.enabled"
    static let scenarioKey = "debug.mock.scenario"
    static let timeKey = "debug.mock.time"
    static let endpointKeyPrefix = "debug.mock.endpoint."

    static let endpoints = ["schedule", "grade", "exam", "free-classroom", "lost-found", "weather"]

    static func endpointJSON(_ endpoint: String) -> String {
        UserDefaults.standard.string(forKey: endpointKeyPrefix + endpoint) ?? "{}"
    }

    static func setEndpointJSON(_ value: String, endpoint: String) throws {
        let data = Data(value.utf8)
        _ = try JSONSerialization.jsonObject(with: data)
        UserDefaults.standard.set(value, forKey: endpointKeyPrefix + endpoint)
    }

    static func decode<Value: Decodable>(_ endpoint: String, as type: Value.Type = Value.self) -> Value? {
        let value = endpointJSON(endpoint).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, value != "{}" else { return nil }
        return try? JSONDecoder().decode(Value.self, from: Data(value.utf8))
    }

    static func reset() {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: mockEnabledKey)
        defaults.removeObject(forKey: scenarioKey)
        defaults.removeObject(forKey: timeKey)
        endpoints.forEach { defaults.removeObject(forKey: endpointKeyPrefix + $0) }
    }
}
