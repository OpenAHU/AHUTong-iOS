import Foundation
import XCTest
@testable import AHUTong

final class PaymentAmountTests: XCTestCase {
    func testAcceptsPositiveAmountWithAtMostTwoFractionDigits() throws {
        XCTAssertEqual(try PaymentAmount("12").text, "12.00")
        XCTAssertEqual(try PaymentAmount("12.3").text, "12.30")
        XCTAssertEqual(try PaymentAmount("12.34").text, "12.34")
    }

    func testRejectsBlankZeroNegativeMalformedAndExcessiveAmounts() {
        for value in ["", "0", "-1", "1.2.3", "1.234", "500.01"] {
            XCTAssertThrowsError(try PaymentAmount(value))
        }
    }

    func testRequestRejectsMismatchedTransactionContext() throws {
        XCTAssertThrowsError(try PaymentRequest(
            feature: .bathroom,
            method: .campusAccount,
            amount: PaymentAmount("10"),
            accountID: "test-account",
            accountLabel: "测试账户",
            context: .electricity(thirdPartyJSON: "{}")
        )) { error in
            XCTAssertEqual(
                error as? PaymentValidationError,
                .invalidTransactionContext
            )
        }
    }
}

final class TransientPaymentAuthorizationTests: XCTestCase {
    func testAuthorizationCanBeConsumedOnlyOnceAndOriginalBufferIsCleared() throws {
        let authorization = try makeAuthorization()
        var consumed = try authorization.consumeASCIIBytes()
        defer { wipe(&consumed) }

        XCTAssertEqual(consumed.count, 6)
        XCTAssertTrue(authorization.isCleared)
        XCTAssertThrowsError(try authorization.consumeASCIIBytes())
    }

    func testExplicitClearIsIdempotent() throws {
        let authorization = try makeAuthorization()
        authorization.clear()
        authorization.clear()

        XCTAssertTrue(authorization.isCleared)
        XCTAssertThrowsError(try authorization.consumeASCIIBytes())
    }

    func testOnlySixASCIIDigitsAreAccepted() {
        for invalid in ["", "12345", "1234567", "１２３４５６", "12345x"] {
            XCTAssertThrowsError(
                try TransientPaymentAuthorization(digits: invalid)
            )
        }
    }
}

@MainActor
final class PaymentCoordinatorTests: XCTestCase {
    func testServerConfirmationIsRequiredBeforeSuccess() async throws {
        let coordinator = makeCoordinator(
            feature: .cardRecharge,
            gateway: DemoPaymentGateway()
        )

        await coordinator.submit(try request(
            feature: .cardRecharge,
            method: .bankCard
        ))

        guard case let .succeeded(orderID, _) = coordinator.phase else {
            return XCTFail("Expected a server-confirmed terminal state")
        }
        XCTAssertTrue(orderID.hasPrefix("MOCK-CARD"))
    }

    func testRejectedServerResultNeverPresentsSuccess() async throws {
        let coordinator = makeCoordinator(
            feature: .bathroom,
            gateway: DemoPaymentGateway(mode: .rejected)
        )
        let authorization = try makeAuthorization()

        await coordinator.submit(
            try request(feature: .bathroom, method: .campusAccount),
            authorization: authorization
        )

        guard case .failed = coordinator.phase else {
            return XCTFail("Expected a rejected terminal state")
        }
        XCTAssertTrue(authorization.isCleared)
    }

    func testLostCreateResponseLocksAttemptAndNeverCreatesAgain() async throws {
        let store = makePendingStore()
        let gateway = LostCreateResponseGateway()
        let first = PaymentCoordinator(
            feature: .bathroom,
            gateway: gateway,
            pendingStore: store
        )
        let firstAuthorization = try makeAuthorization()
        let paymentRequest = try request(
            feature: .bathroom,
            method: .campusAccount
        )

        await first.submit(
            paymentRequest,
            authorization: firstAuthorization,
            idempotencyKey: "first-local-attempt"
        )

        guard case .creationUnknown = first.phase else {
            return XCTFail("A lost create response must lock the attempt")
        }
        XCTAssertTrue(firstAuthorization.isCleared)
        XCTAssertEqual(store.load()?.stage, .creationUnknown)

        let restored = PaymentCoordinator(
            feature: .bathroom,
            gateway: gateway,
            pendingStore: store
        )
        await restored.resumePendingOrder()
        let secondAuthorization = try makeAuthorization()
        await restored.submit(
            paymentRequest,
            authorization: secondAuthorization,
            idempotencyKey: "must-not-be-used"
        )

        XCTAssertTrue(secondAuthorization.isCleared)
        let createCount = await gateway.createCount
        XCTAssertEqual(createCount, 1)
        guard case .creationUnknown = restored.phase else {
            return XCTFail("Restored create-unknown state must remain locked")
        }
    }

    func testOrderCreatedRecoveryContinuesSameOrderWithoutCreatingAgain() async throws {
        let store = makePendingStore()
        let gateway = RecoverablePreparedGateway()
        let paymentRequest = try request(
            feature: .electricity,
            method: .campusAccount
        )
        let first = PaymentCoordinator(
            feature: .electricity,
            gateway: gateway,
            pendingStore: store
        )
        let firstAuthorization = try makeAuthorization()

        await first.submit(
            paymentRequest,
            authorization: firstAuthorization
        )

        guard case let .failed(message) = first.phase else {
            return XCTFail("Preparation failure must be visible to the user")
        }
        XCTAssertTrue(message.contains("原订单已保留"))
        XCTAssertTrue(firstAuthorization.isCleared)
        XCTAssertEqual(store.load()?.orderID, "RECOVERABLE-ORDER")
        XCTAssertEqual(store.load()?.stage, .orderCreated)

        first.reset()
        guard case .awaitingConfirmation = first.phase else {
            return XCTFail("The visible failure must remain retryable")
        }
        XCTAssertEqual(store.load()?.stage, .orderCreated)

        let restored = PaymentCoordinator(
            feature: .electricity,
            gateway: gateway,
            pendingStore: store
        )
        await restored.resumePendingOrder()
        guard case .awaitingConfirmation = restored.phase else {
            return XCTFail("A created order must require explicit continuation")
        }

        let secondAuthorization = try makeAuthorization()
        await restored.continuePendingOrder(
            authorization: secondAuthorization
        )

        XCTAssertTrue(secondAuthorization.isCleared)
        let createCount = await gateway.createCount
        let prepareCount = await gateway.prepareCount
        let submitCount = await gateway.submitCount
        XCTAssertEqual(createCount, 1)
        XCTAssertEqual(prepareCount, 2)
        XCTAssertEqual(submitCount, 1)
        guard case .succeeded = restored.phase else {
            return XCTFail("The existing order should reach its terminal result")
        }
        XCTAssertNil(store.load())
    }

