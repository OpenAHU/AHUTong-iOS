import CryptoKit
import Foundation
import SwiftUI

enum PaymentFeature: String, Codable, CaseIterable, Sendable {
    case cardRecharge
    case bathroom
    case electricity

    var displayName: String {
        switch self {
        case .cardRecharge: "校园卡充值"
        case .bathroom: "浴室缴费"
        case .electricity: "电控缴费"
        }
    }
}

enum PaymentMethod: String, Codable, Sendable {
    case bankCard
    case alipay
    case campusAccount
}

enum PaymentValidationError: LocalizedError, Equatable {
    case missingAmount
    case invalidAmount
    case tooManyFractionDigits
    case exceedsLimit
    case missingAccount
    case invalidPassword

    var errorDescription: String? {
        switch self {
        case .missingAmount: "请输入缴费金额"
        case .invalidAmount: "请输入有效金额"
        case .tooManyFractionDigits: "金额最多保留两位小数"
        case .exceedsLimit: "单次金额不能超过 500 元"
        case .missingAccount: "请先选择缴费账户"
        case .invalidPassword: "密码必须是 6 位数字"
        }
    }
}

struct PaymentAmount: Equatable, Sendable {
    let value: Decimal

    init(_ rawValue: String) throws {
        let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { throw PaymentValidationError.missingAmount }
        guard value.range(of: #"^\d+(\.\d{0,2})?$"#, options: .regularExpression) != nil else {
            if value.range(of: #"^\d+\.\d{3,}$"#, options: .regularExpression) != nil {
                throw PaymentValidationError.tooManyFractionDigits
            }
            throw PaymentValidationError.invalidAmount
        }
        guard let amount = Decimal(string: value, locale: Locale(identifier: "en_US_POSIX")), amount > 0 else {
            throw PaymentValidationError.invalidAmount
        }
        guard amount <= 500 else { throw PaymentValidationError.exceedsLimit }
        self.value = amount
    }

    var text: String {
        let number = NSDecimalNumber(decimal: value)
        return String(format: "%.2f", number.doubleValue)
    }
}

struct PaymentRequest: Equatable, Sendable {
    let feature: PaymentFeature
    let method: PaymentMethod
    let amount: PaymentAmount
    let accountID: String
    let accountLabel: String
    let authorization: String?

    init(
        feature: PaymentFeature,
        method: PaymentMethod,
        amount: PaymentAmount,
        accountID: String,
        accountLabel: String,
        authorization: String? = nil
    ) throws {
        guard !accountID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw PaymentValidationError.missingAccount
        }
        if method == .campusAccount {
            guard let authorization,
                  authorization.count == 6,
                  authorization.allSatisfy({ $0.isNumber }) else {
                throw PaymentValidationError.invalidPassword
            }
        }
        self.feature = feature
        self.method = method
        self.amount = amount
        self.accountID = accountID
        self.accountLabel = accountLabel
        self.authorization = authorization
    }
}

struct PaymentOrder: Equatable, Sendable {
    let id: String
    let externalURL: URL?
}

enum PaymentOrderStatus: Equatable, Sendable {
    case pending(String)
    case confirmed(String)
    case rejected(String)
    case unknown(String)
}

enum PaymentGatewayError: LocalizedError, Equatable {
    case safetyServiceUnavailable
    case timedOut
    case invalidResponse
    case featureMismatch
    case server(String)

    var errorDescription: String? {
        switch self {
        case .safetyServiceUnavailable: "学校支付安全服务尚未配置，未发起任何扣款"
        case .timedOut: "支付请求超时，请先查询订单结果，勿重复提交"
        case .invalidResponse: "支付服务返回了无法识别的结果"
        case .featureMismatch: "支付请求与当前功能不匹配"
        case let .server(message): message
        }
    }
}

enum OfficialSchoolPaymentPortal {
    private static let loginEndpoint = URL(
        string: "https://ycard.ahu.edu.cn/berserker-auth/cas/redirect/neusoftCas"
    )!
    private static let portalTarget = URL(
        string: "https://ycard.ahu.edu.cn/plat/?name=loginTransit"
    )!

    static var loginURL: URL {
        var components = URLComponents(
            url: loginEndpoint,
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = [
            URLQueryItem(name: "targetUrl", value: portalTarget.absoluteString)
        ]
        return components.url!
    }
}

protocol PaymentGateway: Sendable {
    func createOrder(request: PaymentRequest, idempotencyKey: String) async throws -> PaymentOrder
    func confirm(orderID: String, authorization: String?) async throws -> PaymentOrderStatus
    func status(orderID: String) async throws -> PaymentOrderStatus
    func cancel(orderID: String) async
}

enum PaymentPhase: Equatable {
    case idle
    case creating
    case confirming(String)
    case awaitingExternal(String)
    case reconciling(String)
    case succeeded(String, String)
    case failed(String)
    case cancelled
    case unknown(String, String)

