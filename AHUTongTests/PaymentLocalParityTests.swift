import Foundation
import XCTest
@testable import AHUTong

final class CampusPaymentPasswordEntryTests: XCTestCase {
    func testInvalidPasswordKeepsInlineErrorUntilInputChanges() {
        var entry = CampusPaymentPasswordEntry()
        entry.update("12a345")

        XCTAssertEqual(entry.value, "12345")
        XCTAssertFalse(entry.validate())
        XCTAssertEqual(
            entry.inlineError,
            CampusPaymentPasswordEntry.validationMessage
        )

        entry.update("1234567")
        XCTAssertEqual(entry.value, "123456")
        XCTAssertNil(entry.inlineError)
        XCTAssertTrue(entry.validate())
    }

    func testResetRemovesTransientPasswordAndError() {
        var entry = CampusPaymentPasswordEntry()
        entry.update("123")
        XCTAssertFalse(entry.validate())

        entry.reset()

        XCTAssertEqual(entry.value, "")
        XCTAssertNil(entry.inlineError)
    }
}

final class ElectricityChargeHistoryModelTests: XCTestCase {
    @MainActor
    func testHistoryPersistsFirstDateAndAccumulatesConfirmedAmounts() throws {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let firstDate = Date(timeIntervalSince1970: 1_735_776_000)
        let model = ElectricityChargeHistoryModel(
            userID: "student-a",
            defaults: defaults
        )

        model.record(
            amount: try PaymentAmount("12.34"),
            after: .succeeded("ORDER-1", "服务端已确认"),
            at: firstDate
        )
        model.record(
            amount: try PaymentAmount("7.66"),
            after: .succeeded("ORDER-2", "服务端已确认"),
            at: firstDate.addingTimeInterval(86_400)
        )

        XCTAssertEqual(model.record?.totalAmount, Decimal(string: "20.00"))
        XCTAssertEqual(model.record?.firstChargeDate, firstDate)

        let restored = ElectricityChargeHistoryModel(
            userID: "student-a",
            defaults: defaults
        )
        XCTAssertEqual(restored.record, model.record)
    }

    @MainActor
    func testHistoryIsIsolatedByAccountAndClearIsPersistent() throws {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let first = ElectricityChargeHistoryModel(
            userID: "student-a",
            defaults: defaults
        )
        first.record(
            amount: try PaymentAmount("10"),
            after: .succeeded("ORDER-1", "服务端已确认")
        )

        let second = ElectricityChargeHistoryModel(
            userID: "student-b",
            defaults: defaults
        )
        XCTAssertNil(second.record)

        first.clear()
        XCTAssertNil(first.record)
        XCTAssertEqual(first.feedback, "累计记录已清零")
        XCTAssertNil(
            ElectricityChargeHistoryModel(
                userID: "student-a",
                defaults: defaults
            ).record
        )
    }

    @MainActor
    func testFifthInfoTapRevealsHistoryOrNoRecord() throws {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let model = ElectricityChargeHistoryModel(
            userID: "student-a",
            defaults: defaults
        )

        model.revealInfo()
        XCTAssertEqual(model.feedback, "点击五次查看累计充值记录，长按清空记录")
        model.revealInfo()
        XCTAssertEqual(model.feedback, "再点击三次即可查看累计充值记录")
        model.revealInfo()
        XCTAssertEqual(model.feedback, "再点击两次即可查看累计充值记录")
        model.revealInfo()
        XCTAssertEqual(model.feedback, "再点击一次即可查看累计充值记录")
        model.revealInfo()
        XCTAssertEqual(model.feedback, "暂无充值记录")

        model.record(
            amount: try PaymentAmount("20"),
            after: .succeeded("ORDER-1", "服务端已确认"),
            at: Date(timeIntervalSince1970: 1_735_776_000)
        )
        model.revealInfo()

        XCTAssertTrue(model.feedback?.hasPrefix("从") == true)
        XCTAssertTrue(
            model.feedback?.contains("累计电费充值金额为：20.00元") == true
        )
    }

    @MainActor
    func testUnconfirmedPaymentNeverChangesHistory() throws {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let model = ElectricityChargeHistoryModel(
            userID: "student-a",
            defaults: defaults
        )
        let amount = try PaymentAmount("20")

        model.record(amount: amount, after: .creating)
        model.record(amount: amount, after: .failed("未确认"))
        model.record(amount: amount, after: .unknown("ORDER-1", "待确认"))

        XCTAssertNil(model.record)
    }

    @MainActor
    private func makeDefaults() -> (UserDefaults, String) {
        let suiteName = "ElectricityChargeHistoryModelTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return (defaults, suiteName)
    }
}