    func testDuplicateSubmitRestoresCreatedOrderWithoutRequiringPasswordAgain() async throws {
        let store = makePendingStore()
        XCTAssertTrue(store.save(PendingPayment(
            feature: .bathroom,
            orderID: "EXISTING-ORDER",
            method: .campusAccount,
            stage: .orderCreated
        )))
        let gateway = CountingGuardGateway()
        let coordinator = PaymentCoordinator(
            feature: .bathroom,
            gateway: gateway,
            pendingStore: store
        )

        await coordinator.submit(try request(
            feature: .bathroom,
            method: .campusAccount
        ))

        guard case let .awaitingConfirmation(orderID) = coordinator.phase else {
            return XCTFail("A duplicate tap must restore the existing order")
        }
        XCTAssertEqual(orderID, "EXISTING-ORDER")
        let createCount = await gateway.createCount
        XCTAssertEqual(createCount, 0)
        XCTAssertEqual(store.load()?.stage, .orderCreated)
    }

    func testFinalTimeoutNeverResubmitsPreparedPayment() async throws {
        let store = makePendingStore()
        let gateway = FinalResponseLostGateway()
        let first = PaymentCoordinator(
            feature: .networkRecharge,
            gateway: gateway,
            pendingStore: store
        )
        let authorization = try makeAuthorization()

        await first.submit(
            try request(
                feature: .networkRecharge,
                method: .campusAccount
            ),
            authorization: authorization
        )

        XCTAssertTrue(authorization.isCleared)
        guard case .unknown = first.phase else {
            return XCTFail("A lost final response must remain unknown")
        }
        XCTAssertEqual(store.load()?.stage, .resultUnknown)

        let restored = PaymentCoordinator(
            feature: .networkRecharge,
            gateway: gateway,
            pendingStore: store
        )
        await restored.resumePendingOrder()
        await restored.continuePendingOrder()

        let createCount = await gateway.createCount
        let prepareCount = await gateway.prepareCount
        let submitCount = await gateway.submitCount
        let statusCount = await gateway.statusCount
        XCTAssertEqual(createCount, 1)
        XCTAssertEqual(prepareCount, 1)
        XCTAssertEqual(submitCount, 1)
        XCTAssertEqual(statusCount, 2)
        XCTAssertEqual(store.load()?.stage, .resultUnknown)
    }

    func testFinalSubmissionStageIsPersistedBeforeMutationRequest() async throws {
        let fixture = makeStoreFixture()
        let gateway = FinalStageObservingGateway(
            suiteName: fixture.suite,
            key: fixture.key
        )
        let coordinator = PaymentCoordinator(
            feature: .cardRecharge,
            gateway: gateway,
            pendingStore: fixture.store
        )

        await coordinator.submit(try request(
            feature: .cardRecharge,
            method: .bankCard
        ))

        let observedFinalSubmissionStage = await gateway.observedFinalSubmissionStage
        XCTAssertTrue(observedFinalSubmissionStage)
        guard case .succeeded = coordinator.phase else {
            return XCTFail("Expected terminal success after observing the gate")
        }
    }

    func testDuplicateSubmissionIsIgnoredWhileCreateIsInFlight() async throws {
        let gateway = SuspendedCreateGateway()
        let coordinator = makeCoordinator(
            feature: .bathroom,
            gateway: gateway
        )
        let paymentRequest = try request(
            feature: .bathroom,
            method: .campusAccount
        )
        let firstAuthorization = try makeAuthorization()
        let first = Task { @MainActor in
            await coordinator.submit(
                paymentRequest,
                authorization: firstAuthorization
            )
        }
        await gateway.waitUntilCreateStarts()

        let duplicateAuthorization = try makeAuthorization()
        await coordinator.submit(
            paymentRequest,
            authorization: duplicateAuthorization
        )
        XCTAssertTrue(duplicateAuthorization.isCleared)

        await gateway.releaseCreate()
        _ = await first.value

        XCTAssertTrue(firstAuthorization.isCleared)
        let createCount = await gateway.createCount
        XCTAssertEqual(createCount, 1)
        guard case .succeeded = coordinator.phase else {
            return XCTFail("The original in-flight submission should finish")
        }
    }

    func testConcurrentResumeStartsOnlyOneStatusRequest() async {
        let store = makePendingStore()
        XCTAssertTrue(store.save(PendingPayment(
            feature: .cardRecharge,
            orderID: "RECOVERY-ORDER",
            method: .bankCard,
            stage: .resultUnknown
        )))
        let gateway = OutOfOrderStatusGateway()
        let coordinator = PaymentCoordinator(
            feature: .cardRecharge,
            gateway: gateway,
            pendingStore: store
        )
        let first = Task { @MainActor in
            await coordinator.resumePendingOrder()
        }
        await gateway.waitUntilFirstStatusStarts()

        await coordinator.resumePendingOrder()
        await coordinator.resumeExternalReturn()

        let countWhileSuspended = await gateway.statusCount
        XCTAssertEqual(countWhileSuspended, 1)
        await gateway.releaseFirstStatus(.confirmed("已确认"))
        _ = await first.value
        let finalCount = await gateway.statusCount
        XCTAssertEqual(finalCount, 1)
        XCTAssertNil(store.load())
        guard case .succeeded = coordinator.phase else {
            return XCTFail("The single recovery request should complete")
        }
    }

