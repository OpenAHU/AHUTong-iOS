import Foundation
import XCTest
@testable import AHUTong

@MainActor
final class CampusCardPriorityTests: XCTestCase {
    func testHomePrefetchRequestsQRCodeBeforeBalance() async {
        let api = DeferredCampusCardAPI()
        let defaults = makeDefaults()
        defer { defaults.0.removePersistentDomain(forName: defaults.1) }
        let model = CampusCardViewModel(api: api, userID: "qr-fixture", defaults: defaults.0)

        await model.prefetchQRCode(demo: false)

        let events = await api.events()
        XCTAssertEqual(events, ["qr", "balance"])
        XCTAssertEqual(model.qrState, .loaded("QR-1"))
        XCTAssertEqual(model.balance, 42)
    }

    func testQRCodeIsVisibleWhileSlowBalanceIsStillSuspended() async {
        let api = DeferredCampusCardAPI(suspendFirstBalance: true)
        let defaults = makeDefaults()
        defer { defaults.0.removePersistentDomain(forName: defaults.1) }
        defaults.0.set(19.5, forKey: CampusCardViewModel.cacheKey(for: "qr-fixture"))
        let model = CampusCardViewModel(api: api, userID: "qr-fixture", defaults: defaults.0)
        let prefetch = Task { await model.prefetchQRCode(demo: false) }
        await api.waitForBalance()

        XCTAssertEqual(model.qrState, .loaded("QR-1"))
        XCTAssertEqual(model.balance, 19.5)
        await model.loadQRCode(demo: false)
        let events = await api.events()
        XCTAssertEqual(events, ["qr", "balance"])

        await api.releaseBalance()
        await prefetch.value
        XCTAssertEqual(model.balance, 42)
    }

    func testOpeningQRCodeDoesNotWaitForExistingBalanceAndOldBalanceCannotOverwriteNewValue() async {
        let api = DeferredCampusCardAPI(suspendFirstBalance: true)
        let defaults = makeDefaults()
        defer { defaults.0.removePersistentDomain(forName: defaults.1) }
        let model = CampusCardViewModel(api: api, userID: "qr-fixture", defaults: defaults.0)
        let balance = Task { await model.load(demo: false) }
        await api.waitForBalance()

        await model.loadQRCode(demo: false)
        XCTAssertEqual(model.qrState, .loaded("QR-1"))
        XCTAssertEqual(model.balance, 84)
        await api.releaseBalance()
        await balance.value
        XCTAssertEqual(model.balance, 84)
        let events = await api.events()
        XCTAssertEqual(events, ["balance", "qr", "balance"])
    }

    func testConcurrentOpeningAndPrefetchShareOneQRCodeRequest() async {
        let api = DeferredCampusCardAPI(suspendFirstQR: true)
        let defaults = makeDefaults()
        defer { defaults.0.removePersistentDomain(forName: defaults.1) }
        let model = CampusCardViewModel(api: api, userID: "qr-fixture", defaults: defaults.0)
        let prefetch = Task { await model.prefetchQRCode(demo: false) }
        await api.waitForQR()

        await model.loadQRCode(demo: false)
        await model.load(demo: false)
        let waitingEvents = await api.events()
        XCTAssertEqual(waitingEvents, ["qr"])
        XCTAssertEqual(model.qrState, .loading)

        await api.releaseQR()
        await prefetch.value
        let completedEvents = await api.events()
        XCTAssertEqual(completedEvents, ["qr", "balance"])
    }

    func testExpiredPrefetchGetsANewCodeInsteadOfShowingOldPayload() async {
        let api = DeferredCampusCardAPI()
        let clock = MutableTestClock()
        let defaults = makeDefaults()
        defer { defaults.0.removePersistentDomain(forName: defaults.1) }
        let model = CampusCardViewModel(api: api, userID: "qr-fixture", defaults: defaults.0,
                                        now: { clock.now() })
        await model.prefetchQRCode(demo: false)
        clock.advance(seconds: 14)
        await model.loadQRCode(demo: false)
        XCTAssertEqual(model.qrState, .loaded("QR-1"))

        clock.advance(seconds: 1)
        await model.loadQRCode(demo: false)
        XCTAssertEqual(model.qrState, .loaded("QR-2"))
        let events = await api.events()
        XCTAssertEqual(events, ["qr", "balance", "qr", "balance"])
    }

