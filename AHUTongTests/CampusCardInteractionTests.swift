import Foundation
import XCTest
@testable import AHUTong

@MainActor
final class CampusCardInteractionTests: XCTestCase {
    func testPassiveBalanceLoadNeverAllowsInteractiveLogin() async {
        let api = CampusCardInteractionAPI()
        let suite = "campus-card-interaction-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = CampusCardViewModel(api: api, userID: "test-user", defaults: defaults)

        await model.load(demo: false)

        let flags = await api.balanceInteractionFlags()
        XCTAssertEqual(flags, [false])
        XCTAssertEqual(model.balance, 42)
    }

    func testBalanceCanRefreshSilentlyAfterCampusLogin() async {
        let api = CampusCardInteractionAPI(failsFirstBalance: true)
        let suite = "campus-card-interaction-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = CampusCardViewModel(api: api, userID: "test-user", defaults: defaults)

        await model.load(demo: false)
        XCTAssertNil(model.balance)

        await model.load(demo: false, refresh: true)

        XCTAssertEqual(model.balance, 42)
        let flags = await api.balanceInteractionFlags()
        XCTAssertEqual(flags, [false, false])
    }

    func testFailedAutomaticQRCodeLoadDoesNotRepeatUntilUserRetries() async {
        let api = CampusCardInteractionAPI(failsQRCode: true)
        let suite = "campus-card-interaction-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = CampusCardViewModel(api: api, userID: "test-user", defaults: defaults)

        await model.loadQRCode(demo: false)
        await model.loadQRCode(demo: false)
        let automaticCount = await api.qrRequestCount()

        await model.loadQRCode(demo: false, force: true)
        let explicitRetryCount = await api.qrRequestCount()
        let refreshCount = await api.refreshCount()

        XCTAssertEqual(automaticCount, 1)
        XCTAssertEqual(explicitRetryCount, 2)
        XCTAssertEqual(refreshCount, 2)
        let refreshFlags = await api.refreshInteractionFlags()
        XCTAssertEqual(refreshFlags, [false, false])
    }

    func testFirstQRCodeLoadCanRestoreCampusCardSessionSilently() async {
        let api = CampusCardInteractionAPI(failsQRCode: true, recoversAfterRefresh: true)
        let suite = "campus-card-interaction-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = CampusCardViewModel(api: api, userID: "test-user", defaults: defaults)

        await model.loadQRCode(demo: false)
        let automaticRefreshCount = await api.refreshCount()
        XCTAssertEqual(model.qrState, .loaded("TEST-QR"))
        XCTAssertEqual(automaticRefreshCount, 1)
        let refreshFlags = await api.refreshInteractionFlags()
        XCTAssertEqual(refreshFlags, [false])
    }

    func testExpandedQRCodeCanRenewSilentlyWithoutPresentingLogin() async {
        let api = CampusCardInteractionAPI(
            failsQRCode: true,
            recoversAfterRefresh: true
        )
        let suite = "campus-card-interaction-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = CampusCardViewModel(api: api, userID: "test-user", defaults: defaults)

        await model.loadQRCode(demo: false)

        XCTAssertEqual(model.qrState, .loaded("TEST-QR"))
        let refreshFlags = await api.refreshInteractionFlags()
        XCTAssertEqual(refreshFlags, [false])
        XCTAssertEqual(model.balance, 42)
    }

    func testFirstBalanceLoadCanRestoreCampusCardSessionSilently() async {
        let api = CampusCardInteractionAPI(recoversAfterRefresh: true, failsFirstBalance: true)
        let suite = "campus-card-first-balance-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = CampusCardViewModel(api: api, userID: "test-user", defaults: defaults)

        await model.load(demo: false)

        XCTAssertEqual(model.balance, 42)
        let refreshFlags = await api.refreshInteractionFlags()
        XCTAssertEqual(refreshFlags, [false])
    }

    func testTappingLoadedQRCodeForcesNewCodeAndRefreshesBalance() async {
        let api = CampusCardInteractionAPI()
        let suite = "campus-card-tap-refresh-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = CampusCardViewModel(api: api, userID: "test-user", defaults: defaults)

        await model.loadQRCode(demo: false)
        await model.refreshQRCodeAndBalance(demo: false)

        let qrRequests = await api.qrRequestCount()
        let balanceFlags = await api.balanceInteractionFlags()
        XCTAssertEqual(model.qrState, .loaded("TEST-QR"))
        XCTAssertEqual(qrRequests, 2)
        XCTAssertEqual(balanceFlags, [false, false])
    }
}

private actor CampusCardInteractionAPI: CampusCoreAPI {
    private var balanceFlags: [Bool] = []
    private var qrCalls = 0
    private var refreshes = 0
    private var refreshFlags: [Bool] = []
    private let failsQRCode: Bool
    private let recoversAfterRefresh: Bool
    private let failsFirstBalance: Bool
    private var balanceCalls = 0

    init(
        failsQRCode: Bool = false,
        recoversAfterRefresh: Bool = false,
        failsFirstBalance: Bool = false
    ) {
        self.failsQRCode = failsQRCode
        self.recoversAfterRefresh = recoversAfterRefresh
        self.failsFirstBalance = failsFirstBalance
    }

    func initialize(cookiesJSON: String) {}
    func dumpCookies() -> String { "[]" }
    func cookiesFlat() -> String { "[]" }
    func schedule() -> [Course] { [] }
    func currentWeek() -> Int { 1 }
    func exams() -> [CampusExam] { [] }
    func grades() -> CampusGradeReport {
        CampusGradeReport(grades: [], gradePointAverage: nil, rank: nil, studentProfiles: [])
    }
    func cardBalance() -> Double { 42 }
    func cardBalance(allowsInteractiveLogin: Bool) throws -> Double {
        balanceFlags.append(allowsInteractiveLogin)
        balanceCalls += 1
        if failsFirstBalance && balanceCalls == 1 {
            try refreshSession(scope: .campusCard, allowsInteractiveLogin: false)
        }
        return 42
    }
    func cardQRCode() throws -> String {
        qrCalls += 1
        if failsQRCode && (!recoversAfterRefresh || refreshes == 0) {
            try refreshSession(scope: .campusCard, allowsInteractiveLogin: false)
        }
        return "TEST-QR"
    }

    func refreshSession(scope: CampusSessionScope) throws {
        refreshes += 1
        if !recoversAfterRefresh { throw CampusCoreError.credentialsUnavailable }
    }

    func refreshSession(scope: CampusSessionScope, allowsInteractiveLogin: Bool) throws {
        refreshFlags.append(allowsInteractiveLogin)
        try refreshSession(scope: scope)
    }

    func balanceInteractionFlags() -> [Bool] { balanceFlags }
    func qrRequestCount() -> Int { qrCalls }
    func refreshCount() -> Int { refreshes }
    func refreshInteractionFlags() -> [Bool] { refreshFlags }
}
