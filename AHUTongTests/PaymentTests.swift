import Foundation
import XCTest
@testable import AHUTong

final class PaymentAmountTests: XCTestCase {
    func testAcceptsPositiveAmountWithAtMostTwoFractionDigits() throws {
        XCTAssertEqual(try PaymentAmount("12").text, "12.00")
        XCTAssertEqual(try PaymentAmount("12.3").text, "12.30")
        XCTAssertEqual(try PaymentAmount("12.34").text, "12.34")
    }

    func testRejectsBlankZeroNegativeAndMalformedAmounts() {
        XCTAssertThrowsError(try PaymentAmount(""))
        XCTAssertThrowsError(try PaymentAmount("0"))
        XCTAssertThrowsError(try PaymentAmount("-1"))
        XCTAssertThrowsError(try PaymentAmount("1.2.3"))
    }

    func testRejectsMoreThanTwoFractionDigitsAndExcessiveAmount() {
        XCTAssertThrowsError(try PaymentAmount("1.234")) { error in
            XCTAssertEqual(error as? PaymentValidationError, .tooManyFractionDigits)
        }
        XCTAssertThrowsError(try PaymentAmount("500.01")) { error in
            XCTAssertEqual(error as? PaymentValidationError, .exceedsLimit)
        }
    }

    func testCampusAccountRequiresSixDigitTransientAuthorization() throws {
        let amount = try PaymentAmount("10")
        XCTAssertThrowsError(try PaymentRequest(
            feature: .bathroom,
            method: .campusAccount,
            amount: amount,
            accountID: "bath-1",
            accountLabel: "竹园",
            authorization: "12345"
        ))
        XCTAssertNoThrow(try PaymentRequest(
            feature: .bathroom,
            method: .campusAccount,
            amount: amount,
            accountID: "bath-1",
            accountLabel: "竹园",
            authorization: "123456"
        ))
    }
}

@MainActor
final class PaymentCoordinatorTests: XCTestCase {
    func testServerConfirmationIsRequiredBeforeSuccess() async throws {
        let coordinator = makeCoordinator(feature: .cardRecharge, gateway: DemoPaymentGateway())
        await coordinator.submit(try request(feature: .cardRecharge, method: .bankCard))
        guard case let .succeeded(orderID, message) = coordinator.phase else {
            return XCTFail("Expected reconciled success, got \(coordinator.phase)")
        }
        XCTAssertTrue(orderID.hasPrefix("MOCK-CARD"))
        XCTAssertEqual(message, "服务端已确认支付成功")
    }

    func testRejectedConfirmationNeverPresentsSuccess() async throws {
        let coordinator = makeCoordinator(
            feature: .bathroom,
            gateway: DemoPaymentGateway(mode: .rejected)
        )
        await coordinator.submit(try request(feature: .bathroom, method: .campusAccount))
        guard case let .failed(message) = coordinator.phase else {
            return XCTFail("Expected failure, got \(coordinator.phase)")
        }
        XCTAssertEqual(message, "服务端拒绝了本次支付")
    }

    func testUnknownStatusKeepsOrderForExplicitReconciliation() async throws {
        let store = makePendingStore()
        let coordinator = PaymentCoordinator(
            feature: .electricity,
            gateway: DemoPaymentGateway(mode: .unknown),
            pendingStore: store
        )
        await coordinator.submit(try request(feature: .electricity, method: .campusAccount))
        guard case let .unknown(orderID, _) = coordinator.phase else {
            return XCTFail("Expected unknown result, got \(coordinator.phase)")
        }
        XCTAssertEqual(store.load()?.orderID, orderID)
    }