    func testConcurrentContinueStartsOnlyOneFinalSubmission() async {
        let store = makePendingStore()
        XCTAssertTrue(store.save(PendingPayment(
            feature: .cardRecharge,
            orderID: "CONTINUE-ORDER",
            method: .bankCard,
            stage: .orderCreated
        )))
        let gateway = SuspendedFinalSubmitGateway()
        let coordinator = PaymentCoordinator(
            feature: .cardRecharge,
            gateway: gateway,
            pendingStore: store
        )
        let first = Task { @MainActor in
            await coordinator.continuePendingOrder()
        }
        await gateway.waitUntilSubmitStarts()

        await coordinator.continuePendingOrder()

        let prepareCount = await gateway.prepareCount
        let submitCount = await gateway.submitCount
        XCTAssertEqual(prepareCount, 1)
        XCTAssertEqual(submitCount, 1)
        await gateway.releaseSubmit(.confirmed("已确认"))
        _ = await first.value
        XCTAssertNil(store.load())
        guard case .succeeded = coordinator.phase else {
            return XCTFail("Only the first continuation may finish the order")
        }
    }

    func testStalePendingStatusCannotOverwriteNewerConfirmation() async {
        await assertStaleStatusCannotOverwriteConfirmation(
            .pending("旧查询仍在处理")
        )
    }

    func testStaleUnknownStatusCannotOverwriteNewerConfirmation() async {
        await assertStaleStatusCannotOverwriteConfirmation(
            .unknown("旧查询结果未知")
        )
    }

    func testStaleFinalSubmitResponseCannotRestorePendingAfterConfirmation() async {
        let store = makePendingStore()
        XCTAssertTrue(store.save(PendingPayment(
            feature: .cardRecharge,
            orderID: "FINAL-RACE-ORDER",
            method: .bankCard,
            stage: .orderCreated
        )))
        let gateway = SuspendedFinalSubmitGateway()
        let coordinator = PaymentCoordinator(
            feature: .cardRecharge,
            gateway: gateway,
            pendingStore: store
        )
        let staleSubmit = Task { @MainActor in
            await coordinator.continuePendingOrder()
        }
        await gateway.waitUntilSubmitStarts()
        XCTAssertEqual(store.load()?.stage, .finalSubmissionStarted)

        await coordinator.cancel()
        await coordinator.resumePendingOrder()

        XCTAssertNil(store.load())
        let newerStatusSucceeded: Bool
        if case .succeeded = coordinator.phase {
            newerStatusSucceeded = true
        } else {
            newerStatusSucceeded = false
        }
        XCTAssertTrue(newerStatusSucceeded, "The newer status response must win")

        await gateway.releaseSubmit(.pending("旧提交响应"))
        _ = await staleSubmit.value

        XCTAssertNil(store.load())
        guard case .succeeded = coordinator.phase else {
            return XCTFail("A stale final response must not recreate pending state")
        }
        let submitCount = await gateway.submitCount
        let statusCount = await gateway.statusCount
        XCTAssertEqual(submitCount, 1)
        XCTAssertEqual(statusCount, 1)
    }

    func testCorruptRecordFailsClosedAcrossSubmitCancelAndReset() async throws {
        let fixture = makeStoreFixture()
        fixture.defaults.set(Data([0x00, 0x01, 0x02]), forKey: fixture.key)
        let gateway = CountingGuardGateway()
        let coordinator = PaymentCoordinator(
            feature: .cardRecharge,
            gateway: gateway,
            pendingStore: fixture.store
        )

        await coordinator.submit(try request(
            feature: .cardRecharge,
            method: .bankCard
        ))
        guard case .creationUnknown = coordinator.phase else {
            return XCTFail("Corrupt recovery state must lock payment")
        }
        await coordinator.cancel()
        guard case .creationUnknown = coordinator.phase else {
            return XCTFail("Cancel must not clear a corrupt recovery lock")
        }
        coordinator.reset()
        guard case .creationUnknown = coordinator.phase else {
            return XCTFail("Reset must not clear a corrupt recovery lock")
        }
        let createCount = await gateway.createCount
        XCTAssertEqual(createCount, 0)
        XCTAssertNotNil(fixture.defaults.data(forKey: fixture.key))
    }

    func testMismatchedFeatureRecordFailsClosed() async throws {
        let store = makePendingStore()
        XCTAssertTrue(store.save(PendingPayment(
            feature: .electricity,
            orderID: "EXISTING-ORDER",
            method: .campusAccount,
            stage: .resultUnknown
        )))
        let gateway = CountingGuardGateway()
        let coordinator = PaymentCoordinator(
            feature: .bathroom,
            gateway: gateway,
            pendingStore: store
        )

        await coordinator.submit(
            try request(feature: .bathroom, method: .campusAccount),
            authorization: try makeAuthorization()
        )

        guard case .creationUnknown = coordinator.phase else {
            return XCTFail("Feature mismatch must lock payment")
        }
        let createCount = await gateway.createCount
        XCTAssertEqual(createCount, 0)
        XCTAssertNotNil(store.load())
    }

