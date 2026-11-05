import Foundation

/// App-wide equivalent of Android's TokenAuthenticator mutex. Every campus
/// client awaits the same refresh task instead of starting competing logins.
actor SessionRefreshCoordinator {
    static let shared = SessionRefreshCoordinator()

    private struct ActiveRefresh {
        let id: UUID
        let task: Task<Void, Error>
    }

    private var activeRefreshes: [CampusSessionScope: ActiveRefresh] = [:]
    private var revisions: [CampusSessionScope: Int] = [:]

    func revision(scope: CampusSessionScope = .academic) -> Int {
        revisions[scope, default: 0]
    }

    func refresh(
        scope: CampusSessionScope = .academic,
        observedRevision: Int? = nil,
        operation: @escaping @Sendable () async throws -> Void
    ) async throws {
        if let observedRevision, observedRevision != revision(scope: scope) { return }
        if let activeRefresh = activeRefreshes[scope] {
            return try await activeRefresh.task.value
        }

        let id = UUID()
        let task = Task { try await operation() }
        activeRefreshes[scope] = ActiveRefresh(id: id, task: task)

        do {
            try await task.value
            revisions[scope, default: 0] += 1
            clearRefresh(id: id, scope: scope)
        } catch {
            clearRefresh(id: id, scope: scope)
            AppDiagnostics.shared.report(.sessionRefreshFailed, stage: .refresh, error: error, scope: scope)
            throw error
        }
    }

    private func clearRefresh(id: UUID, scope: CampusSessionScope) {
        guard activeRefreshes[scope]?.id == id else { return }
        activeRefreshes[scope] = nil
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
