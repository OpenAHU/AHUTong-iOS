import XCTest
@testable import AHUTong

final class SessionRefreshCoordinatorTests: XCTestCase {
    func testConcurrentRefreshesShareOneLoginTask() async throws {
        let coordinator = SessionRefreshCoordinator()
        let login = SessionRefreshLoginProbe()

        async let first: Void = coordinator.refresh {
            try await login.perform()
        }
        async let second: Void = coordinator.refresh {
            try await login.perform()
        }
        async let third: Void = coordinator.refresh {
            try await login.perform()
        }
        _ = try await (first, second, third)

        let loginCount = await login.count()
        XCTAssertEqual(loginCount, 1)
    }

    func testFailedRefreshDoesNotCreateAnInfiniteLoop() async {
        let coordinator = SessionRefreshCoordinator()
        let attempts = SessionRefreshAttemptProbe()

        for _ in 0..<2 {
            do {
                try await coordinator.refresh {
                    await attempts.record()
                    throw CampusCoreError.credentialsRejected
                }
                XCTFail("Expected refresh failure")
            } catch {
                XCTAssertEqual(error as? CampusCoreError, .credentialsRejected)
            }
        }

        let attemptCount = await attempts.count()
        XCTAssertEqual(attemptCount, 2)
    }

    func testLateUnauthorizedResponseReusesTheCompletedRefresh() async throws {
        let coordinator = SessionRefreshCoordinator()
        let attempts = SessionRefreshAttemptProbe()
        let revision = await coordinator.revision()

        try await coordinator.refresh(observedRevision: revision) { await attempts.record() }
        try await coordinator.refresh(observedRevision: revision) { await attempts.record() }

        let attemptCount = await attempts.count()
        XCTAssertEqual(attemptCount, 1)
    }

    func testNewRequestCanRefreshAgainAfterACompletedRefresh() async throws {
        let coordinator = SessionRefreshCoordinator()
        let attempts = SessionRefreshAttemptProbe()
        let initialRevision = await coordinator.revision()
        try await coordinator.refresh(observedRevision: initialRevision) { await attempts.record() }

        let currentRevision = await coordinator.revision()
        try await coordinator.refresh(observedRevision: currentRevision) { await attempts.record() }

        let attemptCount = await attempts.count()
        XCTAssertEqual(attemptCount, 2)
    }

    func testDifferentScopesDoNotShareTheSameRefreshTask() async throws {
        let coordinator = SessionRefreshCoordinator()
        let login = SessionRefreshLoginProbe()

        async let academic: Void = coordinator.refresh(scope: .academic) {
            try await login.perform()
        }
        async let campusCard: Void = coordinator.refresh(scope: .campusCard) {
            try await login.perform()
        }
        _ = try await (academic, campusCard)

        let loginCount = await login.count()
        XCTAssertEqual(loginCount, 2)
    }

    func testOnlyGetAndHeadAreAutomaticallyRetryable() {
        XCTAssertTrue(CampusRequestRetryPolicy.automatic(forHTTPMethod: "GET").allowsAutomaticRetry)
        XCTAssertTrue(CampusRequestRetryPolicy.automatic(forHTTPMethod: "head").allowsAutomaticRetry)
        XCTAssertFalse(CampusRequestRetryPolicy.automatic(forHTTPMethod: "POST").allowsAutomaticRetry)
        XCTAssertFalse(CampusRequestRetryPolicy.automatic(forHTTPMethod: "PATCH").allowsAutomaticRetry)
    }
}

private actor SessionRefreshLoginProbe {
    private var loginCount = 0

    func perform() async throws {
        loginCount += 1
        try await Task.sleep(for: .milliseconds(50))
    }

    func count() -> Int { loginCount }
}

private actor SessionRefreshAttemptProbe {
    private var attempts = 0
    func record() { attempts += 1 }
    func count() -> Int { attempts }
}