    func testExternalReturnPersistsThenReconcilesOrder() async throws {
        let store = makePendingStore()
        let coordinator = PaymentCoordinator(
            feature: .cardRecharge,
            gateway: DemoPaymentGateway(),
            pendingStore: store
        )
        let url = await coordinator.submit(try request(feature: .cardRecharge, method: .alipay))
        XCTAssertEqual(url?.scheme, "alipays")
        guard case let .awaitingExternal(orderID) = coordinator.phase else {
            return XCTFail("Expected external wait, got \(coordinator.phase)")
        }
        XCTAssertEqual(store.load()?.orderID, orderID)

        await coordinator.resumeExternalReturn()
        guard case .succeeded = coordinator.phase else {
            return XCTFail("Expected reconciled success, got \(coordinator.phase)")
        }
        XCTAssertNil(store.load())
    }

    func testPendingOrderCanBeRecoveredAfterCoordinatorRecreation() async throws {
        let store = makePendingStore()
        let gateway = DemoPaymentGateway()
        let first = PaymentCoordinator(feature: .cardRecharge, gateway: gateway, pendingStore: store)
        _ = await first.submit(try request(feature: .cardRecharge, method: .alipay))

        let restored = PaymentCoordinator(feature: .cardRecharge, gateway: gateway, pendingStore: store)
        await restored.resumePendingOrder()
        guard case .succeeded = restored.phase else {
            return XCTFail("Expected restored success, got \(restored.phase)")
        }
    }

    func testTerminalReconciliationClearsSubmissionLeftByCrashWindow() async {
        let store = makePendingStore()
        store.save(PendingPayment(
            feature: .cardRecharge,
            orderID: "CRASH-WINDOW-1"
        ))
        store.saveSubmission(PendingPaymentSubmission(
            feature: .cardRecharge,
            idempotencyKey: "crash-window-key",
            requestFingerprint: "test-fingerprint"
        ))
        let coordinator = PaymentCoordinator(
            feature: .cardRecharge,
            gateway: CountingPaymentGateway(),
            pendingStore: store
        )

        await coordinator.resumePendingOrder()

        guard case .succeeded = coordinator.phase else {
            return XCTFail(
                "Terminal reconciliation must recover the pending order, got \(coordinator.phase)"
            )
        }
        XCTAssertNil(store.load())
        XCTAssertNil(store.loadSubmission())
    }

    func testDuplicateSubmissionIsIgnoredWhileRequestIsInFlight() async throws {
        let gateway = CountingPaymentGateway()
        let coordinator = makeCoordinator(feature: .cardRecharge, gateway: gateway)
        let paymentRequest = try request(feature: .cardRecharge, method: .bankCard)

        async let first: URL? = coordinator.submit(paymentRequest, idempotencyKey: "same-key")
        async let second: URL? = coordinator.submit(paymentRequest, idempotencyKey: "second-key")
        _ = await (first, second)

        let createCount = await gateway.createCount
        XCTAssertEqual(createCount, 1)
        guard case .succeeded = coordinator.phase else {
            return XCTFail("Expected success, got \(coordinator.phase)")
        }
    }

    func testTimeoutAndSafetyBlockNeverPresentSuccess() async throws {
        let timeout = makeCoordinator(
            feature: .cardRecharge,
            gateway: DemoPaymentGateway(mode: .timeout)
        )
        await timeout.submit(try request(feature: .cardRecharge, method: .bankCard))
        guard case .failed = timeout.phase else { return XCTFail("Timeout must fail safely") }

        let blocked = makeCoordinator(feature: .cardRecharge, gateway: SafetyBlockedPaymentGateway())
        await blocked.submit(try request(feature: .cardRecharge, method: .bankCard))
        guard case let .failed(message) = blocked.phase else { return XCTFail("Safety block must fail safely") }
        XCTAssertTrue(message.contains("未发起任何扣款"))
    }

    func testFeatureMismatchIsRejectedBeforeCreatingOrder() async throws {
        let gateway = CountingPaymentGateway()
        let coordinator = makeCoordinator(feature: .bathroom, gateway: gateway)

        await coordinator.submit(try request(feature: .electricity, method: .campusAccount))

        let createCount = await gateway.createCount
        XCTAssertEqual(createCount, 0)
        guard case let .failed(message) = coordinator.phase else {
            return XCTFail("Mismatched request must fail")
        }
        XCTAssertEqual(message, PaymentGatewayError.featureMismatch.localizedDescription)
    }