    var isBusy: Bool {
        switch self {
        case .creating, .confirming, .awaitingExternal, .reconciling: true
        default: false
        }
    }
}

struct PendingPayment: Codable, Equatable {
    let feature: PaymentFeature
    let orderID: String
}

struct PendingPaymentSubmission: Codable, Equatable {
    let feature: PaymentFeature
    let idempotencyKey: String
    let requestFingerprint: String
}

@MainActor
final class PendingPaymentStore {
    private let defaults: UserDefaults
    private let key: String

    private var submissionKey: String { "\(key).submission" }

    init(defaults: UserDefaults = .standard, key: String = "payments.pending-order") {
        self.defaults = defaults
        self.key = key
    }

    func load() -> PendingPayment? {
        defaults.data(forKey: key).flatMap { try? JSONDecoder().decode(PendingPayment.self, from: $0) }
    }

    @discardableResult
    func save(_ pending: PendingPayment) -> Bool {
        guard let data = try? JSONEncoder().encode(pending) else { return false }
        defaults.set(data, forKey: key)
        return load() == pending
    }

    func clear() {
        defaults.removeObject(forKey: key)
    }

    func loadSubmission() -> PendingPaymentSubmission? {
        defaults.data(forKey: submissionKey).flatMap {
            try? JSONDecoder().decode(PendingPaymentSubmission.self, from: $0)
        }
    }

    @discardableResult
    func saveSubmission(_ submission: PendingPaymentSubmission) -> Bool {
        guard let data = try? JSONEncoder().encode(submission) else {
            return false
        }
        defaults.set(data, forKey: submissionKey)
        return loadSubmission() == submission
    }

    func clearSubmission() {
        defaults.removeObject(forKey: submissionKey)
    }
}

@MainActor
final class PaymentCoordinator: ObservableObject {
    @Published private(set) var phase: PaymentPhase = .idle

    private let feature: PaymentFeature
    private let gateway: any PaymentGateway
    private let pendingStore: PendingPaymentStore

    init(
        feature: PaymentFeature,
        gateway: any PaymentGateway,
        userID: String? = nil,
        pendingStore: PendingPaymentStore? = nil
    ) {
        self.feature = feature
        self.gateway = gateway
        let scope = userID.map { value in
            SHA256.hash(data: Data(value.utf8)).prefix(8).map { String(format: "%02x", $0) }.joined()
        } ?? "anonymous"
        self.pendingStore = pendingStore ?? PendingPaymentStore(key: "payments.pending-order.\(scope).\(feature.rawValue)")
    }

    @discardableResult
    func submit(_ request: PaymentRequest, idempotencyKey: String = UUID().uuidString) async -> URL? {
        guard !phase.isBusy else { return nil }
        guard request.feature == feature else {
            phase = .failed(PaymentGatewayError.featureMismatch.localizedDescription)
            return nil
        }
        if let pending = pendingStore.load(), pending.feature == feature {
            await reconcile(orderID: pending.orderID)
            return nil
        }
        let requestFingerprint = Self.fingerprint(for: request)
        let persistedSubmission = pendingStore.loadSubmission()
        let resolvedIdempotencyKey: String
        if let persistedSubmission {
            guard persistedSubmission.feature == feature,
                  persistedSubmission.requestFingerprint == requestFingerprint else {
                phase = .failed(
                    "上一次建单结果尚未确认，请使用相同的账户、金额和支付方式重试"
                )
                return nil
            }
            resolvedIdempotencyKey = persistedSubmission.idempotencyKey
        } else {
            let submission = PendingPaymentSubmission(
                feature: feature,
                idempotencyKey: idempotencyKey,
                requestFingerprint: requestFingerprint
            )
            guard pendingStore.saveSubmission(submission) else {
                phase = .failed("无法安全保存支付请求状态，未发起建单请求")
                return nil
            }
            resolvedIdempotencyKey = idempotencyKey
        }
        var recoverableOrderID: String?
        phase = .creating
        do {
            let order = try await gateway.createOrder(
                request: request,
                idempotencyKey: resolvedIdempotencyKey
            )
            recoverableOrderID = order.id
            guard pendingStore.save(PendingPayment(
                feature: feature,
                orderID: order.id
            )) else {
                phase = .unknown(
                    order.id,
                    "订单已创建但本机状态未能安全保存，请勿重复提交"
                )
                return nil
            }
            pendingStore.clearSubmission()
            if let externalURL = order.externalURL {
                phase = .awaitingExternal(order.id)
                return externalURL
            }
            phase = .confirming(order.id)
            let confirmation = try await gateway.confirm(orderID: order.id, authorization: request.authorization)
            await apply(confirmation, orderID: order.id, reconcilePending: true)
            return nil
        } catch is CancellationError {
            if let recoverableOrderID {
                phase = .unknown(
                    recoverableOrderID,
                    "操作已中断，订单结果待核验，请勿重复提交"
                )
            } else {
                phase = .cancelled
            }
            return nil
        } catch {
            if let recoverableOrderID {
                phase = .unknown(
                    recoverableOrderID,
                    "订单已创建但结果未确认，请稍后核验，勿重复提交"
                )
            } else {
                if Self.isDefinitePreflightFailure(error) {
                    pendingStore.clearSubmission()
                }
                phase = .failed(Self.safeInitialFailureMessage(error))
            }
            return nil
        }
    }

