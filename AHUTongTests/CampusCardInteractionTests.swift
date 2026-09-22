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

        XCTAssertEqual(automaticCount, 1)
        XCTAssertEqual(explicitRetryCount, 2)
    }
}

private actor CampusCardInteractionAPI: CampusCoreAPI {
    private var balanceFlags: [Bool] = []
    private var qrCalls = 0
    private let failsQRCode: Bool

    init(failsQRCode: Bool = false) {
        self.failsQRCode = failsQRCode
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
        if failsQRCode { throw CampusCoreError.credentialsUnavailable }
        return "TEST-QR"
    }

    func balanceInteractionFlags() -> [Bool] { balanceFlags }
    func qrRequestCount() -> Int { qrCalls }
}