    func testBackgroundInvalidationDiscardsLateQRCodeAndPrefetchesAgain() async {
        let api = DeferredCampusCardAPI(suspendFirstQR: true)
        let defaults = makeDefaults()
        defer { defaults.0.removePersistentDomain(forName: defaults.1) }
        let model = CampusCardViewModel(api: api, userID: "qr-fixture", defaults: defaults.0)
        let prefetch = Task { await model.prefetchQRCode(demo: false) }
        await api.waitForQR()

        model.invalidateQRCode()
        await api.releaseQR()
        await prefetch.value
        XCTAssertEqual(model.qrState, .idle)
        let invalidatedEvents = await api.events()
        XCTAssertEqual(invalidatedEvents, ["qr"])

        await model.prefetchQRCode(demo: false)
        XCTAssertEqual(model.qrState, .loaded("QR-2"))
        let events = await api.events()
        XCTAssertEqual(events, ["qr", "qr", "balance"])
    }

    func testFailedPrefetchStillLoadsBalanceWithoutRepeatedAutomaticQRCodeRequests() async {
        let api = DeferredCampusCardAPI(failsQR: true)
        let defaults = makeDefaults()
        defer { defaults.0.removePersistentDomain(forName: defaults.1) }
        let model = CampusCardViewModel(api: api, userID: "qr-fixture", defaults: defaults.0)

        await model.prefetchQRCode(demo: false)
        await model.prefetchQRCode(demo: false)

        XCTAssertEqual(model.balance, 42)
        if case .failed = model.qrState {} else { XCTFail("付款码失败应可显式重试") }
        let events = await api.events()
        XCTAssertEqual(events, ["qr", "balance"])
    }

    func testReopeningAfterPrefetchFailureActuallyRetries() async {
        let api = DeferredCampusCardAPI(failsQR: true)
        let defaults = makeDefaults()
        defer { defaults.0.removePersistentDomain(forName: defaults.1) }
        let model = CampusCardViewModel(api: api, userID: "qr-fixture", defaults: defaults.0)
        await model.prefetchQRCode(demo: false)
        await model.loadQRCode(demo: false, retryFailure: true)
        let events = await api.events()
        XCTAssertEqual(events, ["qr", "balance", "qr"])
    }

    func testShortcutActivationFailureRecoversOnForegroundWithoutRepeatedTimerRetries() async {
        let api = DeferredCampusCardAPI(failsFirstQR: true)
        let defaults = makeDefaults()
        defer { defaults.0.removePersistentDomain(forName: defaults.1) }
        let model = CampusCardViewModel(api: api, userID: "qr-fixture", defaults: defaults.0)
        await model.prefetchQRCode(demo: false)
        if case .failed = model.qrState {} else { XCTFail("First activation must fail in this fixture") }
        await model.loadQRCode(demo: false)
        await model.resumeAfterForeground(demo: false)
        XCTAssertEqual(model.qrState, .loaded("QR-2"))
        let events = await api.events()
        XCTAssertEqual(events, ["qr", "balance", "qr", "balance"])
    }

    func testExplicitRetryReplacesHungRequestAndLateResultCannotOverwrite() async {
        let api = DeferredCampusCardAPI(suspendFirstQR: true)
        let defaults = makeDefaults()
        defer { defaults.0.removePersistentDomain(forName: defaults.1) }
        let model = CampusCardViewModel(api: api, userID: "qr-fixture", defaults: defaults.0)
        let prefetch = Task { await model.prefetchQRCode(demo: false) }
        await api.waitForQR()
        await model.refreshQRCodeAndBalance(demo: false)
        XCTAssertEqual(model.qrState, .loaded("QR-2"))
        await api.releaseQR()
        await prefetch.value
        XCTAssertEqual(model.qrState, .loaded("QR-2"))
        let events = await api.events()
        XCTAssertEqual(events, ["qr", "qr", "balance"])
    }

    func testAutomaticBalanceRefreshDoesNotCancelSlowRequest() async {
        let api = DeferredCampusCardAPI(suspendFirstBalance: true)
        let clock = MutableTestClock()
        let defaults = makeDefaults()
        defer { defaults.0.removePersistentDomain(forName: defaults.1) }
        let model = CampusCardViewModel(api: api, userID: "slow-refresh", defaults: defaults.0, now: { clock.now() })
        let initialLoad = Task { await model.refreshBalanceIfNeeded(demo: false) }
        await api.waitForBalance()

        clock.advance(seconds: 30)
        await model.refreshBalanceIfNeeded(demo: false)
        let waitingEvents = await api.events()
        XCTAssertEqual(waitingEvents, ["balance"])
        await api.releaseBalance()
        await initialLoad.value
        XCTAssertEqual(model.balanceState, .loaded(42))

        await model.refreshBalanceIfNeeded(demo: false)
        XCTAssertEqual(model.balanceState, .loaded(84))
    }