    func resumePendingOrder() async {
        guard let pending = pendingStore.load(), pending.feature == feature else { return }
        await reconcile(orderID: pending.orderID)
    }

    func resumeExternalReturn() async {
        guard case let .awaitingExternal(orderID) = phase else {
            await resumePendingOrder()
            return
        }
        await reconcile(orderID: orderID)
    }

    func cancel() async {
        let orderID: String?
        switch phase {
        case let .confirming(id),
             let .awaitingExternal(id),
             let .reconciling(id),
             let .unknown(id, _):
            orderID = id
        default: orderID = pendingStore.load()?.orderID
        }
        if let orderID {
            await gateway.cancel(orderID: orderID)
            pendingStore.clearSubmission()
        }
        pendingStore.clear()
        phase = .cancelled
    }

    func reset() {
        guard !phase.isBusy else { return }
        phase = .idle
    }

    private func reconcile(orderID: String) async {
        phase = .reconciling(orderID)
        do {
            await apply(try await gateway.status(orderID: orderID), orderID: orderID, reconcilePending: false)
        } catch {
            phase = .unknown(
                orderID,
                "订单状态暂时无法核验，请稍后重试，勿重复提交"
            )
        }
    }

    private static func safeInitialFailureMessage(_ error: Error) -> String {
        guard let gatewayError = error as? PaymentGatewayError else {
            return "支付服务暂不可用，未发起扣款"
        }
        switch gatewayError {
        case .safetyServiceUnavailable,
             .timedOut,
             .invalidResponse,
             .featureMismatch:
            return gatewayError.localizedDescription
        case .server:
            return "支付服务暂不可用，未发起扣款"
        }
    }

    private static func isDefinitePreflightFailure(_ error: Error) -> Bool {
        guard let gatewayError = error as? PaymentGatewayError else {
            return false
        }
        switch gatewayError {
        case .safetyServiceUnavailable, .featureMismatch:
            return true
        case .timedOut, .invalidResponse, .server:
            return false
        }
    }