    func testCancelClearsPendingOrder() async throws {
        let store = makePendingStore()
        let coordinator = PaymentCoordinator(
            feature: .cardRecharge,
            gateway: DemoPaymentGateway(),
            pendingStore: store
        )
        _ = await coordinator.submit(try request(feature: .cardRecharge, method: .alipay))
        await coordinator.cancel()
        XCTAssertEqual(coordinator.phase, .cancelled)
        XCTAssertNil(store.load())
    }

    func testCancellationAfterOrderCreationKeepsPendingOrderRecoverable() async throws {
        let store = makePendingStore()
        let gateway = ConfirmSuspendingPaymentGateway()
        let coordinator = PaymentCoordinator(
            feature: .cardRecharge,
            gateway: gateway,
            pendingStore: store
        )
        let paymentRequest = try request(
            feature: .cardRecharge,
            method: .bankCard
        )

        let submission = Task {
            await coordinator.submit(paymentRequest)
        }
        await gateway.waitUntilConfirmEntered()
        XCTAssertEqual(store.load()?.orderID, "CANCEL-1")

        submission.cancel()
        _ = await submission.value

        guard case let .unknown(orderID, message) = coordinator.phase else {
            return XCTFail(
                "Cancellation after order creation must remain recoverable, got \(coordinator.phase)"
            )
        }
        XCTAssertEqual(orderID, "CANCEL-1")
        XCTAssertTrue(message.contains("待核验"))
        XCTAssertEqual(store.load()?.orderID, orderID)

        let restored = PaymentCoordinator(
            feature: .cardRecharge,
            gateway: gateway,
            pendingStore: store
        )
        await restored.resumePendingOrder()
        guard case .succeeded = restored.phase else {
            return XCTFail("Expected restored order to reconcile, got \(restored.phase)")
        }
        XCTAssertNil(store.load())
    }

    func testFailureAfterOrderCreationCannotLeakOrCreateDuplicateOrder() async throws {
        let store = makePendingStore()
        let gateway = ConfirmFailingPaymentGateway()
        let coordinator = PaymentCoordinator(
            feature: .cardRecharge,
            gateway: gateway,
            pendingStore: store
        )
        let paymentRequest = try request(
            feature: .cardRecharge,
            method: .bankCard
        )

        await coordinator.submit(paymentRequest)

        guard case let .unknown(orderID, message) = coordinator.phase else {
            return XCTFail(
                "Post-create transport failure must remain recoverable, got \(coordinator.phase)"
            )
        }
        XCTAssertEqual(orderID, "RECOVERABLE-1")
        XCTAssertFalse(message.contains("private-token"))
        XCTAssertEqual(store.load()?.orderID, orderID)

        coordinator.reset()
        await coordinator.submit(paymentRequest)

        let createCount = await gateway.createCount
        XCTAssertEqual(createCount, 1)
        guard case .succeeded = coordinator.phase else {
            return XCTFail(
                "A resubmission must reconcile the pending order, got \(coordinator.phase)"
            )
        }
        XCTAssertNil(store.load())
    }

