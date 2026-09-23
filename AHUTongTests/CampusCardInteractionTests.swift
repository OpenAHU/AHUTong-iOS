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
        XCTAssertEqual(refreshCount, 1)
    }

    func testExplicitQRCodeLoadCanRestoreCampusCardSession() async {
        let api = CampusCardInteractionAPI(failsQRCode: true, recoversAfterRefresh: true)
        let suite = "campus-card-interaction-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = CampusCardViewModel(api: api, userID: "test-user", defaults: defaults)

        await model.loadQRCode(demo: false)
        let automaticRefreshCount = await api.refreshCount()
        XCTAssertEqual(automaticRefreshCount, 0)

        await model.loadQRCode(demo: false, force: true)

        XCTAssertEqual(model.qrState, .loaded("TEST-QR"))
        let explicitRefreshCount = await api.refreshCount()
        XCTAssertEqual(explicitRefreshCount, 1)
    }
}

private actor CampusCardInteractionAPI: CampusCoreAPI {
    private var balanceFlags: [Bool] = []
    private var qrCalls = 0
    private var refreshes = 0
    private let failsQRCode: Bool
    private let recoversAfterRefresh: Bool

    init(failsQRCode: Bool = false, recoversAfterRefresh: Bool = false) {
        self.failsQRCode = failsQRCode
        self.recoversAfterRefresh = recoversAfterRefresh
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
    func cardBalance(allowsInteractiveLogin: Bool) -> Double {
        balanceFlags.append(allowsInteractiveLogin)
        return 42
    }
    func cardQRCode() throws -> String {
        qrCalls += 1
        if failsQRCode && (!recoversAfterRefresh || refreshes == 0) {
            throw CampusCoreError.credentialsUnavailable
        }
        return "TEST-QR"
    }

    func refreshSession(scope: CampusSessionScope) throws {
        refreshes += 1
        if !recoversAfterRefresh { throw CampusCoreError.credentialsUnavailable }
    }

    func balanceInteractionFlags() -> [Bool] { balanceFlags }
    func qrRequestCount() -> Int { qrCalls }
    func refreshCount() -> Int { refreshes }
}