    func testCancelAfterCreationRetainsRecoverableOrder() async {
        let store = makePendingStore()
        XCTAssertTrue(store.save(PendingPayment(
            feature: .bathroom,
            orderID: "RECOVERABLE-ORDER",
            method: .campusAccount,
            stage: .orderCreated
        )))
        let coordinator = PaymentCoordinator(
            feature: .bathroom,
            gateway: CountingGuardGateway(),
            pendingStore: store
        )

        await coordinator.cancel()
        coordinator.reset()

        XCTAssertEqual(store.load()?.stage, .orderCreated)
        guard case .awaitingConfirmation = coordinator.phase else {
            return XCTFail("Cancel/reset must keep a created order recoverable")
        }
    }

    func testExternalReturnCannotSkipFinalSubmissionForCampusAccountOrder() async {
        let store = makePendingStore()
        XCTAssertTrue(store.save(PendingPayment(
            feature: .electricity,
            orderID: "UNSUBMITTED-ORDER",
            method: .campusAccount,
            stage: .orderCreated
        )))
        let gateway = CountingGuardGateway()
        let coordinator = PaymentCoordinator(
            feature: .electricity,
            gateway: gateway,
            pendingStore: store
        )

        await coordinator.resumeExternalReturn()

        guard case .awaitingConfirmation = coordinator.phase else {
            return XCTFail("An unsubmitted order must still require confirmation")
        }
        let statusCount = await gateway.statusCount
        XCTAssertEqual(statusCount, 0)
        XCTAssertEqual(store.load()?.stage, .orderCreated)
    }

    private func assertStaleStatusCannotOverwriteConfirmation(
        _ staleStatus: PaymentOrderStatus
    ) async {
        let store = makePendingStore()
        XCTAssertTrue(store.save(PendingPayment(
            feature: .cardRecharge,
            orderID: "STATUS-RACE-ORDER",
            method: .bankCard,
            stage: .resultUnknown
        )))
        let gateway = OutOfOrderStatusGateway()
        let coordinator = PaymentCoordinator(
            feature: .cardRecharge,
            gateway: gateway,
            pendingStore: store
        )
        let staleRecovery = Task { @MainActor in
            await coordinator.resumePendingOrder()
        }
        await gateway.waitUntilFirstStatusStarts()

        await coordinator.cancel()
        await coordinator.resumeExternalReturn()

        XCTAssertNil(store.load())
        let newerStatusSucceeded: Bool
        if case .succeeded = coordinator.phase {
            newerStatusSucceeded = true
        } else {
            newerStatusSucceeded = false
        }
        XCTAssertTrue(
            newerStatusSucceeded,
            "The newer confirmed response must clear pending state"
        )

        await gateway.releaseFirstStatus(staleStatus)
        _ = await staleRecovery.value

        XCTAssertNil(store.load())
        guard case .succeeded = coordinator.phase else {
            return XCTFail("A stale status response must not overwrite success")
        }
        let statusCount = await gateway.statusCount
        XCTAssertEqual(statusCount, 2)
    }

    private func request(
        feature: PaymentFeature,
        method: PaymentMethod
    ) throws -> PaymentRequest {
        try PaymentRequest(
            feature: feature,
            method: method,
            amount: PaymentAmount("10.00"),
            accountID: "test-account",
            accountLabel: "测试账户",
            context: .demo
        )
    }

    private func makeCoordinator(
        feature: PaymentFeature,
        gateway: any PaymentGateway
    ) -> PaymentCoordinator {
        PaymentCoordinator(
            feature: feature,
            gateway: gateway,
            pendingStore: makePendingStore()
        )
    }

    private func makePendingStore() -> PendingPaymentStore {
        makeStoreFixture().store
    }

    private func makeStoreFixture() -> PaymentStoreFixture {
        let suite = "PaymentTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let key = "pending"
        return PaymentStoreFixture(
            suite: suite,
            key: key,
            defaults: defaults,
            store: PendingPaymentStore(defaults: defaults, key: key)
        )
    }
}

@MainActor
final class PendingPaymentStoreTests: XCTestCase {
    func testLegacyOrderRecordMigratesToUnknownWithoutLosingOrderID() throws {
        let suite = "PendingPaymentLegacyTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let key = "pending"
        defaults.set(
            try JSONSerialization.data(withJSONObject: [
                "feature": PaymentFeature.bathroom.rawValue,
                "orderID": "LEGACY-ORDER"
            ]),
            forKey: key
        )
        let store = PendingPaymentStore(defaults: defaults, key: key)

        let pending = try XCTUnwrap(store.load())
        XCTAssertEqual(pending.version, PendingPayment.currentVersion)
        XCTAssertEqual(pending.stage, .resultUnknown)
        XCTAssertEqual(pending.orderID, "LEGACY-ORDER")
    }

    func testLegacyPreCreateMarkerFailsClosed() {
        let suite = "PendingPaymentLegacySubmissionTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let key = "pending"
        defaults.set(Data([0x01]), forKey: "\(key).submission")
        let store = PendingPaymentStore(defaults: defaults, key: key)

        XCTAssertEqual(store.loadResult(), .corrupt)
    }

    func testInvalidStageAndOrderCombinationCannotBeSaved() {
        let suite = "PendingPaymentInvalidTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let store = PendingPaymentStore(defaults: defaults, key: "pending")

        XCTAssertFalse(store.save(PendingPayment(
            feature: .networkRecharge,
            orderID: nil,
            method: .campusAccount,
            stage: .resultUnknown
        )))
        XCTAssertFalse(store.save(PendingPayment(
            feature: .bathroom,
            orderID: "MUST-NOT-EXIST",
            method: .campusAccount,
            stage: .creating
        )))
        XCTAssertFalse(store.save(PendingPayment(
            feature: .cardRecharge,
            orderID: "INVALID ORDER",
            method: .bankCard,
            stage: .orderCreated
        )))
    }

