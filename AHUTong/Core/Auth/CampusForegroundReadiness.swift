import UIKit

@MainActor
enum CampusForegroundReadiness {
    /// Shortcut launches can reach the model before the scene has a key window.
    /// Wait briefly for that transition; never keep a background login alive.
    static func wait(
        attempts: Int = 30,
        isReady: @MainActor () -> Bool = {
            UIApplication.shared.applicationState == .active
                && UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
                    .flatMap(\.windows).contains(where: \.isKeyWindow)
        },
        pause: () async throws -> Void = { try await Task.sleep(for: .milliseconds(100)) }
    ) async throws -> Bool {
        for _ in 0..<attempts {
            try Task.checkCancellation()
            if isReady() { return true }
            try await pause()
        }
        try Task.checkCancellation()
        return isReady()
    }
}