    func testCancelledBalanceCanRecoverWhenForegroundQRCodeFails() async {
        let api = DeferredCampusCardAPI(suspendFirstBalance: true, failsQR: true)
        let defaults = makeDefaults()
        defer { defaults.0.removePersistentDomain(forName: defaults.1) }
        let model = CampusCardViewModel(api: api, userID: "cancel-recovery", defaults: defaults.0)
        let initialLoad = Task { await model.load(demo: false) }
        await api.waitForBalance()

        model.invalidateQRCode()
        XCTAssertEqual(model.balanceState, .idle)
        await model.resumeAfterForeground(demo: false)
        XCTAssertEqual(model.balanceState, .loaded(84))

        await api.releaseBalance()
        await initialLoad.value
        XCTAssertEqual(model.balanceState, .loaded(84))
    }

    private func makeDefaults() -> (UserDefaults, String) {
        let suite = "campus-card-priority-\(UUID().uuidString)"
        return (UserDefaults(suiteName: suite)!, suite)
    }
}

private actor DeferredCampusCardAPI: CampusCoreAPI {
    private let suspendFirstBalance: Bool
    private let suspendFirstQR: Bool
    private let failsQR: Bool
    private let failsFirstQR: Bool
    private var recordedEvents: [String] = []
    private var balanceCalls = 0
    private var qrCalls = 0
    private var balanceGate: CheckedContinuation<Void, Never>?
    private var qrGate: CheckedContinuation<Void, Never>?
    private var balanceWaiter: CheckedContinuation<Void, Never>?
    private var qrWaiter: CheckedContinuation<Void, Never>?

    init(suspendFirstBalance: Bool = false, suspendFirstQR: Bool = false, failsQR: Bool = false, failsFirstQR: Bool = false) {
        self.suspendFirstBalance = suspendFirstBalance
        self.suspendFirstQR = suspendFirstQR
        self.failsQR = failsQR
        self.failsFirstQR = failsFirstQR
    }

    func cardBalance() async -> Double { await cardBalance(allowsInteractiveLogin: false) }
    func cardBalance(allowsInteractiveLogin: Bool) async -> Double {
        balanceCalls += 1
        let call = balanceCalls
        recordedEvents.append("balance")
        balanceWaiter?.resume()
        balanceWaiter = nil
        if suspendFirstBalance && call == 1 {
            await withCheckedContinuation { balanceGate = $0 }
        }
        return call == 1 ? 42 : 84
    }
    func cardQRCode() async throws -> String {
        qrCalls += 1
        let call = qrCalls
        recordedEvents.append("qr")
        qrWaiter?.resume()
        qrWaiter = nil
        if suspendFirstQR && call == 1 { await withCheckedContinuation { qrGate = $0 } }
        if failsQR { throw CampusCoreError.invalidResponse }
        if failsFirstQR && call == 1 { throw CampusCoreError.sessionRefreshDeferred }
        return "QR-\(call)"
    }
    func waitForBalance() async {
        if balanceCalls == 0 { await withCheckedContinuation { balanceWaiter = $0 } }
    }
    func waitForQR() async {
        if qrCalls == 0 { await withCheckedContinuation { qrWaiter = $0 } }
    }
    func releaseBalance() { balanceGate?.resume(); balanceGate = nil }
    func releaseQR() { qrGate?.resume(); qrGate = nil }
    func events() -> [String] { recordedEvents }
    func initialize(cookiesJSON: String) {}
    func dumpCookies() -> String { "[]" }
    func cookiesFlat() -> String { "[]" }
    func schedule() -> [Course] { [] }
    func currentWeek() -> Int { 1 }
    func exams() -> [CampusExam] { [] }
    func grades() -> CampusGradeReport {
        CampusGradeReport(grades: [], gradePointAverage: nil, rank: nil, studentProfiles: [])
    }
    func refreshSession(scope: CampusSessionScope) throws { throw CampusCoreError.credentialsUnavailable }
}