    func testDurableStoreSurvivesReconstructionWithOpaqueMinimalLog() throws {
        let fixture = makeDurableFixture(
            key: "payments.pending-order.student-identifier.bathroom"
        )
        defer { fixture.cleanup() }
        let pending = PendingPayment(
            feature: .bathroom,
            orderID: "DURABLE-ORDER",
            method: .campusAccount,
            stage: .orderCreated
        )
        let first = fixture.makeStore()

        XCTAssertTrue(first.save(pending))

        let files = try FileManager.default.contentsOfDirectory(
            at: fixture.directoryURL,
            includingPropertiesForKeys: [.isExcludedFromBackupKey]
        )
        let logs = files.filter { $0.pathExtension == "json" }
        XCTAssertEqual(logs.count, 1)
        let logURL = try XCTUnwrap(logs.first)
        XCTAssertFalse(logURL.lastPathComponent.contains("student-identifier"))
        XCTAssertEqual(
            try logURL.resourceValues(
                forKeys: [.isExcludedFromBackupKey]
            ).isExcludedFromBackup,
            true
        )
        let data = try Data(contentsOf: logURL, options: .uncached)
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        XCTAssertEqual(
            Set(object.keys),
            Set(["version", "feature", "orderID", "method", "stage"])
        )
        for forbiddenKey in [
            "password", "passwordMap", "mappedPassword", "requestBody",
            "authorization", "context", "amount", "accountID"
        ] {
            XCTAssertNil(object[forbiddenKey])
        }

        let reconstructed = fixture.makeStore(reconstructDefaults: true)
        XCTAssertEqual(reconstructed.loadResult(), .value(pending))
    }

    func testAtomicWriteFailurePreservesPreviousDurableRecord() throws {
        let fixture = makeDurableFixture()
        defer { fixture.cleanup() }
        let previous = PendingPayment(
            feature: .cardRecharge,
            orderID: nil,
            method: .bankCard,
            stage: .creating
        )
        let replacement = PendingPayment(
            feature: .cardRecharge,
            orderID: "REPLACEMENT-ORDER",
            method: .bankCard,
            stage: .orderCreated
        )
        XCTAssertTrue(fixture.makeStore().save(previous))
        let failingStore = fixture.makeStore(writeFault: .beforeRename)

        XCTAssertFalse(failingStore.save(replacement))

        XCTAssertEqual(
            fixture.makeStore(reconstructDefaults: true).loadResult(),
            .value(previous)
        )
        let files = try FileManager.default.contentsOfDirectory(
            at: fixture.directoryURL,
            includingPropertiesForKeys: nil
        )
        XCTAssertFalse(files.contains { $0.pathExtension == "tmp" })
    }

    func testLegacyRecordMigratesOnlyAfterDurableVerification() throws {
        let fixture = makeDurableFixture()
        defer { fixture.cleanup() }
        fixture.defaults.set(
            try JSONSerialization.data(withJSONObject: [
                "feature": PaymentFeature.bathroom.rawValue,
                "orderID": "LEGACY-DURABLE-ORDER"
            ]),
            forKey: fixture.key
        )
        fixture.defaults.set(Data([0x01]), forKey: "\(fixture.key).submission")
        let store = fixture.makeStore()

        guard case let .value(migrated) = store.loadResult() else {
            return XCTFail("A valid legacy order must migrate durably")
        }
        XCTAssertEqual(migrated.stage, .resultUnknown)
        XCTAssertEqual(migrated.orderID, "LEGACY-DURABLE-ORDER")
        XCTAssertNil(fixture.defaults.object(forKey: fixture.key))
        XCTAssertNil(fixture.defaults.object(forKey: "\(fixture.key).submission"))
        XCTAssertEqual(
            fixture.makeStore(reconstructDefaults: true).loadResult(),
            .value(migrated)
        )
    }

    func testFailedLegacyMigrationKeepsLegacyValuesAndLocks() throws {
        let fixture = makeDurableFixture()
        defer { fixture.cleanup() }
        let legacy = PendingPayment(
            feature: .electricity,
            orderID: nil,
            method: .campusAccount,
            stage: .creating
        )
        fixture.defaults.set(
            try JSONEncoder().encode(legacy),
            forKey: fixture.key
        )
        fixture.defaults.set(Data([0x01]), forKey: "\(fixture.key).submission")

        XCTAssertEqual(
            fixture.makeStore(writeFault: .beforeRename).loadResult(),
            .corrupt
        )
        XCTAssertNotNil(fixture.defaults.object(forKey: fixture.key))
        XCTAssertNotNil(
            fixture.defaults.object(forKey: "\(fixture.key).submission")
        )

        XCTAssertEqual(fixture.makeStore().loadResult(), .value(legacy))
        XCTAssertNil(fixture.defaults.object(forKey: fixture.key))
        XCTAssertNil(fixture.defaults.object(forKey: "\(fixture.key).submission"))
    }

    func testNestedDirectorySyncFailureKeepsLegacyLockUntilRetry() throws {
        let fixture = makeDurableFixture()
        defer { fixture.cleanup() }
        let legacy = PendingPayment(
            feature: .networkRecharge,
            orderID: nil,
            method: .campusAccount,
            stage: .creating
        )
        fixture.defaults.set(
            try JSONEncoder().encode(legacy),
            forKey: fixture.key
        )

        // For the two initially missing directory levels, attempts 1/2 sync
        // the first level and its stable parent; attempts 3/4 sync the second
        // level and the first-level parent. Failure at #4 proves migration
        // cannot proceed until that second parent entry is durable.
        XCTAssertEqual(
            fixture.makeStore(
                writeFault: .directorySynchronization(4)
            ).loadResult(),
            .corrupt
        )
        XCTAssertNotNil(fixture.defaults.object(forKey: fixture.key))
        let filesAfterFailure = try FileManager.default.contentsOfDirectory(
            at: fixture.directoryURL,
            includingPropertiesForKeys: nil
        )
        XCTAssertFalse(filesAfterFailure.contains { $0.pathExtension == "json" })

        let migratedStore = fixture.makeStore()
        XCTAssertEqual(migratedStore.loadResult(), .value(legacy))
        XCTAssertNil(fixture.defaults.object(forKey: fixture.key))
        XCTAssertEqual(
            fixture.makeStore(reconstructDefaults: true).loadResult(),
            .value(legacy)
        )
    }