    func testLostCreateResponseReusesPersistedIdempotencyKeyAfterRecreation() async throws {
        let store = makePendingStore()
        let gateway = CreateResponseLostPaymentGateway()
        let paymentRequest = try request(
            feature: .bathroom,
            method: .campusAccount
        )
        let first = PaymentCoordinator(
            feature: .bathroom,
            gateway: gateway,
            pendingStore: store
        )

        await first.submit(
            paymentRequest,
            idempotencyKey: "persisted-attempt-key"
        )

        guard case .failed = first.phase else {
            return XCTFail(
                "A lost create response must not be reported as success, got \(first.phase)"
            )
        }
        XCTAssertNil(store.load())
        XCTAssertEqual(
            store.loadSubmission()?.idempotencyKey,
            "persisted-attempt-key"
        )

        let restored = PaymentCoordinator(
            feature: .bathroom,
            gateway: gateway,
            pendingStore: store
        )
        await restored.submit(
            paymentRequest,
            idempotencyKey: "must-not-replace-persisted-key"
        )

        let receivedKeys = await gateway.receivedIdempotencyKeys
        let createdOrderCount = await gateway.createdOrderCount
        XCTAssertEqual(
            receivedKeys,
            ["persisted-attempt-key", "persisted-attempt-key"]
        )
        XCTAssertEqual(createdOrderCount, 1)
        guard case .succeeded = restored.phase else {
            return XCTFail(
                "Retry with the persisted key must recover the existing order, got \(restored.phase)"
            )
        }
        XCTAssertNil(store.loadSubmission())
        XCTAssertNil(store.load())
    }

    func testPendingStoreNeverPersistsAuthorization() throws {
        let suite = "PaymentAuthorizationTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let store = PendingPaymentStore(defaults: defaults, key: "pending")

        _ = try request(feature: .bathroom, method: .campusAccount)
        store.save(PendingPayment(feature: .bathroom, orderID: "ORDER-1"))

        let raw = String(data: try XCTUnwrap(defaults.data(forKey: "pending")), encoding: .utf8)
        XCTAssertFalse(try XCTUnwrap(raw).contains("123456"))
    }

    private func request(feature: PaymentFeature, method: PaymentMethod) throws -> PaymentRequest {
        try PaymentRequest(
            feature: feature,
            method: method,
            amount: PaymentAmount("10.00"),
            accountID: "mock-account",
            accountLabel: "Mock 账户",
            authorization: method == .campusAccount ? "123456" : nil
        )
    }

    private func makeCoordinator(feature: PaymentFeature, gateway: any PaymentGateway) -> PaymentCoordinator {
        PaymentCoordinator(feature: feature, gateway: gateway, pendingStore: makePendingStore())
    }

    private func makePendingStore() -> PendingPaymentStore {
        let suite = "PaymentTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return PendingPaymentStore(defaults: defaults, key: "pending")
    }
}

final class PaymentCatalogTests: XCTestCase {
    func testOfficialPortalUsesSchoolHTTPSLoginTransit() throws {
        let url = OfficialSchoolPaymentPortal.loginURL
        XCTAssertEqual(url.scheme, "https")
        XCTAssertEqual(url.host, "ycard.ahu.edu.cn")
        XCTAssertEqual(url.path, "/berserker-auth/cas/redirect/neusoftCas")

        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        let target = try XCTUnwrap(components.queryItems?.first { $0.name == "targetUrl" }?.value)
        let targetURL = try XCTUnwrap(URL(string: target))
        XCTAssertEqual(targetURL.scheme, "https")
        XCTAssertEqual(targetURL.host, "ycard.ahu.edu.cn")
        XCTAssertEqual(targetURL.path, "/plat")
        XCTAssertEqual(URLComponents(url: targetURL, resolvingAgainstBaseURL: false)?.queryItems?.first?.value, "loginTransit")
    }

    func testCardRechargeFixtureUsesNonProductionAccountAndBalance() {
        XCTAssertTrue(PaymentDemoCatalog.cardAccountID.hasPrefix("mock-"))
        XCTAssertEqual(PaymentDemoCatalog.cardBalance, Decimal(string: "126.35"))
    }

    func testBathroomFixtureKeepsPhoneLookupAndDistinctAccounts() {
        XCTAssertEqual(PaymentDemoCatalog.phone.count, 11)
        XCTAssertEqual(Set(PaymentDemoCatalog.bathrooms.map(\.id)).count, PaymentDemoCatalog.bathrooms.count)
        XCTAssertTrue(PaymentDemoCatalog.bathrooms.allSatisfy { $0.phone == PaymentDemoCatalog.phone })
    }

