import Foundation

/// App-wide equivalent of Android's TokenAuthenticator mutex. Every campus
/// client awaits the same refresh task instead of starting competing logins.
actor SessionRefreshCoordinator {
    static let shared = SessionRefreshCoordinator()

    private struct ActiveRefresh {
        let id: UUID
        let task: Task<Void, Error>
    }

    private var activeRefresh: ActiveRefresh?

    func refresh(
        operation: @escaping @Sendable () async throws -> Void
    ) async throws {
        if let activeRefresh {
            return try await activeRefresh.task.value
        }

        let id = UUID()
        let task = Task { try await operation() }
        activeRefresh = ActiveRefresh(id: id, task: task)

        do {
            try await task.value
            clearRefresh(id: id)
        } catch {
            clearRefresh(id: id)
            throw error
        }
    }

    private func clearRefresh(id: UUID) {
        guard activeRefresh?.id == id else { return }
        activeRefresh = nil
    }
}

enum CampusRequestRetryPolicy: Equatable, Sendable {
    case safeRead
    case sideEffecting

    static func automatic(forHTTPMethod method: String) -> Self {
        switch method.uppercased() {
        case "GET", "HEAD": .safeRead
        default: .sideEffecting
        }
    }

    var allowsAutomaticRetry: Bool {
        self == .safeRead
    }
}