    func testLegacySubmissionAndCorruptDataRemainFailClosed() throws {
        let submissionFixture = makeDurableFixture(key: "submission-lock")
        defer { submissionFixture.cleanup() }
        submissionFixture.defaults.set(
            Data([0x01]),
            forKey: "\(submissionFixture.key).submission"
        )
        XCTAssertEqual(
            submissionFixture.makeStore().loadResult(),
            .corrupt
        )
        XCTAssertNotNil(
            submissionFixture.defaults.object(
                forKey: "\(submissionFixture.key).submission"
            )
        )

        let corruptFixture = makeDurableFixture(key: "corrupt-lock")
        defer { corruptFixture.cleanup() }
        corruptFixture.defaults.set(Data([0x00]), forKey: corruptFixture.key)
        XCTAssertEqual(corruptFixture.makeStore().loadResult(), .corrupt)
        XCTAssertNotNil(corruptFixture.defaults.object(forKey: corruptFixture.key))
    }

    func testDurableClearSurvivesStoreReconstruction() throws {
        let fixture = makeDurableFixture()
        defer { fixture.cleanup() }
        let pending = PendingPayment(
            feature: .networkRecharge,
            orderID: "CLEAR-ORDER",
            method: .campusAccount,
            stage: .resultUnknown
        )
        let store = fixture.makeStore()
        XCTAssertTrue(store.save(pending))
        fixture.defaults.set(Data([0x01]), forKey: "\(fixture.key).submission")

        store.clear()

        XCTAssertEqual(
            fixture.makeStore(reconstructDefaults: true).loadResult(),
            .empty
        )
        XCTAssertNil(fixture.defaults.object(forKey: "\(fixture.key).submission"))
        let files = try FileManager.default.contentsOfDirectory(
            at: fixture.directoryURL,
            includingPropertiesForKeys: nil
        )
        XCTAssertFalse(files.contains { $0.pathExtension == "json" })
    }

    private func makeDurableFixture(
        key: String = "payments.pending-order.test"
    ) -> DurablePaymentStoreFixture {
        let suite = "DurablePaymentStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let rootURL = FileManager.default.temporaryDirectory.appendingPathComponent(
            "AHUTongPaymentStoreTests-\(UUID().uuidString)",
            isDirectory: true
        )
        return DurablePaymentStoreFixture(
            suite: suite,
            key: key,
            defaults: defaults,
            rootURL: rootURL,
            directoryURL: rootURL.appendingPathComponent(
                "transactions",
                isDirectory: true
            )
        )
    }
}

final class PaymentCatalogTests: XCTestCase {
    func testCardRechargeFixtureUsesNonProductionAccountAndBalance() {
        XCTAssertTrue(PaymentDemoCatalog.cardAccountID.hasPrefix("mock-"))
        XCTAssertEqual(PaymentDemoCatalog.cardBalance, Decimal(string: "126.35"))
    }

    func testBathroomFixtureKeepsPhoneLookupAndDistinctAccounts() {
        XCTAssertEqual(PaymentDemoCatalog.phone.count, 11)
        XCTAssertEqual(
            Set(PaymentDemoCatalog.bathrooms.map(\.id)).count,
            PaymentDemoCatalog.bathrooms.count
        )
    }

    func testElectricityFixtureProvidesCompleteSelectionPath() {
        XCTAssertFalse(PaymentDemoCatalog.electricityRooms.isEmpty)
        XCTAssertTrue(PaymentDemoCatalog.electricityRooms.allSatisfy {
            !$0.campus.isEmpty
                && !$0.building.isEmpty
                && !$0.floor.isEmpty
                && !$0.room.isEmpty
        })
    }
}

private struct PaymentStoreFixture {
    let suite: String
    let key: String
    let defaults: UserDefaults
    let store: PendingPaymentStore
}

@MainActor
private struct DurablePaymentStoreFixture {
    let suite: String
    let key: String
    let defaults: UserDefaults
    let rootURL: URL
    let directoryURL: URL

    func makeStore(
        reconstructDefaults: Bool = false,
        writeFault: PendingPaymentStoreWriteFault = .none
    ) -> PendingPaymentStore {
        let resolvedDefaults = reconstructDefaults
            ? UserDefaults(suiteName: suite)!
            : defaults
        return PendingPaymentStore(
            durableDirectoryURL: directoryURL,
            durabilityAnchorURL: rootURL.deletingLastPathComponent(),
            legacyDefaults: resolvedDefaults,
            key: key,
            writeFault: writeFault
        )
    }

    func cleanup() {
        try? FileManager.default.removeItem(at: rootURL)
        defaults.removePersistentDomain(forName: suite)
    }
}

private final class TestPreparedConfirmation:
    PreparedPaymentConfirmation,
    @unchecked Sendable
{
    let orderID: String
    private let lock = NSLock()
    private var cleared = false

    init(orderID: String) {
        self.orderID = orderID
    }

    func clear() {
        lock.withLock { cleared = true }
    }

    var isAvailable: Bool {
        lock.withLock { !cleared }
    }
}

