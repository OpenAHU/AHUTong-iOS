import Foundation
import SwiftUI

struct CampusPaymentPasswordEntry: Equatable {
    static let validationMessage = "密码必须是6位数字"

    private(set) var value = ""
    private(set) var inlineError: String?

    mutating func update(_ input: String) {
        value = String(input.filter(\.isNumber).prefix(6))
        inlineError = nil
    }

    @discardableResult
    mutating func validate() -> Bool {
        guard value.count == 6, value.allSatisfy(\.isNumber) else {
            inlineError = Self.validationMessage
            return false
        }
        inlineError = nil
        return true
    }

    mutating func reset() {
        value = ""
        inlineError = nil
    }
}

struct ElectricityChargeRecord: Codable, Equatable, Sendable {
    var totalAmount: Decimal
    let firstChargeDate: Date
}

@MainActor
final class ElectricityChargeHistoryStore {
    private let defaults: UserDefaults
    private let key: String

    init(userID: String, defaults: UserDefaults = .standard) {
        self.defaults = defaults
        key = AccountPreferenceKey.make(
            "payment.electricity-charge-history.v1",
            userID: userID
        )
    }

    func load() -> ElectricityChargeRecord? {
        defaults.data(forKey: key).flatMap {
            try? JSONDecoder().decode(ElectricityChargeRecord.self, from: $0)
        }
    }

    func save(_ record: ElectricityChargeRecord) {
        guard let data = try? JSONEncoder().encode(record) else { return }
        defaults.set(data, forKey: key)
    }

    func clear() {
        defaults.removeObject(forKey: key)
    }
}

@MainActor
final class ElectricityChargeHistoryModel: ObservableObject {
    @Published private(set) var record: ElectricityChargeRecord?
    @Published private(set) var feedback: String?
    private(set) var infoTapCount = 0

    private let store: ElectricityChargeHistoryStore

    init(userID: String, defaults: UserDefaults = .standard) {
        let store = ElectricityChargeHistoryStore(userID: userID, defaults: defaults)
        self.store = store
        record = store.load()
    }

    func revealInfo() {
        infoTapCount += 1
        feedback = switch infoTapCount {
        case 1:
            "点击五次查看累计充值记录，长按清空记录"
        case 2:
            "再点击三次即可查看累计充值记录"
        case 3:
            "再点击两次即可查看累计充值记录"
        case 4:
            "再点击一次即可查看累计充值记录"
        default:
            record.map(Self.summary) ?? "暂无充值记录"
        }
    }

    func record(
        amount: PaymentAmount,
        after phase: PaymentPhase,
        at date: Date = .now
    ) {
        guard case .succeeded = phase else { return }
        if var existing = record {
            existing.totalAmount += amount.value
            record = existing
        } else {
            record = ElectricityChargeRecord(
                totalAmount: amount.value,
                firstChargeDate: date
            )
        }
        if let record {
            store.save(record)
        }
    }

    func clear() {
        store.clear()
        record = nil
        feedback = "累计记录已清零"
    }

    func dismissFeedback(ifMatching message: String) {
        guard feedback == message else { return }
        feedback = nil
    }

    private static func summary(_ record: ElectricityChargeRecord) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy年MM月dd日"
        let firstDate = formatter.string(from: record.firstChargeDate)
        let amount = String(
            format: "%.2f",
            NSDecimalNumber(decimal: record.totalAmount).doubleValue
        )
        return "从\(firstDate)起累计电费充值金额为：\(amount)元"
    }
}