    private static func fingerprint(for request: PaymentRequest) -> String {
        // Authorization is intentionally excluded: it is transient confirmation
        // material and must never be persisted, even as part of an attempt record.
        let fields = [
            "v1",
            request.feature.rawValue,
            request.method.rawValue,
            request.amount.text,
            request.accountID,
            request.accountLabel
        ]
        let canonical = fields.map { field in
            "\(field.utf8.count):\(field)"
        }.joined(separator: "|")
        return SHA256.hash(data: Data(canonical.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }

    private func apply(_ status: PaymentOrderStatus, orderID: String, reconcilePending: Bool) async {
        switch status {
        case let .confirmed(message):
            pendingStore.clear()
            pendingStore.clearSubmission()
            phase = .succeeded(orderID, message)
        case let .rejected(message):
            pendingStore.clear()
            pendingStore.clearSubmission()
            phase = .failed(message)
        case let .pending(message), let .unknown(message):
            if reconcilePending {
                await reconcile(orderID: orderID)
            } else {
                phase = .unknown(orderID, message)
            }
        }
    }
}

actor DemoPaymentGateway: PaymentGateway {
    enum Mode: Sendable {
        case success
        case rejected
        case unknown
        case timeout
    }

    private let mode: Mode
    private var orders: [String: PaymentRequest] = [:]
    private var orderByIdempotencyKey: [String: String] = [:]
    private var sequence = 0

    init(mode: Mode = .success) {
        self.mode = mode
    }

    func createOrder(request: PaymentRequest, idempotencyKey: String) async throws -> PaymentOrder {
        if mode == .timeout { throw PaymentGatewayError.timedOut }
        if let existing = orderByIdempotencyKey[idempotencyKey] {
            return PaymentOrder(id: existing, externalURL: externalURL(for: request, orderID: existing))
        }
        sequence += 1
        let prefix = switch request.feature {
        case .cardRecharge: "MOCK-CARD"
        case .bathroom: "MOCK-BATH"
        case .electricity: "MOCK-ELEC"
        }
        let orderID = "\(prefix)-\(String(format: "%04d", sequence))"
        orders[orderID] = request
        orderByIdempotencyKey[idempotencyKey] = orderID
        return PaymentOrder(id: orderID, externalURL: externalURL(for: request, orderID: orderID))
    }

    func confirm(orderID: String, authorization: String?) async throws -> PaymentOrderStatus {
        guard let request = orders[orderID] else { throw PaymentGatewayError.invalidResponse }
        if request.method == .campusAccount,
           (authorization?.count != 6 || authorization?.allSatisfy({ $0.isNumber }) != true) {
            return .rejected("支付密码格式错误")
        }
        return .pending("订单已提交，正在核验服务端结果")
    }

    func status(orderID: String) async throws -> PaymentOrderStatus {
        guard orders[orderID] != nil else { throw PaymentGatewayError.invalidResponse }
        switch mode {
        case .success: return .confirmed("服务端已确认支付成功")
        case .rejected: return .rejected("服务端拒绝了本次支付")
        case .unknown: return .unknown("服务端暂未确认结果，请稍后查询")
        case .timeout: throw PaymentGatewayError.timedOut
        }
    }

    func cancel(orderID: String) async {
        orders.removeValue(forKey: orderID)
    }

    private func externalURL(for request: PaymentRequest, orderID: String) -> URL? {
        guard request.method == .alipay else { return nil }
        return URL(string: "alipays://platformapi/startapp?appId=2019090967125695&order=\(orderID)")
    }
}

struct SafetyBlockedPaymentGateway: PaymentGateway {
    func createOrder(request: PaymentRequest, idempotencyKey: String) async throws -> PaymentOrder {
        throw PaymentGatewayError.safetyServiceUnavailable
    }

    func confirm(orderID: String, authorization: String?) async throws -> PaymentOrderStatus {
        throw PaymentGatewayError.safetyServiceUnavailable
    }

    func status(orderID: String) async throws -> PaymentOrderStatus {
        throw PaymentGatewayError.safetyServiceUnavailable
    }

    func cancel(orderID: String) async { }
}

enum PaymentGatewayFactory {
    static func make(demo: Bool) -> any PaymentGateway {
        if demo {
            let arguments = ProcessInfo.processInfo.arguments
            let mode: DemoPaymentGateway.Mode
            if arguments.contains("--demo-payment-error") { mode = .rejected }
            else if arguments.contains("--demo-payment-unknown") { mode = .unknown }
            else if arguments.contains("--demo-payment-timeout") { mode = .timeout }
            else { mode = .success }
            return DemoPaymentGateway(mode: mode)
        }
        return SafetyBlockedPaymentGateway()
    }
}

struct BathroomPaymentAccount: Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    let phone: String
    let cashBalance: Decimal
    let giftBalance: Decimal
}

struct ElectricityRoom: Identifiable, Equatable, Sendable {
    let id: String
    let campus: String
    let building: String
    let floor: String
    let room: String
    let balance: Decimal?
    let information: String?

    var label: String { "\(campus) · \(building) · \(floor) · \(room)" }

    init(
        id: String,
        campus: String,
        building: String,
        floor: String,
        room: String,
        balance: Decimal?,
        information: String? = nil
    ) {
        self.id = id
        self.campus = campus
        self.building = building
        self.floor = floor
        self.room = room
        self.balance = balance
        self.information = information
    }
}

enum PaymentDemoCatalog {
    static let cardAccountID = "mock-campus-card-main"
    static let cardAccountLabel = "主钱包 01"
    static let cardBalance = Decimal(string: "126.35")!
    static let phone = "13800000000"
    static let bathrooms = [
        BathroomPaymentAccount(id: "bath-zhuyuan", name: "竹园/龙河浴室", phone: phone, cashBalance: 18.60, giftBalance: 2.00),
        BathroomPaymentAccount(id: "bath-juyuan", name: "桔园/蕙园浴室", phone: phone, cashBalance: 12.30, giftBalance: 1.50),
        BathroomPaymentAccount(id: "bath-graduate", name: "研究生公寓浴室", phone: phone, cashBalance: 8.00, giftBalance: 0)
    ]
    static let electricityRooms = [
        ElectricityRoom(id: "qy-zhu-3-305", campus: "磬苑校区", building: "竹园", floor: "3 层", room: "305", balance: 20.00),
        ElectricityRoom(id: "qy-ju-5-512", campus: "磬苑校区", building: "桔园", floor: "5 层", room: "512", balance: 36.40),
        ElectricityRoom(id: "lh-north-2-203", campus: "龙河校区", building: "北楼", floor: "2 层", room: "203", balance: 15.80)
    ]
}