private actor LostCreateResponseGateway: PaymentGateway {
    private(set) var createCount = 0

    func createOrder(
        request: PaymentRequest,
        idempotencyKey: String
    ) async throws -> PaymentOrder {
        createCount += 1
        throw URLError(.networkConnectionLost)
    }

    func prepareConfirmation(
        orderID: String,
        feature: PaymentFeature,
        method: PaymentMethod,
        authorization: TransientPaymentAuthorization?
    ) async throws -> any PreparedPaymentConfirmation {
        authorization?.clear()
        throw PaymentGatewayError.invalidResponse
    }

    func submitPreparedConfirmation(
        _ prepared: any PreparedPaymentConfirmation
    ) async throws -> PaymentOrderStatus {
        prepared.clear()
        throw PaymentGatewayError.invalidResponse
    }

    func status(
        orderID: String,
        feature: PaymentFeature,
        method: PaymentMethod
    ) async throws -> PaymentOrderStatus {
        .unknown("待确认")
    }
}

private actor RecoverablePreparedGateway: PaymentGateway {
    private(set) var createCount = 0
    private(set) var prepareCount = 0
    private(set) var submitCount = 0

    func createOrder(
        request: PaymentRequest,
        idempotencyKey: String
    ) async throws -> PaymentOrder {
        createCount += 1
        return PaymentOrder(id: "RECOVERABLE-ORDER", externalURL: nil)
    }

    func prepareConfirmation(
        orderID: String,
        feature: PaymentFeature,
        method: PaymentMethod,
        authorization: TransientPaymentAuthorization?
    ) async throws -> any PreparedPaymentConfirmation {
        prepareCount += 1
        try consumeAndWipe(authorization)
        if prepareCount == 1 {
            throw PaymentGatewayError.server("准备信息暂不可用")
        }
        return TestPreparedConfirmation(orderID: orderID)
    }

    func submitPreparedConfirmation(
        _ prepared: any PreparedPaymentConfirmation
    ) async throws -> PaymentOrderStatus {
        guard let prepared = prepared as? TestPreparedConfirmation,
              prepared.isAvailable else {
            throw PaymentGatewayError.invalidResponse
        }
        submitCount += 1
        return .pending("等待核验")
    }

    func status(
        orderID: String,
        feature: PaymentFeature,
        method: PaymentMethod
    ) async throws -> PaymentOrderStatus {
        .confirmed("已确认")
    }
}

private actor FinalResponseLostGateway: PaymentGateway {
    private(set) var createCount = 0
    private(set) var prepareCount = 0
    private(set) var submitCount = 0
    private(set) var statusCount = 0

    func createOrder(
        request: PaymentRequest,
        idempotencyKey: String
    ) async throws -> PaymentOrder {
        createCount += 1
        return PaymentOrder(id: "FINAL-UNKNOWN-ORDER", externalURL: nil)
    }

    func prepareConfirmation(
        orderID: String,
        feature: PaymentFeature,
        method: PaymentMethod,
        authorization: TransientPaymentAuthorization?
    ) async throws -> any PreparedPaymentConfirmation {
        prepareCount += 1
        try consumeAndWipe(authorization)
        return TestPreparedConfirmation(orderID: orderID)
    }

    func submitPreparedConfirmation(
        _ prepared: any PreparedPaymentConfirmation
    ) async throws -> PaymentOrderStatus {
        submitCount += 1
        throw PaymentGatewayError.timedOut
    }

    func status(
        orderID: String,
        feature: PaymentFeature,
        method: PaymentMethod
    ) async throws -> PaymentOrderStatus {
        statusCount += 1
        return .unknown("待确认")
    }
}

private actor FinalStageObservingGateway: PaymentGateway {
    private let suiteName: String
    private let key: String
    private(set) var observedFinalSubmissionStage = false

    init(suiteName: String, key: String) {
        self.suiteName = suiteName
        self.key = key
    }

    func createOrder(
        request: PaymentRequest,
        idempotencyKey: String
    ) async throws -> PaymentOrder {
        PaymentOrder(id: "ORDERING-ORDER", externalURL: nil)
    }

    func prepareConfirmation(
        orderID: String,
        feature: PaymentFeature,
        method: PaymentMethod,
        authorization: TransientPaymentAuthorization?
    ) async throws -> any PreparedPaymentConfirmation {
        TestPreparedConfirmation(orderID: orderID)
    }

    func submitPreparedConfirmation(
        _ prepared: any PreparedPaymentConfirmation
    ) async throws -> PaymentOrderStatus {
        let defaults = UserDefaults(suiteName: suiteName)
        if let data = defaults?.data(forKey: key),
           let pending = try? JSONDecoder().decode(PendingPayment.self, from: data) {
            observedFinalSubmissionStage = pending.stage == .finalSubmissionStarted
        }
        return .pending("等待核验")
    }

    func status(
        orderID: String,
        feature: PaymentFeature,
        method: PaymentMethod
    ) async throws -> PaymentOrderStatus {
        .confirmed("已确认")
    }
}

private actor SuspendedCreateGateway: PaymentGateway {
    private(set) var createCount = 0
    private var createStarted = false
    private var startWaiters: [CheckedContinuation<Void, Never>] = []
    private var releaseContinuation: CheckedContinuation<Void, Never>?

    func createOrder(
        request: PaymentRequest,
        idempotencyKey: String
    ) async throws -> PaymentOrder {
        createCount += 1
        createStarted = true
        let waiters = startWaiters
        startWaiters.removeAll(keepingCapacity: false)
        waiters.forEach { $0.resume() }
        await withCheckedContinuation { continuation in
            releaseContinuation = continuation
        }
        return PaymentOrder(id: "SUSPENDED-ORDER", externalURL: nil)
    }

    func prepareConfirmation(
        orderID: String,
        feature: PaymentFeature,
        method: PaymentMethod,
        authorization: TransientPaymentAuthorization?
    ) async throws -> any PreparedPaymentConfirmation {
        try consumeAndWipe(authorization)
        return TestPreparedConfirmation(orderID: orderID)
    }

    func submitPreparedConfirmation(
        _ prepared: any PreparedPaymentConfirmation
    ) async throws -> PaymentOrderStatus {
        .pending("等待核验")
    }

    func status(
        orderID: String,
        feature: PaymentFeature,
        method: PaymentMethod
    ) async throws -> PaymentOrderStatus {
        .confirmed("已确认")
    }

    func waitUntilCreateStarts() async {
        guard !createStarted else { return }
        await withCheckedContinuation { continuation in
            startWaiters.append(continuation)
        }
    }

    func releaseCreate() {
        releaseContinuation?.resume()
        releaseContinuation = nil
    }
}