    func testElectricityFixtureProvidesCompleteCampusBuildingFloorRoomPath() {
        XCTAssertFalse(PaymentDemoCatalog.electricityRooms.isEmpty)
        XCTAssertTrue(PaymentDemoCatalog.electricityRooms.allSatisfy {
            !$0.campus.isEmpty && !$0.building.isEmpty && !$0.floor.isEmpty && !$0.room.isEmpty
        })
        XCTAssertEqual(Set(PaymentDemoCatalog.electricityRooms.map(\.id)).count, PaymentDemoCatalog.electricityRooms.count)
    }
}

private actor CountingPaymentGateway: PaymentGateway {
    private(set) var createCount = 0

    func createOrder(request: PaymentRequest, idempotencyKey: String) async throws -> PaymentOrder {
        createCount += 1
        try await Task.sleep(for: .milliseconds(100))
        return PaymentOrder(id: "COUNT-1", externalURL: nil)
    }

    func confirm(orderID: String, authorization: String?) async throws -> PaymentOrderStatus {
        .pending("等待核验")
    }

    func status(orderID: String) async throws -> PaymentOrderStatus {
        .confirmed("已确认")
    }

    func cancel(orderID: String) async { }
}

private actor ConfirmSuspendingPaymentGateway: PaymentGateway {
    private var confirmEntered = false
    private var confirmWaiters: [CheckedContinuation<Void, Never>] = []

    func createOrder(
        request: PaymentRequest,
        idempotencyKey: String
    ) async throws -> PaymentOrder {
        PaymentOrder(id: "CANCEL-1", externalURL: nil)
    }

    func confirm(
        orderID: String,
        authorization: String?
    ) async throws -> PaymentOrderStatus {
        confirmEntered = true
        let waiters = confirmWaiters
        confirmWaiters.removeAll(keepingCapacity: false)
        waiters.forEach { $0.resume() }
        try await Task.sleep(for: .seconds(30))
        return .pending("等待核验")
    }

    func status(orderID: String) async throws -> PaymentOrderStatus {
        .confirmed("已恢复确认")
    }

    func cancel(orderID: String) async { }

    func waitUntilConfirmEntered() async {
        guard !confirmEntered else { return }
        await withCheckedContinuation { continuation in
            confirmWaiters.append(continuation)
        }
    }
}

private actor ConfirmFailingPaymentGateway: PaymentGateway {
    private(set) var createCount = 0

    func createOrder(
        request: PaymentRequest,
        idempotencyKey: String
    ) async throws -> PaymentOrder {
        createCount += 1
        return PaymentOrder(id: "RECOVERABLE-1", externalURL: nil)
    }

    func confirm(
        orderID: String,
        authorization: String?
    ) async throws -> PaymentOrderStatus {
        throw PaymentGatewayError.server("token=private-token")
    }

    func status(orderID: String) async throws -> PaymentOrderStatus {
        .confirmed("已恢复确认")
    }

    func cancel(orderID: String) async { }
}

private actor CreateResponseLostPaymentGateway: PaymentGateway {
    private var ordersByIdempotencyKey: [String: PaymentOrder] = [:]
    private(set) var receivedIdempotencyKeys: [String] = []
    private(set) var createdOrderCount = 0

    func createOrder(
        request: PaymentRequest,
        idempotencyKey: String
    ) async throws -> PaymentOrder {
        receivedIdempotencyKeys.append(idempotencyKey)
        if let existing = ordersByIdempotencyKey[idempotencyKey] {
            return existing
        }

        createdOrderCount += 1
        let order = PaymentOrder(id: "LOST-CREATE-1", externalURL: nil)
        ordersByIdempotencyKey[idempotencyKey] = order
        // The server has committed the order, but the first response is lost.
        throw URLError(.networkConnectionLost)
    }

    func confirm(
        orderID: String,
        authorization: String?
    ) async throws -> PaymentOrderStatus {
        .confirmed("已确认且未重复建单")
    }

    func status(orderID: String) async throws -> PaymentOrderStatus {
        .confirmed("已恢复确认")
    }

    func cancel(orderID: String) async { }
}