private actor OutOfOrderStatusGateway: PaymentGateway {
    private(set) var statusCount = 0
    private var firstStatusStarted = false
    private var startWaiters: [CheckedContinuation<Void, Never>] = []
    private var firstStatusContinuation:
        CheckedContinuation<PaymentOrderStatus, Never>?

    func createOrder(
        request: PaymentRequest,
        idempotencyKey: String
    ) async throws -> PaymentOrder {
        throw PaymentGatewayError.featureMismatch
    }

    func prepareConfirmation(
        orderID: String,
        feature: PaymentFeature,
        method: PaymentMethod,
        authorization: TransientPaymentAuthorization?
    ) async throws -> any PreparedPaymentConfirmation {
        authorization?.clear()
        throw PaymentGatewayError.featureMismatch
    }

    func submitPreparedConfirmation(
        _ prepared: any PreparedPaymentConfirmation
    ) async throws -> PaymentOrderStatus {
        prepared.clear()
        throw PaymentGatewayError.featureMismatch
    }

    func status(
        orderID: String,
        feature: PaymentFeature,
        method: PaymentMethod
    ) async throws -> PaymentOrderStatus {
        statusCount += 1
        guard statusCount == 1 else {
            return .confirmed("新查询已确认")
        }
        return await withCheckedContinuation { continuation in
            firstStatusContinuation = continuation
            firstStatusStarted = true
            let waiters = startWaiters
            startWaiters.removeAll(keepingCapacity: false)
            waiters.forEach { $0.resume() }
        }
    }

    func waitUntilFirstStatusStarts() async {
        guard !firstStatusStarted else { return }
        await withCheckedContinuation { continuation in
            startWaiters.append(continuation)
        }
    }

    func releaseFirstStatus(_ status: PaymentOrderStatus) {
        firstStatusContinuation?.resume(returning: status)
        firstStatusContinuation = nil
    }
}

private actor SuspendedFinalSubmitGateway: PaymentGateway {
    private(set) var prepareCount = 0
    private(set) var submitCount = 0
    private(set) var statusCount = 0
    private var submitStarted = false
    private var startWaiters: [CheckedContinuation<Void, Never>] = []
    private var submitContinuation:
        CheckedContinuation<PaymentOrderStatus, Never>?

    func createOrder(
        request: PaymentRequest,
        idempotencyKey: String
    ) async throws -> PaymentOrder {
        throw PaymentGatewayError.featureMismatch
    }

    func prepareConfirmation(
        orderID: String,
        feature: PaymentFeature,
        method: PaymentMethod,
        authorization: TransientPaymentAuthorization?
    ) async throws -> any PreparedPaymentConfirmation {
        authorization?.clear()
        prepareCount += 1
        return TestPreparedConfirmation(orderID: orderID)
    }

    func submitPreparedConfirmation(
        _ prepared: any PreparedPaymentConfirmation
    ) async throws -> PaymentOrderStatus {
        submitCount += 1
        return await withCheckedContinuation { continuation in
            submitContinuation = continuation
            submitStarted = true
            let waiters = startWaiters
            startWaiters.removeAll(keepingCapacity: false)
            waiters.forEach { $0.resume() }
        }
    }

    func status(
        orderID: String,
        feature: PaymentFeature,
        method: PaymentMethod
    ) async throws -> PaymentOrderStatus {
        statusCount += 1
        return .confirmed("新查询已确认")
    }

    func waitUntilSubmitStarts() async {
        guard !submitStarted else { return }
        await withCheckedContinuation { continuation in
            startWaiters.append(continuation)
        }
    }

    func releaseSubmit(_ status: PaymentOrderStatus) {
        submitContinuation?.resume(returning: status)
        submitContinuation = nil
    }
}

private actor CountingGuardGateway: PaymentGateway {
    private(set) var createCount = 0
    private(set) var statusCount = 0

    func createOrder(
        request: PaymentRequest,
        idempotencyKey: String
    ) async throws -> PaymentOrder {
        createCount += 1
        return PaymentOrder(id: "UNEXPECTED-ORDER", externalURL: nil)
    }

    func prepareConfirmation(
        orderID: String,
        feature: PaymentFeature,
        method: PaymentMethod,
        authorization: TransientPaymentAuthorization?
    ) async throws -> any PreparedPaymentConfirmation {
        authorization?.clear()
        return TestPreparedConfirmation(orderID: orderID)
    }

    func submitPreparedConfirmation(
        _ prepared: any PreparedPaymentConfirmation
    ) async throws -> PaymentOrderStatus {
        .unknown("不应调用")
    }

    func status(
        orderID: String,
        feature: PaymentFeature,
        method: PaymentMethod
    ) async throws -> PaymentOrderStatus {
        statusCount += 1
        return .unknown("待确认")
    }
}

private func makeAuthorization() throws -> TransientPaymentAuthorization {
    try TransientPaymentAuthorization(digits: "246810")
}

private func consumeAndWipe(
    _ authorization: TransientPaymentAuthorization?
) throws {
    guard let authorization else {
        throw PaymentValidationError.invalidPassword
    }
    var bytes = try authorization.consumeASCIIBytes()
    defer { wipe(&bytes) }
    guard bytes.count == 6 else {
        throw PaymentValidationError.invalidPassword
    }
}

private func wipe(_ bytes: inout ContiguousArray<UInt8>) {
    for index in bytes.indices {
        bytes[index] = 0
    }
}
